-- ============================================================================
-- Time Trak - Supabase Database Schema
-- ============================================================================
-- This schema creates all necessary tables for the Time Trak application
-- with user authentication and role-based access control.
--
-- IMPORTANT: This schema does NOT use RLS (Row Level Security).
-- All access control is handled in application code.
-- ============================================================================

-- ============================================================================
-- 1. USERS TABLE (extends Supabase auth.users)
-- ============================================================================
-- This table stores additional user information beyond what Supabase Auth provides
-- Links to auth.users via the id field (UUID)

-- Create ENUM type for user roles (safe creation)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('admin', 'member');
    END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    name TEXT,
    role user_role NOT NULL DEFAULT 'member', -- Changed to use ENUM type
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON public.users(is_active);

-- ============================================================================
-- 2. ATTENDANCE SESSIONS TABLE
-- ============================================================================
-- Stores check-in/check-out sessions for users

CREATE TABLE IF NOT EXISTS public.attendance_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ NOT NULL,
    check_out_time TIMESTAMPTZ,
    check_in_time_utc TIMESTAMPTZ NOT NULL,
    check_out_time_utc TIMESTAMPTZ,
    check_in_source TEXT NOT NULL DEFAULT 'manual',
    check_out_source TEXT,
    total_work_seconds INTEGER DEFAULT 0,
    is_closed BOOLEAN NOT NULL DEFAULT false,
    last_seen_time TIMESTAMPTZ,
    continuation_of_session_id UUID REFERENCES public.attendance_sessions(id),
    continuation_reason TEXT,
    original_timezone TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMPTZ,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    local_id TEXT -- For tracking local SQLite record
);

-- Ensure columns exist if table was already created without them
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS check_in_time_utc TIMESTAMPTZ;
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS check_out_time_utc TIMESTAMPTZ;
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ;
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS local_id TEXT;
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS continuation_of_session_id UUID REFERENCES public.attendance_sessions(id);
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS continuation_reason TEXT;
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS original_timezone TEXT;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_attendance_sessions_user_id ON public.attendance_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_attendance_sessions_check_in_time ON public.attendance_sessions(check_in_time);
CREATE INDEX IF NOT EXISTS idx_attendance_sessions_is_closed ON public.attendance_sessions(is_closed);
CREATE INDEX IF NOT EXISTS idx_attendance_sessions_continuation ON public.attendance_sessions(continuation_of_session_id);
CREATE INDEX IF NOT EXISTS idx_attendance_sessions_local_id ON public.attendance_sessions(local_id);

-- ============================================================================
-- 3. BREAK PERIODS TABLE
-- ============================================================================
-- Stores break periods within attendance sessions

CREATE TABLE IF NOT EXISTS public.break_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    break_start_time TIMESTAMPTZ NOT NULL,
    break_end_time TIMESTAMPTZ,
    break_start_time_utc TIMESTAMPTZ NOT NULL,
    break_end_time_utc TIMESTAMPTZ,
    duration_seconds INTEGER DEFAULT 0,
    continuation_of_break_id UUID REFERENCES public.break_periods(id),
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMPTZ,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    local_id TEXT
);

-- Ensure columns exist
ALTER TABLE public.break_periods ADD COLUMN IF NOT EXISTS break_start_time_utc TIMESTAMPTZ;
ALTER TABLE public.break_periods ADD COLUMN IF NOT EXISTS break_end_time_utc TIMESTAMPTZ;
ALTER TABLE public.break_periods ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ;
ALTER TABLE public.break_periods ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.break_periods ADD COLUMN IF NOT EXISTS local_id TEXT;
ALTER TABLE public.break_periods ADD COLUMN IF NOT EXISTS continuation_of_break_id UUID REFERENCES public.break_periods(id);
ALTER TABLE public.break_periods ADD COLUMN IF NOT EXISTS note TEXT;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_break_periods_session_id ON public.break_periods(session_id);
CREATE INDEX IF NOT EXISTS idx_break_periods_user_id ON public.break_periods(user_id);
CREATE INDEX IF NOT EXISTS idx_break_periods_start_time ON public.break_periods(break_start_time);
CREATE INDEX IF NOT EXISTS idx_break_periods_local_id ON public.break_periods(local_id);

