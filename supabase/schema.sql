-- ============================================================================
-- TIME TRAK — MULTI-COMPANY SUPABASE SCHEMA
-- ============================================================================
-- Run this whole file once in the Supabase SQL Editor of a NEW project
-- (Dashboard → SQL Editor → New query → paste → Run).
-- It is safe to run again: every object is created idempotently.
--
-- Roles in the system
--   • Platform (super) admin  – row in public.platform_admins. Reviews company
--                               registration requests and can see every company,
--                               every member and all tracking data.
--   • Company admin           – users.role = 'admin' inside an APPROVED company.
--                               Invites members and sees their tracking data.
--   • Member                  – users.role = 'member'. Tracks time with the
--                               desktop app and sees only their own data.
--
-- Flow
--   1. Anyone signs in with Google → a profile row is created in public.users
--      (no company yet).
--   2. The user either
--        a) registers a company  → request_company()  → status 'pending', or
--        b) accepts an invitation → accept_invitation(token).
--   3. A platform admin approves the request → approve_company(); the requester
--      becomes that company's admin.
--   4. The company admin invites people → create_invitation() (or the
--      `invite-member` Edge Function, which also sends the e-mail).
--   5. The invitee opens the link, signs in, accepts, downloads the desktop app
--      and starts tracking. Every tracking row is stamped with the member's
--      company_id automatically by a trigger.
--
-- Security
--   Row Level Security is ENABLED on every table. Privileged changes (roles,
--   company membership, approvals) only happen through SECURITY DEFINER
--   functions below, so the anon key can safely ship inside the apps.
--
-- AFTER RUNNING: scroll to section 12 and add your platform admin e-mail.
-- ============================================================================


-- ============================================================================
-- 1. TYPES
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('admin', 'member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_status') THEN
        CREATE TYPE public.company_status AS ENUM ('pending', 'approved', 'rejected', 'suspended');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invitation_status') THEN
        CREATE TYPE public.invitation_status AS ENUM ('pending', 'accepted', 'declined', 'revoked', 'expired');
    END IF;
END$$;


