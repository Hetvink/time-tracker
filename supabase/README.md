# Supabase setup (multi-company)

Everything the apps need lives in this folder:

| File | What it is |
| --- | --- |
| `schema.sql` | The whole database: tables, Row Level Security, triggers, RPC functions, monthly summary view. Safe to run more than once. |
| `functions/invite-member/` | Edge Function that creates an invitation and e-mails the join link. |
| `tests/` | Automated checks for `schema.sql` (runs Postgres locally in Node). |
| `legacy/` | The old single-company SQL files. Not used any more; kept for reference. |

## 1. Create the project and run the schema

1. Create a new project at <https://supabase.com/dashboard>.
2. Open **SQL Editor → New query**, paste all of `schema.sql`, and click **Run**.
3. Make yourself the platform admin. Use the Google account you'll sign in with, then run:

   ```sql
   INSERT INTO public.platform_admin_emails (email) VALUES ('you@yourdomain.com')
   ON CONFLICT DO NOTHING;
   ```

   It works before or after that account's first sign-in.

## 2. Google sign-in

1. In Google Cloud Console → **APIs & Services → Credentials**, create an **OAuth client ID** (type *Web application*).
   Add this **Authorized redirect URI**: `https://<project-ref>.supabase.co/auth/v1/callback`
2. In Supabase → **Authentication → Sign In / Providers → Google**, enable it and paste the client ID and secret.
3. In Supabase → **Authentication → URL Configuration**:
   - **Site URL**: your web portal URL, e.g. `https://timetrak.example.com`
   - **Redirect URLs**: add all of these
     - `https://timetrak.example.com/**` (web portal)
     - `http://localhost:3000` (desktop sign-in; match `OAUTH_CALLBACK_PORT`)
     - `timetrak://login-callback` (Android / iOS)
     - `http://localhost:8080/**` (optional, local web development)

## 3. Invitation e-mails (Edge Function)

Install the [Supabase CLI](https://supabase.com/docs/guides/cli), then from the project root:

```bash
supabase login
supabase link --project-ref <project-ref>
supabase functions deploy invite-member
supabase secrets set APP_URL=https://timetrak.example.com
# E-mail delivery through Resend (https://resend.com); verify your domain there first
supabase secrets set RESEND_API_KEY=re_xxx INVITE_FROM_EMAIL="Time Trak <team@yourdomain.com>"
```

Until the function is deployed or `RESEND_API_KEY` is set, inviting still works: the Team page shows a **Copy invite link** button so the admin can send the link themselves.

## 4. Configure the apps

Copy `.env.example` to `.env` in the project root and fill in:

```dotenv
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...   # or SUPABASE_ANON_KEY for legacy keys
WEB_APP_URL=https://timetrak.example.com
DESKTOP_DOWNLOAD_URL=https://timetrak.example.com/download   # optional
```

The build scripts (`build_web.sh`, `deploy_web.sh`, `build_dmg.sh`, `build_windows.bat`) pass `--dart-define-from-file=.env` automatically. For `flutter run`, use the VS Code launch configurations or add the same flag yourself.

## 5. Optional: keep monthly summaries fresh

Enable **pg_cron** (Database → Extensions), then run:

```sql
SELECT cron.schedule('refresh-monthly-summary', '*/15 * * * *',
                     'SELECT public.refresh_monthly_summary_cache()');
```

The web app also triggers a refresh when it opens the monthly timesheet (throttled to once per 30 s on the server).

## How access works

| Who | Can see | Can do |
| --- | --- | --- |
| **Member** | Their own profile and tracking data | Track time, accept or decline invitations, leave the company |
| **Company admin** | Every member of their company and all of that company's tracking data | Invite people, change roles, deactivate or remove members, edit the company profile |
| **Platform admin** | Everything | Approve, reject, suspend or delete companies, and open any company's team and member activity |

Rules are enforced in Postgres (RLS + `SECURITY DEFINER` functions), not in the app, so the publishable key is safe to ship. A user can never change their own role or company from the client: a trigger reverts those columns.

Every tracking row gets `company_id` automatically from the owner's profile. Time tracked before someone joins a company is attached to that company when they join.

## Running the schema tests

```bash
cd supabase/tests
npm install
npm test
```

This runs `schema.sql` twice inside [PGlite](https://pglite.dev) (Postgres compiled to WASM) against a stubbed Supabase `auth` schema. It then checks registration, approval, invitations, tenant isolation, role-escalation protection, the team view, monthly summaries, and suspension/deletion.
