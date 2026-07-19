-- Allow authenticated staff-session accounts to read their own module access and
-- allow school administrators to manage module access for staff in their school.

create or replace function public.secure_list_user_privileges_with_session(
  p_session_token text,
  p_staff_user_id uuid default null
)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  actor public.staff_users;
  target_staff_id uuid;
  privilege_keys text[];
begin
  select * into actor
  from public.staff_from_login_session(p_session_token);

  if actor.id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  target_staff_id := coalesce(p_staff_user_id, actor.id);

  if target_staff_id <> actor.id and actor.category <> 'School Administrator' then
    raise exception 'Only a school administrator can view another staff user''s privileges.';
  end if;

  if not exists (
    select 1
    from public.staff_users target
    where target.id = target_staff_id
      and target.school_id = actor.school_id
  ) then
    raise exception 'Staff user does not belong to this school.';
  end if;

  update public.staff_login_sessions
  set last_seen_at = now()
  where session_token = p_session_token;

  select coalesce(array_agg(priv.page_key order by priv.page_key), array[]::text[])
    into privilege_keys
  from public.user_privileges priv
  where priv.school_id = actor.school_id
    and priv.staff_user_id = target_staff_id;

  return privilege_keys;
end;
$$;

create or replace function public.secure_save_user_privileges_with_session(
  p_session_token text,
  p_staff_user_id uuid,
  p_page_keys text[]
)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  actor public.staff_users;
  privilege_keys text[];
begin
  select * into actor
  from public.staff_from_login_session(p_session_token);

  if actor.id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  if actor.category <> 'School Administrator' then
    raise exception 'Only a school administrator can assign module privileges.';
  end if;

  if not exists (
    select 1
    from public.staff_users target
    where target.id = p_staff_user_id
      and target.school_id = actor.school_id
  ) then
    raise exception 'Staff user does not belong to this school.';
  end if;

  delete from public.user_privileges
  where school_id = actor.school_id
    and staff_user_id = p_staff_user_id;

  insert into public.user_privileges (school_id, staff_user_id, page_key)
  select actor.school_id, p_staff_user_id, key_value
  from (
    select distinct btrim(raw_key) as key_value
    from unnest(coalesce(p_page_keys, array[]::text[])) as keys(raw_key)
  ) clean_keys
  where key_value <> '';

  update public.staff_login_sessions
  set last_seen_at = now()
  where session_token = p_session_token;

  select coalesce(array_agg(priv.page_key order by priv.page_key), array[]::text[])
    into privilege_keys
  from public.user_privileges priv
  where priv.school_id = actor.school_id
    and priv.staff_user_id = p_staff_user_id;

  return privilege_keys;
end;
$$;

grant execute on function public.secure_list_user_privileges_with_session(text, uuid)
  to anon, authenticated, service_role;
grant execute on function public.secure_save_user_privileges_with_session(text, uuid, text[])
  to anon, authenticated, service_role;
