-- Web Push subscriptions are device-specific. The browser never receives the
-- VAPID private key; only Edge Functions send notifications.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique check (endpoint ~ '^https://'),
  p256dh text not null check (char_length(p256dh) between 16 and 512),
  auth text not null check (char_length(auth) between 8 and 512),
  user_agent text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions(user_id);

-- A per-user durable dedupe key prevents a minute-based scheduler from
-- delivering the same reminder twice, even across retries.
create table if not exists public.push_deliveries (
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_key text not null check (char_length(notification_key) between 3 and 300),
  sent_at timestamptz not null default now(),
  primary key (user_id, notification_key)
);

drop trigger if exists push_subscriptions_set_updated_at on public.push_subscriptions;
create trigger push_subscriptions_set_updated_at before update on public.push_subscriptions
for each row execute function public.set_updated_at();

alter table public.push_subscriptions enable row level security;
alter table public.push_deliveries enable row level security;
revoke all on table public.push_subscriptions, public.push_deliveries from anon, authenticated;

create or replace function public.upsert_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_endpoint !~ '^https://' or char_length(p_endpoint) > 4096 or
     char_length(p_p256dh) not between 16 and 512 or char_length(p_auth) not between 8 and 512 then
    raise exception 'invalid push subscription' using errcode = '22023';
  end if;

  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
  values (v_uid, p_endpoint, p_p256dh, p_auth, left(coalesce(p_user_agent, ''), 500))
  on conflict (endpoint) do update set
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    user_agent = excluded.user_agent
  where public.push_subscriptions.user_id = v_uid;

  if not found then
    raise exception 'subscription belongs to another account' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.delete_push_subscription(p_endpoint text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_subscriptions
  where user_id = auth.uid() and endpoint = p_endpoint
$$;

revoke all on function public.upsert_push_subscription(text, text, text, text) from public, anon, authenticated;
revoke all on function public.delete_push_subscription(text) from public, anon, authenticated;
grant execute on function public.upsert_push_subscription(text, text, text, text) to authenticated;
grant execute on function public.delete_push_subscription(text) to authenticated;
