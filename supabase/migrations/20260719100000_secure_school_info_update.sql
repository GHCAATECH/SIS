-- Secure school profile reads and updates for school administrators.

alter table public.schools
  add column if not exists category text,
  add column if not exists ownership text,
  add column if not exists region text,
  add column if not exists district text,
  add column if not exists phone text,
  add column if not exists email text,
  add column if not exists postal_address text,
  add column if not exists motto text,
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.secure_school_info_context(
  p_session_token text default null,
  p_school_id uuid default null
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_staff public.staff_users;
  v_school_id uuid;
begin
  if nullif(btrim(coalesce(p_session_token, '')), '') is not null then
    select session_staff.*
      into v_staff
    from public.staff_from_login_session(p_session_token) session_staff
    limit 1;

    if v_staff.id is null
       or lower(coalesce(v_staff.category, '')) <> 'school administrator' then
      raise exception 'Access denied: school administrator privileges required.';
    end if;

    if p_school_id is not null and p_school_id <> v_staff.school_id then
      raise exception 'Access denied: the selected school does not match this account.';
    end if;

    return v_staff.school_id;
  end if;

  v_school_id := coalesce(p_school_id, public.current_school_id());
  if v_school_id is null or not public.can_manage_school(v_school_id) then
    raise exception 'Access denied: school administrator privileges required.';
  end if;

  return v_school_id;
end;
$function$;

create or replace function public.secure_get_school_info(
  p_session_token text default null,
  p_school_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_school_id uuid;
  v_school public.schools;
begin
  v_school_id := public.secure_school_info_context(p_session_token, p_school_id);

  select school.*
    into v_school
  from public.schools school
  where school.id = v_school_id;

  if v_school.id is null then
    raise exception 'School record was not found.';
  end if;

  return to_jsonb(v_school);
end;
$function$;

create or replace function public.secure_update_school_info(
  p_session_token text default null,
  p_school_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_school_id uuid;
  v_school public.schools;
  v_name text := btrim(coalesce(p_payload->>'name', ''));
begin
  v_school_id := public.secure_school_info_context(p_session_token, p_school_id);

  if v_name = '' then
    raise exception 'School name is required.';
  end if;

  update public.schools school
  set name = v_name,
      category = nullif(btrim(coalesce(p_payload->>'category', '')), ''),
      ownership = nullif(btrim(coalesce(p_payload->>'ownership', '')), ''),
      region = nullif(btrim(coalesce(p_payload->>'region', '')), ''),
      district = nullif(btrim(coalesce(p_payload->>'district', '')), ''),
      phone = nullif(btrim(coalesce(p_payload->>'phone', '')), ''),
      email = nullif(btrim(coalesce(p_payload->>'email', '')), ''),
      postal_address = nullif(btrim(coalesce(p_payload->>'postal_address', '')), ''),
      motto = nullif(btrim(coalesce(p_payload->>'motto', '')), ''),
      updated_at = now()
  where school.id = v_school_id
  returning school.* into v_school;

  if v_school.id is null then
    raise exception 'School record was not found.';
  end if;

  return to_jsonb(v_school);
end;
$function$;

revoke all on function public.secure_school_info_context(text, uuid) from public;
revoke all on function public.secure_get_school_info(text, uuid) from public;
revoke all on function public.secure_update_school_info(text, uuid, jsonb) from public;

grant execute on function public.secure_get_school_info(text, uuid) to anon, authenticated, service_role;
grant execute on function public.secure_update_school_info(text, uuid, jsonb) to anon, authenticated, service_role;
