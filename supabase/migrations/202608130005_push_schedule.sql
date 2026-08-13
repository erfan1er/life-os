-- Schedule the Push reminder Edge Function once per minute.
-- Before running this migration, store the same random value in:
--   1) Edge Function secret: PLANER_PUSH_CRON_SECRET
--   2) Vault secret named: planer_push_cron_secret
-- The value is never committed to this repository.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

create or replace function public.planer_trigger_push_reminders()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'planer_push_cron_secret'
  order by created_at desc
  limit 1;

  if v_secret is null then
    raise exception 'Planer Push scheduler secret is not configured';
  end if;

  perform net.http_post(
    url := 'https://ceugxisjrircwdzhztdv.supabase.co/functions/v1/send-push-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-planer-cron-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
end;
$$;

revoke all on function public.planer_trigger_push_reminders() from public, anon, authenticated;

select cron.unschedule(jobid)
from cron.job
where jobname = 'planer-push-reminders';

select cron.schedule(
  'planer-push-reminders',
  '* * * * *',
  $$select public.planer_trigger_push_reminders()$$
);