-- ============================================================================
-- 4. APP ACTIVITIES TABLE
-- ============================================================================
-- Stores tracked application activities

CREATE TABLE IF NOT EXISTS public.app_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    app_name TEXT NOT NULL,
    window_title TEXT,
    bundle_id TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    start_time_utc TIMESTAMPTZ NOT NULL,
    end_time_utc TIMESTAMPTZ,
    duration_seconds INTEGER DEFAULT 0,
    activity_type TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMPTZ,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    local_id TEXT
);

-- Ensure columns exist
ALTER TABLE public.app_activities ADD COLUMN IF NOT EXISTS start_time_utc TIMESTAMPTZ;
ALTER TABLE public.app_activities ADD COLUMN IF NOT EXISTS end_time_utc TIMESTAMPTZ;
ALTER TABLE public.app_activities ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ;
ALTER TABLE public.app_activities ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.app_activities ADD COLUMN IF NOT EXISTS local_id TEXT;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_app_activities_session_id ON public.app_activities(session_id);
CREATE INDEX IF NOT EXISTS idx_app_activities_user_id ON public.app_activities(user_id);
CREATE INDEX IF NOT EXISTS idx_app_activities_start_time ON public.app_activities(start_time);
CREATE INDEX IF NOT EXISTS idx_app_activities_app_name ON public.app_activities(app_name);
CREATE INDEX IF NOT EXISTS idx_app_activities_local_id ON public.app_activities(local_id);

-- ============================================================================
-- 5. WORK DURING SLEEP PERIODS TABLE
-- ============================================================================
-- Stores periods where work was detected during system sleep

CREATE TABLE IF NOT EXISTS public.work_during_sleep_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    sleep_start_time TIMESTAMPTZ NOT NULL,
    wake_time TIMESTAMPTZ NOT NULL,
    sleep_start_time_utc TIMESTAMPTZ NOT NULL,
    wake_time_utc TIMESTAMPTZ NOT NULL,
    duration_seconds INTEGER NOT NULL,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMPTZ,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    local_id TEXT
);

-- Ensure columns exist
ALTER TABLE public.work_during_sleep_periods ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ;
ALTER TABLE public.work_during_sleep_periods ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.work_during_sleep_periods ADD COLUMN IF NOT EXISTS local_id TEXT;
ALTER TABLE public.work_during_sleep_periods ADD COLUMN IF NOT EXISTS sleep_start_time_utc TIMESTAMPTZ;
ALTER TABLE public.work_during_sleep_periods ADD COLUMN IF NOT EXISTS wake_time_utc TIMESTAMPTZ;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_work_sleep_session_id ON public.work_during_sleep_periods(session_id);
CREATE INDEX IF NOT EXISTS idx_work_sleep_user_id ON public.work_during_sleep_periods(user_id);
CREATE INDEX IF NOT EXISTS idx_work_sleep_start_time ON public.work_during_sleep_periods(sleep_start_time);
CREATE INDEX IF NOT EXISTS idx_work_sleep_local_id ON public.work_during_sleep_periods(local_id);

-- ============================================================================
-- 6. SESSION CONTINUATIONS TABLE
-- ============================================================================
-- Tracks session splits and continuations

CREATE TABLE IF NOT EXISTS public.session_continuations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    new_session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    continuation_type TEXT NOT NULL,
    split_timestamp_utc TIMESTAMPTZ NOT NULL,
    split_timestamp_local TIMESTAMPTZ NOT NULL,
    metadata TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMPTZ,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    local_id TEXT
);

-- Ensure columns exist
ALTER TABLE public.session_continuations ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ;
ALTER TABLE public.session_continuations ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.session_continuations ADD COLUMN IF NOT EXISTS local_id TEXT;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_continuations_original ON public.session_continuations(original_session_id);
CREATE INDEX IF NOT EXISTS idx_continuations_new ON public.session_continuations(new_session_id);
CREATE INDEX IF NOT EXISTS idx_continuations_user_id ON public.session_continuations(user_id);
CREATE INDEX IF NOT EXISTS idx_continuations_local_id ON public.session_continuations(local_id);

