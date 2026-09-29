// Supabase Edge Function: invite-member
//
// Creates (or refreshes) a company invitation and e-mails the join link.
// Authorisation is enforced by the create_invitation() RPC, which runs with
// the caller's JWT — only admins of an approved company (or platform admins)
// can invite.
//
// Deploy:
//   supabase functions deploy invite-member
//   supabase secrets set APP_URL=https://your-web-app.example.com
//   supabase secrets set RESEND_API_KEY=re_xxx INVITE_FROM_EMAIL="Time Trak <team@yourdomain.com>"
//
// Without RESEND_API_KEY the invitation is still created and the response
// contains `invite_url`, which the app shows so the admin can share it.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function inviteEmailHtml(opts: {
  companyName: string;
  inviterName: string;
  role: string;
  inviteUrl: string;
  expiresAt: string;
}) {
  const company = escapeHtml(opts.companyName);
  const inviter = escapeHtml(opts.inviterName);
  const expires = new Date(opts.expiresAt).toUTCString().slice(0, 16);
  return `<!doctype html>
<html><body style="margin:0;background:#f4f5f7;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1c1c1e">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:32px 16px">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:12px;padding:32px">
        <tr><td>
          <p style="margin:0 0 8px;font-size:13px;color:#6e6e73;letter-spacing:.04em;text-transform:uppercase">Time Trak</p>
          <h1 style="margin:0 0 16px;font-size:22px">Join ${company} on Time Trak</h1>
          <p style="margin:0 0 16px;font-size:15px;line-height:1.5">
            ${inviter} invited you to join <strong>${company}</strong> as ${opts.role === "admin" ? "an admin" : "a team member"}.
          </p>
          <p style="margin:0 0 24px;font-size:15px;line-height:1.5">
            Accept the invitation, sign in with this e-mail's Google account, then download the desktop app to start tracking.
          </p>
          <a href="${opts.inviteUrl}" style="display:inline-block;background:#007aff;color:#ffffff;text-decoration:none;font-weight:600;padding:12px 22px;border-radius:8px">Accept invitation</a>
          <p style="margin:24px 0 0;font-size:12px;color:#6e6e73;line-height:1.5">
            This invitation expires on ${expires}. If the button doesn't work, open this link:<br>
            <a href="${opts.inviteUrl}" style="color:#007aff;word-break:break-all">${opts.inviteUrl}</a>
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

  let body: { email?: string; role?: string; company_id?: string; app_url?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const email = (body.email ?? "").trim().toLowerCase();
  const role = body.role === "admin" ? "admin" : "member";
  if (!email) return json({ error: "email is required" }, 400);

  // Client bound to the caller's JWT so RLS / RPC checks apply to them
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: invitation, error: inviteError } = await supabase.rpc("create_invitation", {
    p_email: email,
    p_role: role,
    p_company_id: body.company_id ?? null,
  });
  if (inviteError) return json({ error: inviteError.message }, 400);

  const { data: preview } = await supabase.rpc("get_invitation_preview", {
    p_token: invitation.token,
  });

  const appUrl = (Deno.env.get("APP_URL") ?? body.app_url ?? "").replace(/\/+$/, "");
  const inviteUrl = appUrl ? `${appUrl}/?invite=${invitation.token}` : null;

  const resendKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("INVITE_FROM_EMAIL") ?? "Time Trak <onboarding@resend.dev>";
  let emailSent = false;
  let emailError: string | null = null;

  if (!inviteUrl) {
    emailError = "APP_URL secret is not set, so no link could be e-mailed.";
  } else if (!resendKey) {
    emailError = "E-mail sending is not configured (RESEND_API_KEY). Share the link manually.";
  } else {
    const companyName = preview?.company_name ?? "your team";
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: fromEmail,
        to: [email],
        subject: `You're invited to join ${companyName} on Time Trak`,
        html: inviteEmailHtml({
          companyName,
          inviterName: preview?.invited_by_name ?? preview?.invited_by_email ?? "Your admin",
          role,
          inviteUrl,
          expiresAt: invitation.expires_at,
        }),
      }),
    });
    if (res.ok) {
      emailSent = true;
    } else {
      emailError = `E-mail provider error (${res.status}): ${await res.text()}`;
    }
  }

  return json({
    invitation,
    invite_url: inviteUrl,
    email_sent: emailSent,
    email_error: emailError,
  });
});
