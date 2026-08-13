import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type PushPayload = {
  title: string;
  body: string;
  tag: string;
  url?: string;
};

const url = Deno.env.get('SUPABASE_URL') || '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const publicKey = Deno.env.get('PUSH_VAPID_PUBLIC_KEY') || '';
const privateKey = Deno.env.get('PUSH_VAPID_PRIVATE_KEY') || '';
const subject = Deno.env.get('PUSH_VAPID_SUBJECT') || 'mailto:planer-notify@users.noreply.github.com';

if (publicKey && privateKey) webpush.setVapidDetails(subject, publicKey, privateKey);

export const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export const reply = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });

export async function sendPushToUser(userId: string, payload: PushPayload) {
  if (!url || !serviceKey || !publicKey || !privateKey) throw new Error('push_not_configured');
  const { data: subscriptions, error } = await admin
    .from('push_subscriptions')
    .select('id, endpoint, p256dh, auth')
    .eq('user_id', userId);
  if (error) throw error;

  let sent = 0;
  for (const sub of subscriptions || []) {
    try {
      await webpush.sendNotification({
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth },
      }, JSON.stringify(payload), { TTL: 60 * 60 });
      sent++;
    } catch (error) {
      const status = Number((error as { statusCode?: number })?.statusCode || 0);
      if (status === 404 || status === 410) {
        await admin.from('push_subscriptions').delete().eq('id', sub.id);
      }
      console.error('push delivery failed', { status, subscription: sub.id });
    }
  }
  return sent;
}

function partsInTehran(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US-u-ca-persian', {
    timeZone: 'Asia/Tehran',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(date);
  const get = (type: string) => parts.find(p => p.type === type)?.value || '';
  return {
    date: `${get('year')}-${get('month')}-${get('day')}`,
    minutes: Number(get('hour')) * 60 + Number(get('minute')),
  };
}

export async function sendDueTaskPushes() {
  const now = partsInTehran();
  const { data: records, error } = await admin
    .from('app_records')
    .select('user_id, id, payload')
    .eq('collection', 'tasks')
    .is('deleted_at', null)
    .limit(1000);
  if (error) throw error;

  let sent = 0;
  for (const record of records || []) {
    const task = record.payload || {};
    const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(String(task.dueTime || ''));
    if (!task.id || task.completed || task.date !== now.date || !match) continue;
    const dueMinutes = Number(match[1]) * 60 + Number(match[2]);
    // The scheduler runs every minute. A short grace period covers delayed
    // executions without silently sending a notification hours late.
    if (now.minutes < dueMinutes || now.minutes - dueMinutes > 5) continue;

    const key = `task:${task.id}:${task.date}:${task.dueTime}`;
    const { error: claimed } = await admin.from('push_deliveries')
      .insert({ user_id: record.user_id, notification_key: key });
    if (claimed) {
      if (claimed.code === '23505') continue;
      console.error('push dedupe claim failed', claimed.code);
      continue;
    }

    try {
      sent += await sendPushToUser(record.user_id, {
        title: String(task.title || 'Planer'),
        body: `زمان انجام کار · ${task.dueTime}`,
        tag: key,
        url: '/life-os/#/today',
      });
    } catch (error) {
      await admin.from('push_deliveries').delete()
        .eq('user_id', record.user_id).eq('notification_key', key);
      console.error('due task push failed', error);
    }
  }
  return sent;
}
