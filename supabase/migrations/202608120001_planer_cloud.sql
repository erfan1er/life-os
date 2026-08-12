-- Planer cloud account, invite-only registration, and offline-sync backend.
-- Run with `supabase db push` or paste into the Supabase SQL Editor as one
-- migration. This migration contains no project keys or other secrets.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 80),
  role text not null default 'user' check (role in ('admin', 'user')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_records (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null check (char_length(id) between 3 and 200),
  collection text not null check (collection ~ '^[a-zA-Z][a-zA-Z0-9_]{0,63}$'),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  client_updated_at bigint not null check (client_updated_at > 0),
  version bigint not null default 1 check (version > 0),
  deleted_at bigint null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);
create index if not exists app_records_user_collection_updated_idx
  on public.app_records (user_id, collection, client_updated_at desc);

-- The database holds only a SHA-256 hash and a short non-reversible display
-- hint. The raw invite string is never persisted.
create table if not exists public.invite_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  code_hint text not null check (char_length(code_hint) between 4 and 16),
  max_uses integer not null check (max_uses > 0 and max_uses <= 100000),
  used_count integer not null default 0 check (used_count >= 0 and used_count <= max_uses),
  expires_at timestamptz null,
  enabled boolean not null default true,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists invite_codes_available_idx
  on public.invite_codes (enabled, expires_at) where enabled;

-- Audit only. It intentionally has no policy granting an administrator access
-- to other users' rows, so invite administration cannot reveal private data.
create table if not exists public.invite_redemptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  invite_id uuid not null references public.invite_codes(id) on delete restrict,
  redeemed_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
drop trigger if exists app_records_set_updated_at on public.app_records;
create trigger app_records_set_updated_at before update on public.app_records
for each row execute function public.set_updated_at();
drop trigger if exists invite_codes_set_updated_at on public.invite_codes;
create trigger invite_codes_set_updated_at before update on public.invite_codes
for each row execute function public.set_updated_at();

-- Every Auth user gets a non-privileged profile. This is the only automatic
-- role assignment; the first admin is promoted manually as documented.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, role)
  values (
    new.id,
    coalesce(left(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 80), ''),
    'user'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.app_records enable row level security;
alter table public.invite_codes enable row level security;
alter table public.invite_redemptions enable row level security;

-- Defense in depth: policies protect against altered browser requests even
-- though normal application data access uses the RPCs below.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select
  to authenticated using (id = auth.uid());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update
  to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists app_records_select_own on public.app_records;
create policy app_records_select_own on public.app_records for select
  to authenticated using (user_id = auth.uid());
drop policy if exists app_records_insert_own on public.app_records;
create policy app_records_insert_own on public.app_records for insert
  to authenticated with check (user_id = auth.uid());
drop policy if exists app_records_update_own on public.app_records;
create policy app_records_update_own on public.app_records for update
  to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists app_records_delete_own on public.app_records;
create policy app_records_delete_own on public.app_records for delete
  to authenticated using (user_id = auth.uid());

drop policy if exists invite_redemptions_select_own on public.invite_redemptions;
create policy invite_redemptions_select_own on public.invite_redemptions for select
  to authenticated using (user_id = auth.uid());

-- Do not expose invite hashes, redemption history, or arbitrary app-record
-- writes through PostgREST. The role column may only be changed by SQL/service
-- role; a regular user can update display_name only.
revoke all on table public.profiles, public.app_records, public.invite_codes, public.invite_redemptions from anon, authenticated;
grant select, update (display_name) on table public.profiles to authenticated;

create or replace function public.normalize_invite_code(p_code text)
returns text
language sql
immutable
strict
set search_path = public
as $$
  select upper(regexp_replace(trim(p_code), '\s+', '', 'g'))
$$;

create or replace function public.is_planer_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  )
$$;

