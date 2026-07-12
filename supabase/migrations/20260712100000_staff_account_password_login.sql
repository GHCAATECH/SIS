-- Staff and School Admin login fallback using explicit account_password, not date of birth.
-- This supports accounts that have not yet been linked to Supabase Auth.

create or replace function public.resolve_staff_password_login(
  p_identifier text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_identifier text := lower(trim(coalesce(p_identifier, '')));
  clean_password text := coalesce(p_password, '');
  staff_record public.staff_users;
  school_record public.schools;
  privilege_keys jsonb := '[]'::jsonb;
begin
  if clean_identifier = '' or clean_password = '' then
    return null;
  end if;

  select *
    into staff_record
  from public.staff_users
  where status = 'Active'
    and coalesce(account_password, '') = clean_password
    and (
      lower(coalesce(staff_id, '')) = clean_identifier
      or lower(coalesce(username, '')) = clean_identifier
      or lower(coalesce(email, '')) = clean_identifier
    )
  limit 1;

  if staff_record.id is null then
    return null;
  end if;

  select *
    into school_record
  from public.schools
  where id = staff_record.school_id
  limit 1;

  if school_record.id is null then
    return null;
  end if;

  if coalesce(school_record.subscription_status, 'Active') = 'Suspended' then
    return null;
  end if;

  if coalesce(school_record.subscription_status, 'Active') = 'Trial'
     and school_record.trial_expires_at is not null
     and school_record.trial_expires_at < now() then
    return null;
  end if;

  select coalesce(jsonb_agg(page_key order by page_key), '[]'::jsonb)
    into privilege_keys
  from public.user_privileges
  where staff_user_id = staff_record.id;

  update public.staff_users
  set last_login_at = now()
  where id = staff_record.id;

  return jsonb_build_object(
    'id', staff_record.id,
    'auth_user_id', staff_record.auth_user_id,
    'full_name', staff_record.full_name,
    'staff_id', staff_record.staff_id,
    'username', staff_record.username,
    'email', staff_record.email,
    'role', staff_record.role,
    'category', staff_record.category,
    'position_responsibility', staff_record.position_responsibility,
    'position', staff_record.position_responsibility,
    'department', staff_record.department,
    'rank', staff_record.rank,
    'school_id', staff_record.school_id,
    'school_code', school_record.code,
    'school_name', school_record.name,
    'isAdmin', staff_record.category = 'School Administrator',
    'privileges', privilege_keys
  );
end;
$$;

grant execute on function public.resolve_staff_password_login(text, text) to anon, authenticated, service_role;
