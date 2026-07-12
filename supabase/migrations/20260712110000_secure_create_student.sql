-- Secure student registration insert for the admin portal.
-- Use this when production RLS is enabled.

create or replace function public.secure_create_student(
  p_school_id uuid,
  p_payload jsonb
)
returns public.students
language plpgsql
security definer
set search_path = public
as $$
declare
  saved public.students;
  v_class_id uuid := nullif(p_payload->>'class_id', '')::uuid;
  v_house_id uuid := nullif(p_payload->>'house_id', '')::uuid;
begin
  if not public.can_manage_school(p_school_id) then
    raise exception 'Access denied: school administrator privileges required.';
  end if;

  if v_class_id is not null and not exists (
    select 1 from public.classes where id = v_class_id and school_id = p_school_id
  ) then
    raise exception 'Selected class does not belong to this school.';
  end if;

  if v_house_id is not null and not exists (
    select 1 from public.houses where id = v_house_id and school_id = p_school_id
  ) then
    raise exception 'Selected house does not belong to this school.';
  end if;

  insert into public.students (
    school_id,
    class_id,
    house_id,
    ass_ref_id,
    surname,
    first_name,
    other_names,
    ghana_card_number,
    gender,
    disability_status,
    date_of_birth,
    guardian_name,
    relationship,
    phone_number,
    profession,
    residential_address,
    residential_status,
    year_admitted,
    student_level,
    passport_url,
    status,
    inserted_by
  ) values (
    p_school_id,
    v_class_id,
    v_house_id,
    coalesce(nullif(p_payload->>'ass_ref_id', ''), 'STD-' || extract(epoch from now())::bigint::text),
    nullif(p_payload->>'surname', ''),
    nullif(p_payload->>'first_name', ''),
    nullif(p_payload->>'other_names', ''),
    nullif(p_payload->>'ghana_card_number', ''),
    nullif(p_payload->>'gender', ''),
    coalesce(nullif(p_payload->>'disability_status', ''), 'No'),
    nullif(p_payload->>'date_of_birth', '')::date,
    nullif(p_payload->>'guardian_name', ''),
    nullif(p_payload->>'relationship', ''),
    nullif(p_payload->>'phone_number', ''),
    nullif(p_payload->>'profession', ''),
    nullif(p_payload->>'residential_address', ''),
    nullif(p_payload->>'residential_status', ''),
    nullif(p_payload->>'year_admitted', '')::integer,
    nullif(p_payload->>'student_level', ''),
    nullif(p_payload->>'passport_url', ''),
    coalesce(nullif(p_payload->>'status', ''), 'Active'),
    coalesce(nullif(p_payload->>'inserted_by', ''), 'Admin')
  )
  returning * into saved;

  return saved;
end;
$$;

grant execute on function public.secure_create_student(uuid, jsonb) to authenticated, service_role;