-- ============================================================================
-- 7. EVENT LOG TABLE
-- ============================================================================
-- System event logging

CREATE TABLE IF NOT EXISTS public.event_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    event_source TEXT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMPTZ,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    local_id TEXT
);

-- Ensure columns exist
ALTER TABLE public.event_log ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.event_log ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ;
ALTER TABLE public.event_log ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.event_log ADD COLUMN IF NOT EXISTS local_id TEXT;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_event_log_user_id ON public.event_log(user_id);
CREATE INDEX IF NOT EXISTS idx_event_log_timestamp ON public.event_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_event_log_type ON public.event_log(event_type);
CREATE INDEX IF NOT EXISTS idx_event_log_local_id ON public.event_log(local_id);

-- ============================================================================
-- 8. SYNC QUEUE TABLE (Client-side tracking)
-- ============================================================================
-- This table helps track pending sync operations
-- It's primarily used locally but can be synced for multi-device support

CREATE TABLE IF NOT EXISTS public.sync_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('insert', 'update', 'delete')),
    data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMPTZ,
    retry_count INTEGER DEFAULT 0,
    last_error TEXT
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_sync_queue_user_id ON public.sync_queue(user_id);
CREATE INDEX IF NOT EXISTS idx_sync_queue_synced_at ON public.sync_queue(synced_at);
CREATE INDEX IF NOT EXISTS idx_sync_queue_table_name ON public.sync_queue(table_name);

-- ============================================================================
-- FUNCTIONS AND TRIGGERS
-- ============================================================================

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at on all tables
-- We DROP before CREATE to ensure idempotency

DROP TRIGGER IF EXISTS update_users_updated_at ON public.users;
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_attendance_sessions_updated_at ON public.attendance_sessions;
CREATE TRIGGER update_attendance_sessions_updated_at BEFORE UPDATE ON public.attendance_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_break_periods_updated_at ON public.break_periods;
CREATE TRIGGER update_break_periods_updated_at BEFORE UPDATE ON public.break_periods
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_app_activities_updated_at ON public.app_activities;
CREATE TRIGGER update_app_activities_updated_at BEFORE UPDATE ON public.app_activities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_work_during_sleep_updated_at ON public.work_during_sleep_periods;
CREATE TRIGGER update_work_during_sleep_updated_at BEFORE UPDATE ON public.work_during_sleep_periods
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_session_continuations_updated_at ON public.session_continuations;
CREATE TRIGGER update_session_continuations_updated_at BEFORE UPDATE ON public.session_continuations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_event_log_updated_at ON public.event_log;
CREATE TRIGGER update_event_log_updated_at BEFORE UPDATE ON public.event_log
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to automatically create user profile after signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email, role, created_at)
    VALUES (
        NEW.id,
        NEW.email,
        'member'::user_role, -- Default role is member (explicit cast)
        NOW()
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create user profile on auth.users insert
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- INITIAL ADMIN USER SETUP
-- ============================================================================
-- After creating a user through Supabase Auth, you can promote them to admin:
-- UPDATE public.users SET role = 'admin'::user_role WHERE email = 'admin@example.com';
-- ============================================================================

-- ============================================================================
-- DISABLE RLS (Row Level Security)
-- ============================================================================
-- As per requirements, we're NOT using RLS and handling all access control
-- in application code. These commands ensure RLS is disabled.

ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_sessions DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.break_periods DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_activities DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_during_sleep_periods DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_continuations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_log DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_queue DISABLE ROW LEVEL SECURITY;

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. All timestamps use TIMESTAMPTZ for proper timezone handling
-- 3. local_id helps track records from local SQLite database
-- 4. synced_at tracks when records were last synced
-- 5. updated_at is automatically updated via triggers
-- 6. Foreign keys use CASCADE for proper cleanup
-- 7. Default role is 'member' for new users
-- 8. First user should be manually promoted to 'admin' role
-- ============================================================================
