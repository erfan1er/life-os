-- Fix an ambiguity between the `id` output column of sync_app_records and
-- the app_records primary-key column. Using the named constraint keeps the
-- secure upsert semantics unchanged while making every valid sync batch work.

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
    on conflict on constraint app_records_pkey do update set
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

revoke all on function public.sync_app_records(jsonb) from public, anon, authenticated;
grant execute on function public.sync_app_records(jsonb) to authenticated;
