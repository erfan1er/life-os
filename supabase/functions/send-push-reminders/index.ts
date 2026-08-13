import { corsHeaders, reply, sendDueTaskPushes } from '../_shared/push.ts';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);

  const expected = Deno.env.get('PLANER_PUSH_CRON_SECRET');
  if (!expected || request.headers.get('x-planer-cron-secret') !== expected) {
    return reply({ error: 'unauthorized' }, 401);
  }
  try {
    const sent = await sendDueTaskPushes();
    return reply({ ok: true, sent });
  } catch (error) {
    console.error('send-push-reminders failed', error);
    return reply({ error: 'push_unavailable' }, 503);
  }
});
