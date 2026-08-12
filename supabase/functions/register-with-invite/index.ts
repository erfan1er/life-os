// Supabase Edge Function: invite-only account creation for Planer.
// Deploy with: supabase functions deploy register-with-invite
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are supplied by the Supabase
// runtime; never place the service role key in GitHub Pages or this repository.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const reply = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);

  try {
    const input = await request.json();
    const email = String(input.email || '').trim().toLowerCase();
    const password = String(input.password || '');
    const displayName = String(input.display_name || '').trim().slice(0, 80);
    const inviteCode = String(input.invite_code || '').trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 8 ||
      !/^[A-Za-z0-9_-]{6,64}$/.test(inviteCode)) {
      return reply({ error: 'invalid_input' }, 400);
    }

    const url = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !serviceKey) return reply({ error: 'server_unavailable' }, 503);
    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // email_confirm is deliberately explicit: this invite-gated flow needs the
    // Auth user before the transactional consume RPC can associate the use.
    // See README for the SMTP/email-verification tradeoff and recommended
    // rate-limit/CAPTCHA settings.
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: displayName },
    });
    if (createError || !created.user) return reply({ error: 'registration_unavailable' }, 400);

    const { error: consumeError } = await admin.rpc('consume_invite_for_user', {
      p_code: inviteCode,
      p_user_id: created.user.id,
      p_display_name: displayName,
    });
    if (consumeError) {
      // A failed or exhausted invite must not leave a usable Auth account.
      await admin.auth.admin.deleteUser(created.user.id).catch(() => {});
      return reply({ error: 'invite_unavailable' }, 400);
    }
    return reply({ ok: true });
  } catch (error) {
    console.error('register-with-invite failed', error);
    return reply({ error: 'registration_unavailable' }, 400);
  }
});