-- Service-role only: the Edge Function calls this after it has created the
-- Auth user. SELECT ... FOR UPDATE serializes concurrent redemption attempts,
-- so used_count cannot exceed max_uses.
create or replace function public.consume_invite_for_user(
  p_code text,
  p_user_id uuid,
  p_display_name text default ''
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text := public.normalize_invite_code(p_code);
  v_hash text;
  v_invite public.invite_codes%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if v_code !~ '^[A-Z0-9_-]{6,64}$' then
    raise exception 'invite unavailable' using errcode = '22023';
  end if;
  v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');
  select * into v_invite
  from public.invite_codes
  where code_hash = v_hash
  for update;
  if not found or not v_invite.enabled or
     (v_invite.expires_at is not null and v_invite.expires_at <= now()) or
     v_invite.used_count >= v_invite.max_uses then
    raise exception 'invite unavailable' using errcode = '22023';
  end if;

  update public.invite_codes
  set used_count = used_count + 1
  where id = v_invite.id;
  insert into public.invite_redemptions (user_id, invite_id)
  values (p_user_id, v_invite.id);
  update public.profiles
  set display_name = coalesce(left(nullif(trim(p_display_name), ''), 80), display_name)
  where id = p_user_id;
end;
$$;

-- One RPC owns all cloud writes. The client submits a bounded batch; each
-- record can only be written under auth.uid(). LWW is deterministic: a later
-- client_updated_at wins; ties use the larger version. Tombstones are records
-- with deleted_at rather than destructive deletes.
create or replace function public.sync_app_records(p_records jsonb)
returns table (
  id text,
  collection text,
  payload jsonb,
  client_updated_at bigint,
  version bigint,
  deleted_at bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_input jsonb;
  v_id text;
  v_collection text;
  v_payload jsonb;
  v_updated bigint;
  v_version bigint;
  v_deleted bigint;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if jsonb_typeof(p_records) <> 'array' or jsonb_array_length(p_records) > 100 then
    raise exception 'invalid record batch' using errcode = '22023';
  end if;
  for v_input in select value from jsonb_array_elements(p_records)
  loop
    v_id := v_input ->> 'id';
    v_collection := v_input ->> 'collection';
    v_payload := v_input -> 'payload';
    v_updated := (v_input ->> 'client_updated_at')::bigint;
    v_version := greatest(coalesce((v_input ->> 'version')::bigint, 1), 1);
    v_deleted := nullif(v_input ->> 'deleted_at', '')::bigint;
    if v_id is null or v_collection is null or v_payload is null or
       jsonb_typeof(v_payload) <> 'object' or
       v_collection !~ '^[a-zA-Z][a-zA-Z0-9_]{0,63}$' or
       v_id !~ '^[a-zA-Z][a-zA-Z0-9_]{0,63}:.{1,135}$' or
       split_part(v_id, ':', 1) <> v_collection or v_updated <= 0 then
      raise exception 'invalid record' using errcode = '22023';
    end if;
    insert into public.app_records (user_id, id, collection, payload, client_updated_at, version, deleted_at)
    values (v_uid, v_id, v_collection, v_payload, v_updated, v_version, v_deleted)
    on conflict (user_id, id) do update set
      collection = excluded.collection,
      payload = excluded.payload,
      client_updated_at = excluded.client_updated_at,
      version = excluded.version,
      deleted_at = excluded.deleted_at
    where excluded.client_updated_at > public.app_records.client_updated_at
       or (excluded.client_updated_at = public.app_records.client_updated_at
           and excluded.version >= public.app_records.version);
  end loop;
  return query
    select r.id, r.collection, r.payload, r.client_updated_at, r.version,
           r.deleted_at, r.created_at, r.updated_at
    from public.app_records r
    where r.user_id = v_uid
      and r.id in (select value ->> 'id' from jsonb_array_elements(p_records));
end;
$$;

create or replace function public.get_app_records()
returns table (
  id text,
  collection text,
  payload jsonb,
  client_updated_at bigint,
  version bigint,
  deleted_at bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select id, collection, payload, client_updated_at, version, deleted_at, created_at, updated_at
  from public.app_records
  where user_id = auth.uid()
  order by client_updated_at asc, id asc
$$;

create or replace function public.admin_create_invite(
  p_code text,
  p_max_uses integer,
  p_expires_at timestamptz default null
)
returns table (
  id uuid,
  code_hint text,
  max_uses integer,
  used_count integer,
  expires_at timestamptz,
  enabled boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text := public.normalize_invite_code(p_code);
  v_hash text;
begin
  if not public.is_planer_admin() then raise exception 'admin required' using errcode = '42501'; end if;
  if v_code !~ '^[A-Z0-9_-]{6,64}$' or p_max_uses is null or p_max_uses < 1 or p_max_uses > 100000 or
     (p_expires_at is not null and p_expires_at <= now()) then
    raise exception 'invalid invite' using errcode = '22023';
  end if;
  v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');
  return query
    insert into public.invite_codes (code_hash, code_hint, max_uses, expires_at, created_by)
    values (v_hash, left(v_code, 4) || '••••', p_max_uses, p_expires_at, auth.uid())
    returning invite_codes.id, invite_codes.code_hint, invite_codes.max_uses,
      invite_codes.used_count, invite_codes.expires_at, invite_codes.enabled, invite_codes.created_at;
end;
$$;

create or replace function public.admin_list_invites()
returns table (
  id uuid,
  code_hint text,
  max_uses integer,
  used_count integer,
  expires_at timestamptz,
  enabled boolean,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select id, code_hint, max_uses, used_count, expires_at, enabled, created_at
  from public.invite_codes
  where public.is_planer_admin()
  order by created_at desc
$$;

create or replace function public.admin_set_invite_enabled(p_invite_id uuid, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_planer_admin() then raise exception 'admin required' using errcode = '42501'; end if;
  update public.invite_codes set enabled = p_enabled where id = p_invite_id;
  if not found then raise exception 'invite not found' using errcode = 'P0002'; end if;
end;
$$;

revoke all on function public.normalize_invite_code(text) from public, anon, authenticated;
revoke all on function public.is_planer_admin() from public, anon, authenticated;
revoke all on function public.consume_invite_for_user(text, uuid, text) from public, anon, authenticated;
revoke all on function public.sync_app_records(jsonb) from public, anon, authenticated;
revoke all on function public.get_app_records() from public, anon, authenticated;
revoke all on function public.admin_create_invite(text, integer, timestamptz) from public, anon, authenticated;
revoke all on function public.admin_list_invites() from public, anon, authenticated;
revoke all on function public.admin_set_invite_enabled(uuid, boolean) from public, anon, authenticated;
grant execute on function public.sync_app_records(jsonb) to authenticated;
grant execute on function public.get_app_records() to authenticated;
grant execute on function public.admin_create_invite(text, integer, timestamptz) to authenticated;
grant execute on function public.admin_list_invites() to authenticated;
grant execute on function public.admin_set_invite_enabled(uuid, boolean) to authenticated;

