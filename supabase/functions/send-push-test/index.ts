import { admin, corsHeaders, reply, sendPushToUser } from '../_shared/push.ts';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);

  const authorization = request.headers.get('authorization') || '';
  const token = authorization.replace(/^Bearer\s+/i, '');
  if (!token) return reply({ error: 'unauthorized' }, 401);
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return reply({ error: 'unauthorized' }, 401);

  try {
    const sent = await sendPushToUser(userData.user.id, {
      title: 'Planer',
      body: 'اعلان آزمایشی با موفقیت فعال است.',
      tag: `planer-test:${Date.now()}`,
      url: '/life-os/#/settings',
    });
    return reply({ ok: true, sent });
  } catch (error) {
    console.error('send-push-test failed', error);
    return reply({ error: 'push_unavailable' }, 503);
  }
});
