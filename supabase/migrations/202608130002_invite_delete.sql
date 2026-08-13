-- Allow an administrator to permanently remove an unused invite code.
-- Redeemed codes deliberately remain immutable audit records; disable them
-- instead of deleting them.

create or replace function public.admin_delete_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_planer_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;

  delete from public.invite_codes
  where id = p_invite_id
    and used_count = 0;

  if not found then
    raise exception 'only unused invite codes can be deleted' using errcode = '22023';
  end if;
end;
$$;

revoke all on function public.admin_delete_invite(uuid) from public, anon, authenticated;
grant execute on function public.admin_delete_invite(uuid) to authenticated;