-- ============================================================================
-- 2. CORE TABLES: users, companies, platform admins, invitations
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.users (
    id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email             TEXT NOT NULL UNIQUE,
    name              TEXT,
    avatar_url        TEXT,
    role              public.user_role NOT NULL DEFAULT 'member',
    company_id        UUID,
    joined_company_at TIMESTAMPTZ,
    is_active         BOOLEAN NOT NULL DEFAULT true,
    last_login_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.companies (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name             TEXT NOT NULL CHECK (char_length(trim(name)) BETWEEN 2 AND 120),
    slug             TEXT NOT NULL UNIQUE,
    website          TEXT,
    industry         TEXT,
    company_size     TEXT,
    country          TEXT,
    phone            TEXT,
    description      TEXT,
    status           public.company_status NOT NULL DEFAULT 'pending',
    created_by       UUID REFERENCES public.users(id) ON DELETE SET NULL,
    reviewed_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    reviewed_at      TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- users.company_id → companies (added separately because of the circular FK)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'users_company_id_fkey'
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_company_id_fkey
            FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE SET NULL;
    END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);
CREATE INDEX IF NOT EXISTS idx_users_email_lower ON public.users(lower(email));
CREATE INDEX IF NOT EXISTS idx_companies_status ON public.companies(status);
CREATE INDEX IF NOT EXISTS idx_companies_created_by ON public.companies(created_by);

-- A user can only have one pending registration request at a time
CREATE UNIQUE INDEX IF NOT EXISTS uq_companies_one_pending_per_user
    ON public.companies(created_by) WHERE status = 'pending';

-- Platform (super) admins
CREATE TABLE IF NOT EXISTS public.platform_admins (
    user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- E-mails that are promoted to platform admin automatically on sign-in
-- (see section 12). Not readable by app users.
CREATE TABLE IF NOT EXISTS public.platform_admin_emails (
    email      TEXT PRIMARY KEY CHECK (email = lower(email)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Company invitations
CREATE TABLE IF NOT EXISTS public.company_invitations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email       TEXT NOT NULL CHECK (email = lower(email)),
    role        public.user_role NOT NULL DEFAULT 'member',
    token       TEXT NOT NULL UNIQUE
                DEFAULT replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
    status      public.invitation_status NOT NULL DEFAULT 'pending',
    invited_by  UUID REFERENCES public.users(id) ON DELETE SET NULL,
    accepted_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    accepted_at TIMESTAMPTZ,
    expires_at  TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '14 days'),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invitations_company ON public.company_invitations(company_id);
CREATE INDEX IF NOT EXISTS idx_invitations_email ON public.company_invitations(email);
CREATE UNIQUE INDEX IF NOT EXISTS uq_invitations_pending
    ON public.company_invitations(company_id, email) WHERE status = 'pending';


-- ============================================================================
-- 3. TRACKING TABLES (written by the desktop app, read by web + admins)
-- ============================================================================
-- company_id on every row is filled by a trigger from the owner's profile,
-- so clients never send it and cannot forge it.

CREATE TABLE IF NOT EXISTS public.attendance_sessions (
    id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id                 UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    check_in_time              TIMESTAMPTZ NOT NULL,
    check_out_time             TIMESTAMPTZ,
    check_in_time_utc          TIMESTAMPTZ NOT NULL,
    check_out_time_utc         TIMESTAMPTZ,
    check_in_source            TEXT NOT NULL DEFAULT 'manual',
    check_out_source           TEXT,
    total_work_seconds         INTEGER DEFAULT 0,
    is_closed                  BOOLEAN NOT NULL DEFAULT false,
    last_seen_time             TIMESTAMPTZ,
    continuation_of_session_id UUID REFERENCES public.attendance_sessions(id) ON DELETE SET NULL,
    continuation_reason        TEXT,
    original_timezone          TEXT,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at                  TIMESTAMPTZ,
    is_deleted                 BOOLEAN NOT NULL DEFAULT false,
    local_id                   TEXT
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON public.attendance_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_company_user ON public.attendance_sessions(company_id, user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_check_in_utc ON public.attendance_sessions(user_id, check_in_time_utc DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_sessions_open ON public.attendance_sessions(user_id) WHERE is_closed = false AND is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_sessions_continuation ON public.attendance_sessions(continuation_of_session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_local_id ON public.attendance_sessions(local_id);

CREATE TABLE IF NOT EXISTS public.break_periods (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id               UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    user_id                  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id               UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    break_start_time         TIMESTAMPTZ NOT NULL,
    break_end_time           TIMESTAMPTZ,
    break_start_time_utc     TIMESTAMPTZ NOT NULL,
    break_end_time_utc       TIMESTAMPTZ,
    duration_seconds         INTEGER DEFAULT 0,
    continuation_of_break_id UUID REFERENCES public.break_periods(id) ON DELETE SET NULL,
    note                     TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at                TIMESTAMPTZ,
    is_deleted               BOOLEAN NOT NULL DEFAULT false,
    local_id                 TEXT
);

CREATE INDEX IF NOT EXISTS idx_breaks_session_id ON public.break_periods(session_id);
CREATE INDEX IF NOT EXISTS idx_breaks_user_id ON public.break_periods(user_id);
CREATE INDEX IF NOT EXISTS idx_breaks_company_user ON public.break_periods(company_id, user_id);
CREATE INDEX IF NOT EXISTS idx_breaks_start_time ON public.break_periods(break_start_time);
CREATE INDEX IF NOT EXISTS idx_breaks_local_id ON public.break_periods(local_id);

CREATE TABLE IF NOT EXISTS public.app_activities (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id       UUID REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    user_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id       UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    app_name         TEXT NOT NULL,
    window_title     TEXT,
    bundle_id        TEXT,
    start_time       TIMESTAMPTZ NOT NULL,
    end_time         TIMESTAMPTZ,
    start_time_utc   TIMESTAMPTZ NOT NULL,
    end_time_utc     TIMESTAMPTZ,
    duration_seconds INTEGER DEFAULT 0,
    activity_type    TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at        TIMESTAMPTZ,
    is_deleted       BOOLEAN NOT NULL DEFAULT false,
    local_id         TEXT
);

CREATE INDEX IF NOT EXISTS idx_activities_session_time ON public.app_activities(session_id, start_time_utc) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_activities_user_time ON public.app_activities(user_id, start_time_utc DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_activities_company_user ON public.app_activities(company_id, user_id);
CREATE INDEX IF NOT EXISTS idx_activities_user_app ON public.app_activities(user_id, app_name, start_time_utc) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_activities_local_id ON public.app_activities(local_id);

CREATE TABLE IF NOT EXISTS public.work_during_sleep_periods (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id           UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    user_id              UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id           UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    sleep_start_time     TIMESTAMPTZ NOT NULL,
    wake_time            TIMESTAMPTZ NOT NULL,
    sleep_start_time_utc TIMESTAMPTZ NOT NULL,
    wake_time_utc        TIMESTAMPTZ NOT NULL,
    duration_seconds     INTEGER NOT NULL,
    note                 TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at            TIMESTAMPTZ,
    is_deleted           BOOLEAN NOT NULL DEFAULT false,
    local_id             TEXT
);

CREATE INDEX IF NOT EXISTS idx_sleep_session_id ON public.work_during_sleep_periods(session_id);
CREATE INDEX IF NOT EXISTS idx_sleep_user_id ON public.work_during_sleep_periods(user_id);
CREATE INDEX IF NOT EXISTS idx_sleep_company_user ON public.work_during_sleep_periods(company_id, user_id);
CREATE INDEX IF NOT EXISTS idx_sleep_start_time ON public.work_during_sleep_periods(sleep_start_time);
CREATE INDEX IF NOT EXISTS idx_sleep_local_id ON public.work_during_sleep_periods(local_id);

CREATE TABLE IF NOT EXISTS public.session_continuations (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_session_id   UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    new_session_id        UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    user_id               UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id            UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    continuation_type     TEXT NOT NULL,
    split_timestamp_utc   TIMESTAMPTZ NOT NULL,
    split_timestamp_local TIMESTAMPTZ NOT NULL,
    metadata              TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at             TIMESTAMPTZ,
    is_deleted            BOOLEAN NOT NULL DEFAULT false,
    local_id              TEXT
);

CREATE INDEX IF NOT EXISTS idx_continuations_original ON public.session_continuations(original_session_id);
CREATE INDEX IF NOT EXISTS idx_continuations_new ON public.session_continuations(new_session_id);
CREATE INDEX IF NOT EXISTS idx_continuations_user_id ON public.session_continuations(user_id);

CREATE TABLE IF NOT EXISTS public.event_log (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id   UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    event_type   TEXT NOT NULL,
    event_source TEXT NOT NULL,
    timestamp    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata     TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at    TIMESTAMPTZ,
    is_deleted   BOOLEAN NOT NULL DEFAULT false,
    local_id     TEXT
);

CREATE INDEX IF NOT EXISTS idx_event_log_user_time ON public.event_log(user_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_event_log_type ON public.event_log(event_type);

CREATE TABLE IF NOT EXISTS public.sync_queue (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id  UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    table_name  TEXT NOT NULL,
    record_id   UUID NOT NULL,
    operation   TEXT NOT NULL CHECK (operation IN ('insert', 'update', 'delete')),
    data        JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at   TIMESTAMPTZ,
    retry_count INTEGER DEFAULT 0,
    last_error  TEXT
);

CREATE INDEX IF NOT EXISTS idx_sync_queue_user_id ON public.sync_queue(user_id);


-- ============================================================================
-- 4. ACCESS HELPERS (used by RLS policies and RPCs)
-- ============================================================================
-- SECURITY DEFINER so policies on public.users do not recurse.

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT EXISTS (SELECT 1 FROM public.platform_admins WHERE user_id = auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.current_company_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT company_id FROM public.users WHERE id = auth.uid();
$$;

-- True only for an admin of an APPROVED company
CREATE OR REPLACE FUNCTION public.is_company_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.users u
        JOIN public.companies c ON c.id = u.company_id
        WHERE u.id = auth.uid()
          AND u.role = 'admin'
          AND u.is_active
          AND c.status = 'approved'
    );
$$;

-- Can the caller administer the given company?
CREATE OR REPLACE FUNCTION public.can_manage_company(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT public.is_super_admin()
        OR (p_company_id IS NOT NULL
            AND p_company_id = public.current_company_id()
            AND public.is_company_admin());
$$;

-- Can the caller see the given user's tracking data?
CREATE OR REPLACE FUNCTION public.can_view_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT p_user_id = auth.uid()
        OR public.is_super_admin()
        OR EXISTS (
            SELECT 1 FROM public.users t
            WHERE t.id = p_user_id
              AND t.company_id IS NOT NULL
              AND public.can_manage_company(t.company_id)
        );
$$;

-- Internal: allow the next statements in this transaction to change
-- protected columns (role, company_id, …). Only SECURITY DEFINER RPCs call it.
CREATE OR REPLACE FUNCTION public._allow_privileged_write()
RETURNS VOID
LANGUAGE sql VOLATILE
AS $$
    SELECT set_config('app.privileged_write', 'on', true);
$$;


-- ============================================================================
-- 5. TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql SET search_path = public
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'users', 'companies', 'company_invitations', 'attendance_sessions',
        'break_periods', 'app_activities', 'work_during_sleep_periods',
        'session_continuations', 'event_log', 'sync_queue'
    ] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_%1$s_updated_at ON public.%1$I', t);
        EXECUTE format(
            'CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON public.%1$I
             FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()', t);
    END LOOP;
END$$;

-- Stamp company_id on tracking rows from the owner's profile.
-- Clients can never set or change it themselves.
CREATE OR REPLACE FUNCTION public.set_row_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF current_setting('app.privileged_write', true) = 'on' THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        NEW.company_id := (SELECT company_id FROM public.users WHERE id = NEW.user_id);
    ELSE
        NEW.company_id := OLD.company_id;
    END IF;
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'attendance_sessions', 'break_periods', 'app_activities',
        'work_during_sleep_periods', 'session_continuations', 'event_log', 'sync_queue'
    ] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_%1$s_company ON public.%1$I', t);
        EXECUTE format(
            'CREATE TRIGGER trg_%1$s_company BEFORE INSERT OR UPDATE ON public.%1$I
             FOR EACH ROW EXECUTE FUNCTION public.set_row_company_id()', t);
    END LOOP;
END$$;

-- Users may edit their own name / avatar / last_login_at, but never their
-- role, company, active flag or e-mail. Those change only through RPCs.
CREATE OR REPLACE FUNCTION public.protect_user_columns()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    -- RPCs, the auth trigger (no JWT) and platform admins are trusted
    IF current_setting('app.privileged_write', true) = 'on'
       OR auth.uid() IS NULL
       OR public.is_super_admin() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        NEW.role := 'member';
        NEW.company_id := NULL;
        NEW.joined_company_at := NULL;
        NEW.is_active := true;
        NEW.email := lower(NEW.email);
    ELSE
        NEW.id := OLD.id;
        NEW.email := OLD.email;
        NEW.role := OLD.role;
        NEW.company_id := OLD.company_id;
        NEW.joined_company_at := OLD.joined_company_at;
        NEW.is_active := OLD.is_active;
        NEW.created_at := OLD.created_at;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_protect ON public.users;
CREATE TRIGGER trg_users_protect
    BEFORE INSERT OR UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.protect_user_columns();

-- Create the profile row when someone signs up (Google OAuth or otherwise)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_meta JSONB := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
    v_email TEXT := lower(NEW.email);
BEGIN
    INSERT INTO public.users (id, email, name, avatar_url, last_login_at)
    VALUES (
        NEW.id,
        v_email,
        COALESCE(
            NULLIF(v_meta->>'full_name', ''),
            NULLIF(v_meta->>'name', ''),
            split_part(v_email, '@', 1)
        ),
        COALESCE(v_meta->>'avatar_url', v_meta->>'picture'),
        NOW()
    )
    ON CONFLICT (id) DO UPDATE
        SET email = EXCLUDED.email,
            name = COALESCE(public.users.name, EXCLUDED.name),
            avatar_url = COALESCE(EXCLUDED.avatar_url, public.users.avatar_url);

    IF EXISTS (SELECT 1 FROM public.platform_admin_emails WHERE email = v_email) THEN
        INSERT INTO public.platform_admins (user_id) VALUES (NEW.id)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Never block sign-up; the app re-creates the profile if it is missing
    RAISE WARNING 'handle_new_user failed for %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Promote existing accounts when an e-mail is added to platform_admin_emails
CREATE OR REPLACE FUNCTION public.sync_platform_admin_email()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    INSERT INTO public.platform_admins (user_id)
    SELECT id FROM auth.users WHERE lower(email) = NEW.email
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_platform_admin_email ON public.platform_admin_emails;
CREATE TRIGGER trg_platform_admin_email
    AFTER INSERT ON public.platform_admin_emails
    FOR EACH ROW EXECUTE FUNCTION public.sync_platform_admin_email();


-- ============================================================================
-- 6. ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.users                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_admins           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_admin_emails     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_invitations       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_sessions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.break_periods             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_activities            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_during_sleep_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_continuations     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_log                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_queue                ENABLE ROW LEVEL SECURITY;

-- ---- users -----------------------------------------------------------------
DROP POLICY IF EXISTS users_select ON public.users;
CREATE POLICY users_select ON public.users FOR SELECT TO authenticated
    USING (
        id = (SELECT auth.uid())
        OR (SELECT public.is_super_admin())
        OR (company_id IS NOT NULL AND public.can_manage_company(company_id))
    );

DROP POLICY IF EXISTS users_insert_self ON public.users;
CREATE POLICY users_insert_self ON public.users FOR INSERT TO authenticated
    WITH CHECK (id = (SELECT auth.uid()));

DROP POLICY IF EXISTS users_update ON public.users;
CREATE POLICY users_update ON public.users FOR UPDATE TO authenticated
    USING (id = (SELECT auth.uid()) OR (SELECT public.is_super_admin()))
    WITH CHECK (id = (SELECT auth.uid()) OR (SELECT public.is_super_admin()));

-- ---- companies ---------------------------------------------------------------
DROP POLICY IF EXISTS companies_select ON public.companies;
CREATE POLICY companies_select ON public.companies FOR SELECT TO authenticated
    USING (
        (SELECT public.is_super_admin())
        OR id = (SELECT public.current_company_id())
        OR created_by = (SELECT auth.uid())
    );
-- No direct INSERT/UPDATE/DELETE: use request_company(), approve_company(), …

-- ---- platform_admins -----------------------------------------------------------
DROP POLICY IF EXISTS platform_admins_select ON public.platform_admins;
CREATE POLICY platform_admins_select ON public.platform_admins FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()) OR (SELECT public.is_super_admin()));
-- platform_admin_emails: no policies → invisible to app users

-- ---- company_invitations -------------------------------------------------------
DROP POLICY IF EXISTS invitations_select ON public.company_invitations;
CREATE POLICY invitations_select ON public.company_invitations FOR SELECT TO authenticated
    USING (
        public.can_manage_company(company_id)
        OR email = lower((SELECT auth.jwt()) ->> 'email')
    );
-- No direct writes: use create_invitation(), revoke_invitation(), accept_invitation()

-- ---- tracking tables -------------------------------------------------------------
-- Owner: full access to own rows.
-- Company admin: read rows stamped with their company.
-- Platform admin: read everything.
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'attendance_sessions', 'break_periods', 'app_activities',
        'work_during_sleep_periods', 'session_continuations', 'event_log', 'sync_queue'
    ] LOOP
        EXECUTE format('DROP POLICY IF EXISTS %1$s_select ON public.%1$I', t);
        EXECUTE format($p$
            CREATE POLICY %1$s_select ON public.%1$I FOR SELECT TO authenticated
            USING (
                user_id = (SELECT auth.uid())
                OR (SELECT public.is_super_admin())
                OR (company_id IS NOT NULL
                    AND company_id = (SELECT public.current_company_id())
                    AND (SELECT public.is_company_admin()))
            )$p$, t);

        EXECUTE format('DROP POLICY IF EXISTS %1$s_insert ON public.%1$I', t);
        EXECUTE format($p$
            CREATE POLICY %1$s_insert ON public.%1$I FOR INSERT TO authenticated
            WITH CHECK (user_id = (SELECT auth.uid()))$p$, t);

        EXECUTE format('DROP POLICY IF EXISTS %1$s_update ON public.%1$I', t);
        EXECUTE format($p$
            CREATE POLICY %1$s_update ON public.%1$I FOR UPDATE TO authenticated
            USING (user_id = (SELECT auth.uid()))
            WITH CHECK (user_id = (SELECT auth.uid()))$p$, t);

        EXECUTE format('DROP POLICY IF EXISTS %1$s_delete ON public.%1$I', t);
        EXECUTE format($p$
            CREATE POLICY %1$s_delete ON public.%1$I FOR DELETE TO authenticated
            USING (user_id = (SELECT auth.uid()) OR (SELECT public.is_super_admin()))$p$, t);
    END LOOP;
END$$;


-- ============================================================================
-- 7. APP CONTEXT RPC (one call on every app start)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_my_context()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_uid   UUID := auth.uid();
    v_user  public.users;
    v_email TEXT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_user FROM public.users WHERE id = v_uid;
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;

    RETURN jsonb_build_object(
        'user', to_jsonb(v_user),
        'is_super_admin', public.is_super_admin(),
        'company', (
            SELECT to_jsonb(c) FROM public.companies c WHERE c.id = v_user.company_id
        ),
        -- Latest registration request made by this user (for the status screen)
        'latest_request', (
            SELECT to_jsonb(c) FROM public.companies c
            WHERE c.created_by = v_uid
            ORDER BY c.created_at DESC
            LIMIT 1
        ),
        'invitations', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'id', i.id,
                       'token', i.token,
                       'email', i.email,
                       'role', i.role,
                       'status', i.status,
                       'expires_at', i.expires_at,
                       'created_at', i.created_at,
                       'company_id', c.id,
                       'company_name', c.name,
                       'invited_by_name', inv.name,
                       'invited_by_email', inv.email
                   ) ORDER BY i.created_at DESC)
            FROM public.company_invitations i
            JOIN public.companies c ON c.id = i.company_id
            LEFT JOIN public.users inv ON inv.id = i.invited_by
            WHERE i.email = v_email
              AND i.status = 'pending'
              AND i.expires_at > NOW()
              AND c.status = 'approved'
        ), '[]'::jsonb)
    );
END;
$$;


-- ============================================================================
-- 8. COMPANY REGISTRATION & PLATFORM ADMIN RPCs
-- ============================================================================

CREATE OR REPLACE FUNCTION public.request_company(
    p_name         TEXT,
    p_website      TEXT DEFAULT NULL,
    p_industry     TEXT DEFAULT NULL,
    p_company_size TEXT DEFAULT NULL,
    p_country      TEXT DEFAULT NULL,
    p_phone        TEXT DEFAULT NULL,
    p_description  TEXT DEFAULT NULL
)
RETURNS public.companies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_uid     UUID := auth.uid();
    v_user    public.users;
    v_slug    TEXT;
    v_company public.companies;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_user FROM public.users WHERE id = v_uid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found. Please sign in again.';
    END IF;
    IF v_user.company_id IS NOT NULL THEN
        RAISE EXCEPTION 'You already belong to a company.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.companies WHERE created_by = v_uid AND status = 'pending') THEN
        RAISE EXCEPTION 'You already have a registration request waiting for approval.';
    END IF;
    IF p_name IS NULL OR char_length(trim(p_name)) < 2 THEN
        RAISE EXCEPTION 'Company name must be at least 2 characters.';
    END IF;

    v_slug := trim(both '-' FROM regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'));
    IF v_slug = '' THEN
        v_slug := 'company';
    END IF;
    IF EXISTS (SELECT 1 FROM public.companies WHERE slug = v_slug) THEN
        v_slug := v_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    END IF;

    INSERT INTO public.companies (
        name, slug, website, industry, company_size, country, phone, description, created_by
    ) VALUES (
        trim(p_name), v_slug, NULLIF(trim(p_website), ''), NULLIF(trim(p_industry), ''),
        NULLIF(trim(p_company_size), ''), NULLIF(trim(p_country), ''),
        NULLIF(trim(p_phone), ''), NULLIF(trim(p_description), ''), v_uid
    )
    RETURNING * INTO v_company;

    RETURN v_company;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_company_request(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    DELETE FROM public.companies
    WHERE id = p_company_id
      AND created_by = auth.uid()
      AND status IN ('pending', 'rejected');
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Request not found or can no longer be cancelled.';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_company(p_company_id UUID)
RETURNS public.companies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company public.companies;
    v_owner   public.users;
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Only platform admins can approve companies.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_company FROM public.companies WHERE id = p_company_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Company not found.';
    END IF;
    IF v_company.status = 'approved' THEN
        RETURN v_company;
    END IF;

    SELECT * INTO v_owner FROM public.users WHERE id = v_company.created_by;
    IF FOUND AND v_owner.company_id IS NOT NULL AND v_owner.company_id <> v_company.id THEN
        RAISE EXCEPTION 'The requester (%) already belongs to another company.', v_owner.email;
    END IF;

    PERFORM public._allow_privileged_write();

    UPDATE public.companies
       SET status = 'approved',
           reviewed_by = auth.uid(),
           reviewed_at = NOW(),
           rejection_reason = NULL
     WHERE id = p_company_id
    RETURNING * INTO v_company;

    IF v_owner.id IS NOT NULL THEN
        UPDATE public.users
           SET company_id = v_company.id,
               role = 'admin',
               joined_company_at = COALESCE(joined_company_at, NOW())
         WHERE id = v_owner.id;

        -- Attribute the owner's earlier, company-less tracking to the company
        PERFORM public._attach_orphan_tracking(v_owner.id, v_company.id);
    END IF;

    RETURN v_company;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_company(p_company_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.companies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company public.companies;
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Only platform admins can reject companies.' USING ERRCODE = '42501';
    END IF;

    UPDATE public.companies
       SET status = 'rejected',
           reviewed_by = auth.uid(),
           reviewed_at = NOW(),
           rejection_reason = NULLIF(trim(p_reason), '')
     WHERE id = p_company_id AND status = 'pending'
    RETURNING * INTO v_company;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only pending requests can be rejected.';
    END IF;
    RETURN v_company;
END;
$$;

-- Suspend / reactivate an approved company
CREATE OR REPLACE FUNCTION public.set_company_suspended(p_company_id UUID, p_suspended BOOLEAN)
RETURNS public.companies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company public.companies;
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Only platform admins can change company status.' USING ERRCODE = '42501';
    END IF;

    UPDATE public.companies
       SET status = CASE WHEN p_suspended THEN 'suspended' ELSE 'approved' END::public.company_status,
           reviewed_by = auth.uid(),
           reviewed_at = NOW()
     WHERE id = p_company_id AND status IN ('approved', 'suspended')
    RETURNING * INTO v_company;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only approved or suspended companies can be changed.';
    END IF;
    RETURN v_company;
END;
$$;

-- Permanently delete a company. Members are detached (their accounts and
-- tracking history stay; history keeps company_id = NULL).
CREATE OR REPLACE FUNCTION public.delete_company(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Only platform admins can delete companies.' USING ERRCODE = '42501';
    END IF;

    PERFORM public._allow_privileged_write();
    UPDATE public.users
       SET company_id = NULL, role = 'member', joined_company_at = NULL
     WHERE company_id = p_company_id;
    DELETE FROM public.companies WHERE id = p_company_id;
END;
$$;

-- Company admins edit their own company profile
CREATE OR REPLACE FUNCTION public.update_company_profile(
    p_name         TEXT,
    p_website      TEXT DEFAULT NULL,
    p_industry     TEXT DEFAULT NULL,
    p_company_size TEXT DEFAULT NULL,
    p_country      TEXT DEFAULT NULL,
    p_phone        TEXT DEFAULT NULL,
    p_description  TEXT DEFAULT NULL,
    p_company_id   UUID DEFAULT NULL
)
RETURNS public.companies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company_id UUID := COALESCE(p_company_id, public.current_company_id());
    v_company    public.companies;
BEGIN
    IF NOT public.can_manage_company(v_company_id) THEN
        RAISE EXCEPTION 'Only company admins can edit the company profile.' USING ERRCODE = '42501';
    END IF;
    IF p_name IS NULL OR char_length(trim(p_name)) < 2 THEN
        RAISE EXCEPTION 'Company name must be at least 2 characters.';
    END IF;

    UPDATE public.companies
       SET name = trim(p_name),
           website = NULLIF(trim(p_website), ''),
           industry = NULLIF(trim(p_industry), ''),
           company_size = NULLIF(trim(p_company_size), ''),
           country = NULLIF(trim(p_country), ''),
           phone = NULLIF(trim(p_phone), ''),
           description = NULLIF(trim(p_description), '')
     WHERE id = v_company_id
    RETURNING * INTO v_company;

    RETURN v_company;
END;
$$;

-- Platform dashboard numbers
CREATE OR REPLACE FUNCTION public.get_platform_stats()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Only platform admins can view platform stats.' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'companies_total',     (SELECT COUNT(*) FROM public.companies),
        'companies_pending',   (SELECT COUNT(*) FROM public.companies WHERE status = 'pending'),
        'companies_approved',  (SELECT COUNT(*) FROM public.companies WHERE status = 'approved'),
        'companies_suspended', (SELECT COUNT(*) FROM public.companies WHERE status = 'suspended'),
        'companies_rejected',  (SELECT COUNT(*) FROM public.companies WHERE status = 'rejected'),
        'users_total',         (SELECT COUNT(*) FROM public.users),
        'users_without_company', (SELECT COUNT(*) FROM public.users WHERE company_id IS NULL),
        'working_now', (
            SELECT COUNT(DISTINCT s.user_id) FROM public.attendance_sessions s
            WHERE s.is_closed = false AND s.is_deleted = false
              AND COALESCE(s.last_seen_time, s.check_in_time_utc) > NOW() - INTERVAL '15 minutes'
        )
    );
END;
$$;

-- All companies with counts, for the platform admin console
CREATE OR REPLACE FUNCTION public.get_companies_overview(p_status public.company_status DEFAULT NULL)
RETURNS TABLE (
    id               UUID,
    name             TEXT,
    slug             TEXT,
    website          TEXT,
    industry         TEXT,
    company_size     TEXT,
    country          TEXT,
    phone            TEXT,
    description      TEXT,
    status           public.company_status,
    created_at       TIMESTAMPTZ,
    reviewed_at      TIMESTAMPTZ,
    rejection_reason TEXT,
    created_by       UUID,
    creator_name     TEXT,
    creator_email    TEXT,
    member_count     BIGINT,
    admin_count      BIGINT,
    working_now      BIGINT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Only platform admins can list companies.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        c.id, c.name, c.slug, c.website, c.industry, c.company_size, c.country,
        c.phone, c.description, c.status, c.created_at, c.reviewed_at,
        c.rejection_reason, c.created_by,
        cr.name, cr.email,
        (SELECT COUNT(*) FROM public.users u WHERE u.company_id = c.id),
        (SELECT COUNT(*) FROM public.users u WHERE u.company_id = c.id AND u.role = 'admin'),
        (SELECT COUNT(DISTINCT s.user_id) FROM public.attendance_sessions s
          WHERE s.company_id = c.id AND s.is_closed = false AND s.is_deleted = false
            AND COALESCE(s.last_seen_time, s.check_in_time_utc) > NOW() - INTERVAL '15 minutes')
    FROM public.companies c
    LEFT JOIN public.users cr ON cr.id = c.created_by
    WHERE p_status IS NULL OR c.status = p_status
    ORDER BY (c.status = 'pending') DESC, c.created_at DESC;
END;
$$;


-- ============================================================================
-- 9. MEMBERS & INVITATIONS RPCs
-- ============================================================================

-- Internal: attach a user's company-less tracking rows to a company
CREATE OR REPLACE FUNCTION public._attach_orphan_tracking(p_user_id UUID, p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    PERFORM public._allow_privileged_write();
    UPDATE public.attendance_sessions       SET company_id = p_company_id WHERE user_id = p_user_id AND company_id IS NULL;
    UPDATE public.break_periods             SET company_id = p_company_id WHERE user_id = p_user_id AND company_id IS NULL;
    UPDATE public.app_activities            SET company_id = p_company_id WHERE user_id = p_user_id AND company_id IS NULL;
    UPDATE public.work_during_sleep_periods SET company_id = p_company_id WHERE user_id = p_user_id AND company_id IS NULL;
    UPDATE public.session_continuations     SET company_id = p_company_id WHERE user_id = p_user_id AND company_id IS NULL;
    UPDATE public.event_log                 SET company_id = p_company_id WHERE user_id = p_user_id AND company_id IS NULL;
END;
$$;

-- Team list with live status and hour totals.
-- p_*_start are the caller's LOCAL day/week/month starts converted to UTC.
CREATE OR REPLACE FUNCTION public.get_company_members(
    p_company_id  UUID DEFAULT NULL,
    p_day_start   TIMESTAMPTZ DEFAULT date_trunc('day', NOW()),
    p_week_start  TIMESTAMPTZ DEFAULT date_trunc('week', NOW()),
    p_month_start TIMESTAMPTZ DEFAULT date_trunc('month', NOW())
)
RETURNS TABLE (
    id                  UUID,
    email               TEXT,
    name                TEXT,
    avatar_url          TEXT,
    role                public.user_role,
    is_active           BOOLEAN,
    last_login_at       TIMESTAMPTZ,
    joined_company_at   TIMESTAMPTZ,
    is_working          BOOLEAN,
    is_on_break         BOOLEAN,
    session_started_at  TIMESTAMPTZ,
    last_seen_at        TIMESTAMPTZ,
    today_work_seconds  BIGINT,
    week_work_seconds   BIGINT,
    month_work_seconds  BIGINT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company_id UUID := COALESCE(p_company_id, public.current_company_id());
BEGIN
    IF NOT public.can_manage_company(v_company_id) THEN
        RAISE EXCEPTION 'Only company admins can view the team.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH open_session AS (
        SELECT DISTINCT ON (s.user_id)
               s.user_id, s.id AS session_id, s.check_in_time_utc,
               COALESCE(s.last_seen_time, s.updated_at, s.check_in_time_utc) AS seen
        FROM public.attendance_sessions s
        WHERE s.company_id = v_company_id
          AND s.is_closed = false AND s.is_deleted = false
        ORDER BY s.user_id, s.check_in_time_utc DESC
    ),
    totals AS (
        SELECT s.user_id,
               SUM(s.total_work_seconds) FILTER (WHERE s.check_in_time_utc >= p_day_start)   AS today,
               SUM(s.total_work_seconds) FILTER (WHERE s.check_in_time_utc >= p_week_start)  AS week,
               SUM(s.total_work_seconds) FILTER (WHERE s.check_in_time_utc >= p_month_start) AS month
        FROM public.attendance_sessions s
        WHERE s.company_id = v_company_id
          AND s.is_deleted = false
          AND s.check_in_time_utc >= LEAST(p_day_start, p_week_start, p_month_start)
        GROUP BY s.user_id
    ),
    last_seen AS (
        SELECT s.user_id,
               MAX(COALESCE(s.last_seen_time, s.check_out_time_utc, s.check_in_time_utc)) AS seen
        FROM public.attendance_sessions s
        WHERE s.company_id = v_company_id AND s.is_deleted = false
        GROUP BY s.user_id
    )
    SELECT
        u.id, u.email, u.name, u.avatar_url, u.role, u.is_active,
        u.last_login_at, u.joined_company_at,
        (os.user_id IS NOT NULL AND os.seen > NOW() - INTERVAL '15 minutes') AS is_working,
        (os.user_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.break_periods b
            WHERE b.session_id = os.session_id AND b.break_end_time_utc IS NULL AND b.is_deleted = false
        )) AS is_on_break,
        os.check_in_time_utc,
        ls.seen,
        COALESCE(t.today, 0)::BIGINT,
        COALESCE(t.week, 0)::BIGINT,
        COALESCE(t.month, 0)::BIGINT
    FROM public.users u
    LEFT JOIN open_session os ON os.user_id = u.id
    LEFT JOIN totals t ON t.user_id = u.id
    LEFT JOIN last_seen ls ON ls.user_id = u.id
    WHERE u.company_id = v_company_id
    ORDER BY (u.role = 'admin') DESC, lower(COALESCE(u.name, u.email));
END;
$$;

CREATE OR REPLACE FUNCTION public.create_invitation(
    p_email      TEXT,
    p_role       public.user_role DEFAULT 'member',
    p_company_id UUID DEFAULT NULL
)
RETURNS public.company_invitations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company_id UUID := COALESCE(p_company_id, public.current_company_id());
    v_email      TEXT := lower(trim(p_email));
    v_status     public.company_status;
    v_inv        public.company_invitations;
BEGIN
    IF NOT public.can_manage_company(v_company_id) THEN
        RAISE EXCEPTION 'Only company admins can invite members.' USING ERRCODE = '42501';
    END IF;

    SELECT status INTO v_status FROM public.companies WHERE id = v_company_id;
    IF v_status IS DISTINCT FROM 'approved' THEN
        RAISE EXCEPTION 'Your company must be approved before inviting members.';
    END IF;

    IF v_email IS NULL OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
        RAISE EXCEPTION 'Please enter a valid e-mail address.';
    END IF;

    IF EXISTS (SELECT 1 FROM public.users WHERE lower(email) = v_email AND company_id = v_company_id) THEN
        RAISE EXCEPTION '% is already a member of your company.', v_email;
    END IF;

    -- Re-inviting refreshes the existing pending invitation
    UPDATE public.company_invitations
       SET role = p_role,
           invited_by = auth.uid(),
           expires_at = NOW() + INTERVAL '14 days'
     WHERE company_id = v_company_id AND email = v_email AND status = 'pending'
    RETURNING * INTO v_inv;

    IF NOT FOUND THEN
        INSERT INTO public.company_invitations (company_id, email, role, invited_by)
        VALUES (v_company_id, v_email, p_role, auth.uid())
        RETURNING * INTO v_inv;
    END IF;

    RETURN v_inv;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_invitation(p_invitation_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
BEGIN
    SELECT company_id INTO v_company_id FROM public.company_invitations WHERE id = p_invitation_id;
    IF NOT public.can_manage_company(v_company_id) THEN
        RAISE EXCEPTION 'Only company admins can revoke invitations.' USING ERRCODE = '42501';
    END IF;

    UPDATE public.company_invitations
       SET status = 'revoked'
     WHERE id = p_invitation_id AND status = 'pending';
END;
$$;

-- Details shown on the "You're invited" screen. The token is the secret.
CREATE OR REPLACE FUNCTION public.get_invitation_preview(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_email TEXT;
    v_row   JSONB;
BEGIN
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = auth.uid();

    SELECT jsonb_build_object(
               'id', i.id,
               'token', i.token,
               'email', i.email,
               'role', i.role,
               'status', CASE WHEN i.status = 'pending' AND i.expires_at <= NOW()
                              THEN 'expired'::public.invitation_status ELSE i.status END,
               'expires_at', i.expires_at,
               'created_at', i.created_at,
               'company_id', c.id,
               'company_name', c.name,
               'company_status', c.status,
               'invited_by_name', inv.name,
               'invited_by_email', inv.email,
               'email_matches', i.email = v_email
           )
      INTO v_row
      FROM public.company_invitations i
      JOIN public.companies c ON c.id = i.company_id
      LEFT JOIN public.users inv ON inv.id = i.invited_by
     WHERE i.token = p_token;

    RETURN v_row; -- NULL when the token is unknown
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_invitation(p_token TEXT)
RETURNS public.companies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_uid     UUID := auth.uid();
    v_email   TEXT;
    v_inv     public.company_invitations;
    v_user    public.users;
    v_company public.companies;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_inv FROM public.company_invitations WHERE token = p_token FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This invitation link is invalid.';
    END IF;
    IF v_inv.status <> 'pending' THEN
        RAISE EXCEPTION 'This invitation has already been %.', v_inv.status;
    END IF;
    IF v_inv.expires_at <= NOW() THEN
        UPDATE public.company_invitations SET status = 'expired' WHERE id = v_inv.id;
        RAISE EXCEPTION 'This invitation has expired. Ask your admin to send a new one.';
    END IF;

    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;
    IF v_email IS DISTINCT FROM v_inv.email THEN
        RAISE EXCEPTION 'This invitation was sent to %. Sign in with that Google account to accept it.', v_inv.email;
    END IF;

    SELECT * INTO v_company FROM public.companies WHERE id = v_inv.company_id;
    IF v_company.status <> 'approved' THEN
        RAISE EXCEPTION '% is not active right now.', v_company.name;
    END IF;

    SELECT * INTO v_user FROM public.users WHERE id = v_uid;
    IF v_user.company_id IS NOT NULL AND v_user.company_id <> v_inv.company_id THEN
        RAISE EXCEPTION 'You already belong to another company. Leave it first to join %.', v_company.name;
    END IF;

    PERFORM public._allow_privileged_write();

    IF v_user.company_id IS NULL THEN
        UPDATE public.users
           SET company_id = v_inv.company_id,
               role = v_inv.role,
               is_active = true,
               joined_company_at = NOW()
         WHERE id = v_uid;
        PERFORM public._attach_orphan_tracking(v_uid, v_inv.company_id);
    END IF;

    UPDATE public.company_invitations
       SET status = 'accepted', accepted_by = v_uid, accepted_at = NOW()
     WHERE id = v_inv.id;

    -- A pending registration request is no longer needed
    DELETE FROM public.companies WHERE created_by = v_uid AND status = 'pending';

    RETURN v_company;
END;
$$;

CREATE OR REPLACE FUNCTION public.decline_invitation(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_email TEXT;
BEGIN
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = auth.uid();
    UPDATE public.company_invitations
       SET status = 'declined'
     WHERE token = p_token AND email = v_email AND status = 'pending';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invitation not found.';
    END IF;
END;
$$;

-- Internal: raise if removing/demoting p_user_id would leave the company without an admin
CREATE OR REPLACE FUNCTION public._assert_not_last_admin(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_user public.users;
BEGIN
    SELECT * INTO v_user FROM public.users WHERE id = p_user_id;
    IF v_user.role = 'admin' AND v_user.company_id IS NOT NULL AND (
        SELECT COUNT(*) FROM public.users
        WHERE company_id = v_user.company_id AND role = 'admin' AND is_active
    ) <= 1 THEN
        RAISE EXCEPTION 'A company needs at least one admin. Make someone else an admin first.';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_member_role(p_user_id UUID, p_role public.user_role)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
BEGIN
    SELECT company_id INTO v_company_id FROM public.users WHERE id = p_user_id;
    IF NOT public.can_manage_company(v_company_id) THEN
        RAISE EXCEPTION 'Only company admins can change roles.' USING ERRCODE = '42501';
    END IF;
    IF p_role = 'member' THEN
        PERFORM public._assert_not_last_admin(p_user_id);
    END IF;

    PERFORM public._allow_privileged_write();
    UPDATE public.users SET role = p_role WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_member_active(p_user_id UUID, p_active BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
BEGIN
    SELECT company_id INTO v_company_id FROM public.users WHERE id = p_user_id;
    IF NOT public.can_manage_company(v_company_id) THEN
        RAISE EXCEPTION 'Only company admins can change member status.' USING ERRCODE = '42501';
    END IF;
    IF NOT p_active THEN
        PERFORM public._assert_not_last_admin(p_user_id);
    END IF;

    PERFORM public._allow_privileged_write();
    UPDATE public.users SET is_active = p_active WHERE id = p_user_id;
END;
$$;

-- Remove a member from the company. Their history stays with the company.
CREATE OR REPLACE FUNCTION public.remove_member(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
BEGIN
    SELECT company_id INTO v_company_id FROM public.users WHERE id = p_user_id;
    IF NOT public.can_manage_company(v_company_id) THEN
        RAISE EXCEPTION 'Only company admins can remove members.' USING ERRCODE = '42501';
    END IF;
    PERFORM public._assert_not_last_admin(p_user_id);

    PERFORM public._allow_privileged_write();
    UPDATE public.users
       SET company_id = NULL, role = 'member', joined_company_at = NULL
     WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_company()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF public.current_company_id() IS NULL THEN
        RETURN;
    END IF;
    PERFORM public._assert_not_last_admin(auth.uid());

    PERFORM public._allow_privileged_write();
    UPDATE public.users
       SET company_id = NULL, role = 'member', joined_company_at = NULL
     WHERE id = auth.uid();
END;
$$;

-- Self-service account deletion (removes auth user; profile + tracking cascade)
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid() AND u.role = 'admin' AND u.company_id IS NOT NULL
          AND EXISTS (SELECT 1 FROM public.users o WHERE o.company_id = u.company_id AND o.id <> u.id)
    ) THEN
        PERFORM public._assert_not_last_admin(auth.uid());
    END IF;

    DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;


-- ============================================================================
-- 10. MONTHLY SUMMARY (materialized view + access-checked readers)
-- ============================================================================
-- Requires PostgreSQL 14+ (multirange support). Supabase projects run 15+.

CREATE OR REPLACE FUNCTION public.get_local_timestamp_robust(
    p_utc_ts TIMESTAMPTZ,
    p_tz TEXT,
    p_local_ts_hint TIMESTAMPTZ
)
RETURNS TIMESTAMP
LANGUAGE plpgsql IMMUTABLE SET search_path = public
AS $$
DECLARE
    v_tz_name TEXT := p_tz;
    v_offset INTERVAL;
BEGIN
    IF p_utc_ts IS NULL THEN
        RETURN NULL;
    END IF;

    -- "IST" from Dart's DateTime.timeZoneName is ambiguous in Postgres
    IF v_tz_name = 'IST' THEN
        v_tz_name := 'Asia/Kolkata';
    END IF;

    BEGIN
        IF v_tz_name IS NOT NULL AND v_tz_name <> '' THEN
            RETURN p_utc_ts AT TIME ZONE v_tz_name;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        -- unknown zone name → fall through
    END;

    -- Fallback: the local column may hold the wall clock stored as UTC
    IF p_local_ts_hint IS NOT NULL THEN
        v_offset := p_local_ts_hint - p_utc_ts;
        IF ABS(EXTRACT(EPOCH FROM v_offset)) > 300 THEN
            RETURN (p_utc_ts + v_offset)::timestamp;
        END IF;
    END IF;

    RETURN p_utc_ts AT TIME ZONE 'UTC';
END;
$$;

-- Net work seconds (sessions minus breaks) for one LOCAL date
CREATE OR REPLACE FUNCTION public.get_daily_work_seconds_local_final(p_user_id UUID, p_local_date DATE)
RETURNS INTEGER
LANGUAGE plpgsql STABLE SET search_path = public
AS $$
DECLARE
    v_start TIMESTAMP := p_local_date::timestamp;
    v_end   TIMESTAMP := p_local_date::timestamp + INTERVAL '1 day';
    v_sessions tsmultirange;
    v_breaks   tsmultirange;
BEGIN
    SELECT COALESCE(range_agg(tsrange(lo, hi, '[)')), '{}'::tsmultirange) INTO v_sessions
    FROM (
        SELECT GREATEST(public.get_local_timestamp_robust(check_in_time_utc, original_timezone, check_in_time), v_start) AS lo,
                   LEAST(COALESCE(
                       public.get_local_timestamp_robust(check_out_time_utc, original_timezone, check_out_time),
                       public.get_local_timestamp_robust(NOW(), original_timezone, check_in_time + (NOW() - check_in_time_utc))
                   ), v_end) AS hi
        FROM public.attendance_sessions
        WHERE user_id = p_user_id
          AND is_deleted = false
          AND check_in_time_utc < (v_end AT TIME ZONE 'UTC') + INTERVAL '1 day'
          AND (check_out_time_utc IS NULL OR check_out_time_utc > (v_start AT TIME ZONE 'UTC') - INTERVAL '1 day')
    ) x
    WHERE lo < hi;

    SELECT COALESCE(range_agg(tsrange(lo, hi, '[)')), '{}'::tsmultirange) INTO v_breaks
    FROM (
        SELECT GREATEST(public.get_local_timestamp_robust(bp.break_start_time_utc, s.original_timezone, bp.break_start_time), v_start) AS lo,
                   LEAST(COALESCE(
                       public.get_local_timestamp_robust(bp.break_end_time_utc, s.original_timezone, bp.break_end_time),
                       public.get_local_timestamp_robust(NOW(), s.original_timezone, s.check_in_time + (NOW() - s.check_in_time_utc))
                   ), v_end) AS hi
        FROM public.break_periods bp
        JOIN public.attendance_sessions s ON bp.session_id = s.id
        WHERE s.user_id = p_user_id
          AND s.is_deleted = false
          AND bp.is_deleted = false
          AND bp.break_start_time_utc < (v_end AT TIME ZONE 'UTC') + INTERVAL '1 day'
    ) x
    WHERE lo < hi;

    RETURN (
        SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (upper(rng) - lower(rng)))), 0)::INTEGER
        FROM unnest(v_sessions - v_breaks) AS rng
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_daily_sleep_seconds_local_final(p_user_id UUID, p_local_date DATE)
RETURNS INTEGER
LANGUAGE plpgsql STABLE SET search_path = public
AS $$
DECLARE
    v_start TIMESTAMP := p_local_date::timestamp;
    v_end   TIMESTAMP := p_local_date::timestamp + INTERVAL '1 day';
    v_sleep tsmultirange;
BEGIN
    SELECT COALESCE(range_agg(tsrange(lo, hi, '[)')), '{}'::tsmultirange) INTO v_sleep
    FROM (
        SELECT GREATEST(public.get_local_timestamp_robust(w.sleep_start_time_utc, s.original_timezone, w.sleep_start_time), v_start) AS lo,
                   LEAST(public.get_local_timestamp_robust(w.wake_time_utc, s.original_timezone, w.wake_time), v_end) AS hi
        FROM public.work_during_sleep_periods w
        JOIN public.attendance_sessions s ON w.session_id = s.id
        WHERE s.user_id = p_user_id
          AND s.is_deleted = false
          AND w.is_deleted = false
          AND w.sleep_start_time_utc < (v_end AT TIME ZONE 'UTC') + INTERVAL '1 day'
          AND w.wake_time_utc > (v_start AT TIME ZONE 'UTC') - INTERVAL '1 day'
    ) x
    WHERE lo < hi;

    RETURN (
        SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (upper(rng) - lower(rng)))), 0)::INTEGER
        FROM unnest(v_sleep) AS rng
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_daily_break_seconds_local_final(p_user_id UUID, p_local_date DATE)
RETURNS INTEGER
LANGUAGE plpgsql STABLE SET search_path = public
AS $$
DECLARE
    v_start  TIMESTAMP := p_local_date::timestamp;
    v_end    TIMESTAMP := p_local_date::timestamp + INTERVAL '1 day';
    v_breaks tsmultirange;
BEGIN
    SELECT COALESCE(range_agg(tsrange(lo, hi, '[)')), '{}'::tsmultirange) INTO v_breaks
    FROM (
        SELECT GREATEST(public.get_local_timestamp_robust(bp.break_start_time_utc, s.original_timezone, bp.break_start_time), v_start) AS lo,
                   LEAST(COALESCE(
                       public.get_local_timestamp_robust(bp.break_end_time_utc, s.original_timezone, bp.break_end_time),
                       public.get_local_timestamp_robust(NOW(), s.original_timezone, s.check_in_time + (NOW() - s.check_in_time_utc))
                   ), v_end) AS hi
        FROM public.break_periods bp
        JOIN public.attendance_sessions s ON bp.session_id = s.id
        WHERE s.user_id = p_user_id
          AND s.is_deleted = false
          AND bp.is_deleted = false
          AND bp.break_start_time_utc < (v_end AT TIME ZONE 'UTC') + INTERVAL '1 day'
    ) x
    WHERE lo < hi;

    RETURN (
        SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (upper(rng) - lower(rng)))), 0)::INTEGER
        FROM unnest(v_breaks) AS rng
    );
END;
$$;

DROP MATERIALIZED VIEW IF EXISTS public.mv_monthly_summary CASCADE;

CREATE MATERIALIZED VIEW public.mv_monthly_summary AS
WITH base_sessions AS (
    SELECT
        s.id,
        s.user_id,
        public.get_local_timestamp_robust(s.check_in_time_utc, s.original_timezone, s.check_in_time) AS check_in_local,
        COALESCE(
            public.get_local_timestamp_robust(s.check_out_time_utc, s.original_timezone, s.check_out_time),
            public.get_local_timestamp_robust(NOW(), s.original_timezone, s.check_in_time + (NOW() - s.check_in_time_utc))
        ) AS check_out_local,
        s.original_timezone
    FROM public.attendance_sessions s
    WHERE s.is_deleted = false
),
expanded_days AS (
    SELECT
        bs.user_id,
        d::date AS work_date,
        EXTRACT(year FROM d)::integer AS work_year,
        EXTRACT(month FROM d)::integer AS work_month,
        bs.id AS session_id,
        bs.original_timezone,
        GREATEST(bs.check_in_local, d) AS day_check_in_local,
        LEAST(bs.check_out_local, d + INTERVAL '1 day') AS day_check_out_local
    FROM base_sessions bs,
    LATERAL generate_series(bs.check_in_local::date, bs.check_out_local::date, '1 day'::interval) d
),
distinct_day_keys AS (
    SELECT DISTINCT user_id, work_year, work_month, work_date FROM expanded_days
),
day_calculations AS (
    SELECT
        dd.user_id, dd.work_year, dd.work_month, dd.work_date,
        public.get_daily_work_seconds_local_final(dd.user_id, dd.work_date)  AS effective_total_work,
        public.get_daily_sleep_seconds_local_final(dd.user_id, dd.work_date) AS effective_sleep_work,
        public.get_daily_break_seconds_local_final(dd.user_id, dd.work_date) AS total_break_seconds
    FROM distinct_day_keys dd
),
daily_meta_stats AS (
    SELECT
        ed.user_id,
        ed.work_date,
        COUNT(DISTINCT ed.session_id) AS session_count,
        MIN(ed.day_check_in_local) AS first_check_in,
        -- show a midnight checkout as 23:59:59 of the same day
        MAX(CASE
                WHEN ed.day_check_out_local = (ed.work_date + INTERVAL '1 day')::timestamp
                THEN (ed.work_date + INTERVAL '1 day' - INTERVAL '1 second')::timestamp
                ELSE ed.day_check_out_local
            END) AS last_check_out
    FROM expanded_days ed
    GROUP BY ed.user_id, ed.work_date
),
activity_stats AS (
    SELECT ed.user_id, ed.work_date, COUNT(DISTINCT aa.id) AS activity_count
    FROM public.app_activities aa
    JOIN expanded_days ed ON aa.session_id = ed.session_id
    WHERE aa.is_deleted = false
      AND public.get_local_timestamp_robust(aa.start_time_utc, ed.original_timezone, aa.start_time)::date = ed.work_date
    GROUP BY ed.user_id, ed.work_date
)
SELECT
    dc.user_id,
    dc.work_year AS year,
    dc.work_month AS month,
    dc.work_date AS date,
    COALESCE(dms.session_count, 0)::integer AS session_count,
    dc.effective_total_work::integer AS total_work_seconds,
    GREATEST(0, dc.effective_total_work - dc.effective_sleep_work)::integer AS normal_work_seconds,
    dc.effective_sleep_work::integer AS total_work_during_sleep_seconds,
    dc.total_break_seconds::integer AS total_break_seconds,
    COALESCE(ast.activity_count, 0)::integer AS activity_count,
    dms.first_check_in,
    dms.last_check_out,
    NOW() AS computed_at
FROM day_calculations dc
LEFT JOIN daily_meta_stats dms ON dc.user_id = dms.user_id AND dc.work_date = dms.work_date
LEFT JOIN activity_stats ast ON dc.user_id = ast.user_id AND dc.work_date = ast.work_date;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_monthly_summary_lookup
    ON public.mv_monthly_summary(user_id, year, month, date);

-- Materialized views cannot use RLS, so apps read it only through the
-- functions below, which check can_view_user().
REVOKE ALL ON public.mv_monthly_summary FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.refresh_monthly_summary_cache()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    -- Throttle: skip if refreshed in the last 30 s or another refresh is running
    IF NOT pg_try_advisory_xact_lock(hashtext('refresh_monthly_summary_cache')) THEN
        RETURN;
    END IF;
    IF (SELECT MAX(computed_at) FROM public.mv_monthly_summary) > NOW() - INTERVAL '30 seconds' THEN
        RETURN;
    END IF;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_monthly_summary;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_monthly_summary(p_user_id UUID, p_year INTEGER, p_month INTEGER)
RETURNS SETOF public.mv_monthly_summary
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF NOT public.can_view_user(p_user_id) THEN
        RAISE EXCEPTION 'Not allowed to view this user''s data.' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
        SELECT * FROM public.mv_monthly_summary
        WHERE user_id = p_user_id AND year = p_year AND month = p_month
        ORDER BY date DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_available_months(p_user_id UUID)
RETURNS TABLE (year INTEGER, month INTEGER)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF NOT public.can_view_user(p_user_id) THEN
        RAISE EXCEPTION 'Not allowed to view this user''s data.' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
        SELECT DISTINCT m.year, m.month FROM public.mv_monthly_summary m
        WHERE m.user_id = p_user_id
        ORDER BY m.year DESC, m.month DESC;
END;
$$;


-- ============================================================================
-- 11. GRANTS & REALTIME
-- ============================================================================

-- Nothing is available without signing in
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon, PUBLIC;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Tables that are only written through RPCs / hidden from apps
REVOKE INSERT, UPDATE, DELETE ON public.companies, public.company_invitations, public.platform_admins FROM authenticated;
REVOKE ALL ON public.platform_admin_emails FROM authenticated;
REVOKE ALL ON public.mv_monthly_summary FROM authenticated;

-- Internal helpers are not callable from the apps
REVOKE EXECUTE ON FUNCTION public._allow_privileged_write() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public._attach_orphan_tracking(UUID, UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public._assert_not_last_admin(UUID) FROM authenticated;

-- Live updates for the web dashboard (Supabase Realtime honours RLS)
DO $$
DECLARE
    t TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        FOREACH t IN ARRAY ARRAY['attendance_sessions', 'app_activities', 'break_periods'] LOOP
            IF NOT EXISTS (
                SELECT 1 FROM pg_publication_tables
                WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
            ) THEN
                EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
            END IF;
        END LOOP;
    END IF;
END$$;

-- Optional: refresh the monthly summary every 15 minutes with pg_cron
-- (enable the pg_cron extension in Dashboard → Database → Extensions first):
-- SELECT cron.schedule('refresh-monthly-summary', '*/15 * * * *',
--                      'SELECT public.refresh_monthly_summary_cache()');


-- ============================================================================
-- 12. PLATFORM ADMIN SETUP  ← EDIT THIS
-- ============================================================================
-- Put the Google account e-mail(s) of the platform owner here, then run this
-- statement (it is fine to run it before or after that person first signs in).
--
-- INSERT INTO public.platform_admin_emails (email) VALUES ('owner@yourdomain.com')
-- ON CONFLICT DO NOTHING;
-- ============================================================================
