// Exercises supabase/schema.sql on PGlite with a stubbed Supabase auth layer.
import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';

const schema = fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');
const db = new PGlite();

const supabaseStub = `
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
GRANT USAGE ON SCHEMA auth TO authenticated, anon;
CREATE TABLE auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS
  $$ SELECT coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
GRANT EXECUTE ON FUNCTION auth.uid(), auth.jwt() TO authenticated, anon;
`;

let failures = 0;
const ok = (msg) => console.log('  ✓ ' + msg);
const fail = (msg) => { failures++; console.log('  ✗ ' + msg); };

const ids = {
  owner: '00000000-0000-0000-0000-00000000000a',
  alice: '00000000-0000-0000-0000-0000000000a1',
  bob:   '00000000-0000-0000-0000-0000000000b0',
  eve:   '00000000-0000-0000-0000-0000000000e0',
};
const emails = { owner: 'owner@platform.io', alice: 'alice@acme.com', bob: 'bob@acme.com', eve: 'eve@other.com' };

async function as(who, sql, params) {
  await db.exec('RESET ROLE');
  await db.query(`SELECT set_config('request.jwt.claim.sub', $1, false)`, [ids[who]]);
  await db.query(`SELECT set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: ids[who], email: emails[who] })]);
  await db.exec('SET ROLE authenticated');
  try {
    return await db.query(sql, params);
  } finally {
    await db.exec('RESET ROLE');
  }
}
async function expectError(label, who, sql, params, pattern) {
  try {
    await as(who, sql, params);
    fail(`${label} — expected error, got success`);
  } catch (e) {
    if (pattern && !pattern.test(e.message)) fail(`${label} — wrong error: ${e.message}`);
    else ok(`${label} (${e.message.split('\n')[0]})`);
  }
}

await db.exec(supabaseStub);
console.log('Running schema.sql (1st pass)…');
await db.exec(schema);
console.log('Running schema.sql (2nd pass, idempotency)…');
await db.exec(schema);
ok('schema applied twice without errors');

await db.exec(`INSERT INTO public.platform_admin_emails(email) VALUES ('owner@platform.io')`);
for (const k of Object.keys(ids)) {
  await db.query(`INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES ($1,$2,$3)`,
    [ids[k], emails[k], JSON.stringify({ full_name: k.toUpperCase(), avatar_url: 'http://x/' + k })]);
}
const prof = await db.query(`SELECT count(*)::int c FROM public.users`);
prof.rows[0].c === 4 ? ok('handle_new_user created 4 profiles') : fail('profiles not created');

console.log('\n— Onboarding');
let ctx = (await as('alice', `SELECT public.get_my_context() c`)).rows[0].c;
ctx.company === null && ctx.is_super_admin === false ? ok('alice has no company, not super admin') : fail(JSON.stringify(ctx));
ctx = (await as('owner', `SELECT public.get_my_context() c`)).rows[0].c;
ctx.is_super_admin === true ? ok('owner promoted to platform admin by e-mail') : fail('owner not super admin');

await as('alice', `UPDATE public.users SET role='admin', name='Alice A' WHERE id=$1`, [ids.alice]);
let r = await db.query(`SELECT role, name FROM public.users WHERE id=$1`, [ids.alice]);
r.rows[0].role === 'member' && r.rows[0].name === 'Alice A' ? ok('self role escalation blocked, name edit allowed') : fail(JSON.stringify(r.rows[0]));

await expectError('direct company insert blocked', 'alice', `INSERT INTO public.companies(name,slug) VALUES ('X','x')`, [], /permission denied/);

const acme = (await as('alice', `SELECT * FROM public.request_company('Acme Inc', 'acme.com', 'Software', '11-50', 'India', null, 'We build')`)).rows[0];
acme.status === 'pending' && acme.slug === 'acme-inc' ? ok('alice requested Acme (pending)') : fail(JSON.stringify(acme));
await expectError('second pending request rejected', 'alice', `SELECT public.request_company('Acme 2')`, [], /already have a registration request/);
await expectError('member cannot approve', 'alice', `SELECT public.approve_company($1)`, [acme.id], /Only platform admins/);
await expectError('invite before approval blocked', 'alice', `SELECT public.create_invitation('bob@acme.com')`, [], /Only company admins/);

const other = (await as('eve', `SELECT * FROM public.request_company('Other Co')`)).rows[0];

console.log('\n— Platform admin');
let ov = (await as('owner', `SELECT * FROM public.get_companies_overview()`)).rows;
ov.length === 2 && ov[0].status === 'pending' ? ok('overview lists both requests') : fail(JSON.stringify(ov));
await as('owner', `SELECT public.approve_company($1)`, [acme.id]);
await as('owner', `SELECT public.reject_company($1, 'Incomplete details')`, [other.id]);
r = await db.query(`SELECT role, company_id FROM public.users WHERE id=$1`, [ids.alice]);
r.rows[0].role === 'admin' && r.rows[0].company_id === acme.id ? ok('approval made alice admin of Acme') : fail(JSON.stringify(r.rows[0]));
ctx = (await as('eve', `SELECT public.get_my_context() c`)).rows[0].c;
ctx.latest_request?.status === 'rejected' && ctx.latest_request.rejection_reason === 'Incomplete details' ? ok('eve sees rejection reason') : fail(JSON.stringify(ctx));
let stats = (await as('owner', `SELECT public.get_platform_stats() s`)).rows[0].s;
stats.companies_approved === 1 && stats.companies_rejected === 1 ? ok('platform stats correct') : fail(JSON.stringify(stats));

console.log('\n— Invitations');
const inv = (await as('alice', `SELECT * FROM public.create_invitation('  Bob@Acme.com ')`)).rows[0];
inv.email === 'bob@acme.com' && inv.token.length === 64 ? ok('invitation created, e-mail normalised') : fail(JSON.stringify(inv));
const inv2 = (await as('alice', `SELECT * FROM public.create_invitation('bob@acme.com')`)).rows[0];
inv2.id === inv.id ? ok('re-invite reuses pending invitation') : fail('duplicate invitation created');
let invs = (await as('alice', `SELECT * FROM public.company_invitations`)).rows;
invs.length === 1 ? ok('admin can list invitations') : fail('admin invitation list: ' + invs.length);
invs = (await as('eve', `SELECT * FROM public.company_invitations`)).rows;
invs.length === 0 ? ok('outsider sees no invitations') : fail('eve sees invitations');
await expectError('wrong account cannot accept', 'eve', `SELECT public.accept_invitation($1)`, [inv.token], /was sent to bob@acme.com/);
let preview = (await as('eve', `SELECT public.get_invitation_preview($1) p`, [inv.token])).rows[0].p;
preview.company_name === 'Acme Inc' && preview.email_matches === false ? ok('preview works, flags e-mail mismatch') : fail(JSON.stringify(preview));

// Bob tracked some time before joining → should be attached to Acme on accept
await as('bob', `INSERT INTO public.attendance_sessions(id,user_id,check_in_time,check_in_time_utc,check_out_time,check_out_time_utc,total_work_seconds,is_closed,original_timezone)
  VALUES ('10000000-0000-0000-0000-000000000001',$1, now()-interval '3 hours', now()-interval '3 hours', now()-interval '2 hours', now()-interval '2 hours', 3600, true, 'UTC')`, [ids.bob]);
ctx = (await as('bob', `SELECT public.get_my_context() c`)).rows[0].c;
ctx.invitations.length === 1 && ctx.invitations[0].company_name === 'Acme Inc' ? ok('bob sees pending invitation in context') : fail(JSON.stringify(ctx.invitations));
await as('bob', `SELECT public.accept_invitation($1)`, [inv.token]);
r = await db.query(`SELECT u.company_id, u.role, (SELECT company_id FROM public.attendance_sessions WHERE user_id=u.id LIMIT 1) s FROM public.users u WHERE id=$1`, [ids.bob]);
r.rows[0].company_id === acme.id && r.rows[0].role === 'member' && r.rows[0].s === acme.id ? ok('bob joined Acme; earlier tracking attached') : fail(JSON.stringify(r.rows[0]));
await expectError('invitation cannot be reused', 'bob', `SELECT public.accept_invitation($1)`, [inv.token], /already been accepted/);

console.log('\n— Tracking data isolation');
await as('bob', `INSERT INTO public.attendance_sessions(id,user_id,company_id,check_in_time,check_in_time_utc,is_closed,last_seen_time,total_work_seconds,original_timezone)
  VALUES ('10000000-0000-0000-0000-000000000002',$1,NULL, now()-interval '1 hour', now()-interval '1 hour', false, now(), 1800, 'UTC')`, [ids.bob]);
await as('bob', `INSERT INTO public.break_periods(session_id,user_id,break_start_time,break_start_time_utc,break_end_time,break_end_time_utc,duration_seconds)
  VALUES ('10000000-0000-0000-0000-000000000002',$1, now()-interval '40 minutes', now()-interval '40 minutes', now()-interval '30 minutes', now()-interval '30 minutes', 600)`, [ids.bob]);
await as('bob', `INSERT INTO public.app_activities(session_id,user_id,app_name,start_time,start_time_utc,duration_seconds)
  VALUES ('10000000-0000-0000-0000-000000000002',$1,'Code', now()-interval '20 minutes', now()-interval '20 minutes', 600)`, [ids.bob]);
r = await db.query(`SELECT company_id FROM public.attendance_sessions WHERE id='10000000-0000-0000-0000-000000000002'`);
r.rows[0].company_id === acme.id ? ok('company_id stamped by trigger (client sent NULL)') : fail('company_id not stamped');
// upsert path used by the desktop sync service
await as('bob', `INSERT INTO public.attendance_sessions(id,user_id,check_in_time,check_in_time_utc,is_closed,total_work_seconds)
  VALUES ('10000000-0000-0000-0000-000000000002',$1, now()-interval '1 hour', now()-interval '1 hour', false, 2400)
  ON CONFLICT (id) DO UPDATE SET total_work_seconds = EXCLUDED.total_work_seconds`, [ids.bob]);
r = await db.query(`SELECT company_id, total_work_seconds FROM public.attendance_sessions WHERE id='10000000-0000-0000-0000-000000000002'`);
r.rows[0].company_id === acme.id && r.rows[0].total_work_seconds === 2400 ? ok('sync upsert keeps company_id') : fail(JSON.stringify(r.rows[0]));

await expectError('cannot write rows for another user', 'bob',
  `INSERT INTO public.attendance_sessions(user_id,check_in_time,check_in_time_utc) VALUES ($1, now(), now())`, [ids.alice], /row-level security/);
let rows = (await as('alice', `SELECT id FROM public.attendance_sessions`)).rows;
rows.length === 2 ? ok('company admin sees member sessions') : fail('alice sees ' + rows.length);
rows = (await as('alice', `SELECT id FROM public.app_activities`)).rows;
rows.length === 1 ? ok('company admin sees member activities') : fail('alice activities ' + rows.length);
rows = (await as('eve', `SELECT id FROM public.attendance_sessions`)).rows;
rows.length === 0 ? ok('outsider sees no sessions') : fail('eve sees ' + rows.length);
rows = (await as('eve', `SELECT id FROM public.users`)).rows;
rows.length === 1 ? ok('outsider sees only own profile') : fail('eve sees users ' + rows.length);
rows = (await as('bob', `SELECT id FROM public.users`)).rows;
rows.length === 1 ? ok('member sees only own profile') : fail('bob sees users ' + rows.length);
rows = (await as('owner', `SELECT id FROM public.attendance_sessions`)).rows;
rows.length === 2 ? ok('platform admin sees all sessions') : fail('owner sees ' + rows.length);
await as('alice', `INSERT INTO public.event_log(user_id,event_type,event_source) VALUES ($1,'boot','test')`, [ids.alice]);
rows = (await as('bob', `UPDATE public.event_log SET event_type='x' WHERE user_id=$1 RETURNING id`, [ids.alice])).rows;
rows.length === 0 ? ok('member cannot update another user\'s rows (0 rows matched)') : fail('bob updated alice rows');

console.log('\n— Team view');
const members = (await as('alice', `SELECT * FROM public.get_company_members()`)).rows;
const bobRow = members.find((m) => m.id === ids.bob);
members.length === 2 && members[0].role === 'admin' && bobRow.is_working === true && Number(bobRow.today_work_seconds) === 2400 + 3600
  ? ok('team list: admin first, bob working, today totals') : fail(JSON.stringify(members));
await expectError('member cannot list team', 'bob', `SELECT * FROM public.get_company_members()`, [], /Only company admins/);
await expectError('outsider cannot list Acme team', 'eve', `SELECT * FROM public.get_company_members($1)`, [acme.id], /Only company admins/);
const ownerView = (await as('owner', `SELECT * FROM public.get_company_members($1)`, [acme.id])).rows;
ownerView.length === 2 ? ok('platform admin can list any company team') : fail('owner team ' + ownerView.length);

console.log('\n— Monthly summary');
await as('bob', `SELECT public.refresh_monthly_summary_cache()`);
const now = new Date();
const own = (await as('bob', `SELECT * FROM public.get_monthly_summary($1,$2,$3)`, [ids.bob, now.getUTCFullYear(), now.getUTCMonth() + 1])).rows;
own.length >= 1 ? ok(`member reads own summary (${own[0].total_work_seconds}s work, ${own[0].total_break_seconds}s break)`) : fail('no summary rows');
const adm = (await as('alice', `SELECT * FROM public.get_monthly_summary($1,$2,$3)`, [ids.bob, now.getUTCFullYear(), now.getUTCMonth() + 1])).rows;
adm.length === own.length ? ok('company admin reads member summary') : fail('alice summary ' + adm.length);
await expectError('outsider cannot read summary', 'eve', `SELECT * FROM public.get_monthly_summary($1,2026,1)`, [ids.bob], /Not allowed/);
await expectError('direct MV access blocked', 'bob', `SELECT * FROM public.mv_monthly_summary`, [], /permission denied/);
const months = (await as('bob', `SELECT * FROM public.get_available_months($1)`, [ids.bob])).rows;
months.length >= 1 ? ok('available months') : fail('no months');

console.log('\n— Member management');
await expectError('cannot demote last admin', 'alice', `SELECT public.update_member_role($1,'member')`, [ids.alice], /at least one admin/);
await expectError('member cannot change roles', 'bob', `SELECT public.update_member_role($1,'admin')`, [ids.bob], /Only company admins/);
await as('alice', `SELECT public.update_member_role($1,'admin')`, [ids.bob]);
await as('alice', `SELECT public.update_member_role($1,'member')`, [ids.alice]);
r = await db.query(`SELECT id, role FROM public.users WHERE company_id=$1 ORDER BY email`, [acme.id]);
r.rows[0].role === 'member' && r.rows[1].role === 'admin' ? ok('admin role transferred alice → bob') : fail(JSON.stringify(r.rows));
await as('bob', `SELECT public.remove_member($1)`, [ids.alice]);
r = await db.query(`SELECT company_id FROM public.users WHERE id=$1`, [ids.alice]);
r.rows[0].company_id === null ? ok('member removed') : fail('alice still in company');
await as('bob', `SELECT public.update_company_profile('Acme Corp', 'acme.io')`);
r = await db.query(`SELECT name, website FROM public.companies WHERE id=$1`, [acme.id]);
r.rows[0].name === 'Acme Corp' ? ok('company profile updated') : fail(JSON.stringify(r.rows[0]));
const inv3 = (await as('bob', `SELECT * FROM public.create_invitation('carol@acme.com')`)).rows[0];
await as('bob', `SELECT public.revoke_invitation($1)`, [inv3.id]);
r = await db.query(`SELECT status FROM public.company_invitations WHERE id=$1`, [inv3.id]);
r.rows[0].status === 'revoked' ? ok('invitation revoked') : fail(r.rows[0].status);

console.log('\n— Suspension & deletion');
await as('owner', `SELECT public.set_company_suspended($1, true)`, [acme.id]);
rows = (await as('bob', `SELECT id FROM public.app_activities WHERE user_id <> $1`, [ids.bob])).rows;
await expectError('suspended company admin cannot list team', 'bob', `SELECT * FROM public.get_company_members()`, [], /Only company admins/);
await as('owner', `SELECT public.set_company_suspended($1, false)`, [acme.id]);
ok('suspend / reactivate');
await as('eve', `SELECT public.delete_my_account()`);
r = await db.query(`SELECT count(*)::int c FROM public.users WHERE id=$1`, [ids.eve]);
r.rows[0].c === 0 ? ok('delete_my_account removed eve') : fail('eve still exists');
await as('owner', `SELECT public.delete_company($1)`, [acme.id]);
r = await db.query(`SELECT company_id FROM public.users WHERE id=$1`, [ids.bob]);
r.rows[0].company_id === null ? ok('delete_company detached members') : fail('bob still attached');

console.log(failures ? `\n${failures} FAILURE(S)` : '\nALL CHECKS PASSED');
process.exit(failures ? 1 : 0);
