-- Allow completed / archived students to keep student portal access.
-- Only Deleted students are blocked.

create or replace function public.resolve_student_auth_login(
  p_ass_ref_id text,
  p_password text
)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  clean_ass_ref text := lower(btrim(coalesce(p_ass_ref_id, '')));
  clean_password text := btrim(coalesce(p_password, ''));
  target_student public.students;
  linked_student public.students;
  resolved_email text;
begin
  if clean_ass_ref = '' or clean_password = '' then
    return null;
  end if;

  select *
    into target_student
  from public.students
  where lower(coalesce(ass_ref_id, '')) = clean_ass_ref
    and coalesce(status, 'Active') <> 'Deleted'
  limit 1;

  if target_student.id is null then
    return null;
  end if;

  if clean_password not in (
    to_char(target_student.date_of_birth, 'MMDDYYYY'),
    to_char(target_student.date_of_birth, 'DDMMYYYY')
  ) then
    return null;
  end if;

  linked_student := public.link_student_auth_account_internal(target_student.id, clean_password);

  select email
    into resolved_email
  from auth.users
  where id = linked_student.auth_user_id
  limit 1;

  return resolved_email;
end;
$$;

grant execute on function public.resolve_student_auth_login(text, text) to anon, authenticated, service_role;
