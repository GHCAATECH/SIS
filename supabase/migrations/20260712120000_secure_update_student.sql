-- Secure student profile update for the admin portal.
-- Use this when production RLS is enabled.

create or replace function public.secure_update_student_by_ass_ref(
  p_school_id uuid,
  p_ass_ref_id text,
  p_payload jsonb
)
returns public.students
language plpgsql
security definer
set search_path = public
as $$
declare
  saved public.students;
  v_class_id uuid;
  v_house_id uuid;
begin
  if not public.can_manage_school(p_school_id) then
    raise exception 'Access denied: school administrator privileges required.';
  end if;

  if nullif(p_payload->>'class_id', '') is not null then
    v_class_id := (p_payload->>'class_id')::uuid;
    if not exists (select 1 from public.classes where id = v_class_id and school_id = p_school_id) then
      raise exception 'Selected class does not belong to this school.';
    end if;
  end if;

  if p_payload ? 'house_id' and nullif(p_payload->>'house_id', '') is not null then
    v_house_id := (p_payload->>'house_id')::uuid;
    if not exists (select 1 from public.houses where id = v_house_id and school_id = p_school_id) then
      raise exception 'Selected house does not belong to this school.';
    end if;
  end if;

  update public.students
  set class_id = case when p_payload ? 'class_id' then v_class_id else class_id end,
      house_id = case when p_payload ? 'house_id' then v_house_id else house_id end,
      surname = coalesce(nullif(p_payload->>'surname', ''), surname),
      first_name = coalesce(nullif(p_payload->>'first_name', ''), first_name),
      other_names = case when p_payload ? 'other_names' then nullif(p_payload->>'other_names', '') else other_names end,
      ghana_card_number = case when p_payload ? 'ghana_card_number' then nullif(p_payload->>'ghana_card_number', '') else ghana_card_number end,
      gender = coalesce(nullif(p_payload->>'gender', ''), gender),
      disability_status = coalesce(nullif(p_payload->>'disability_status', ''), disability_status),
      date_of_birth = coalesce(nullif(p_payload->>'date_of_birth', '')::date, date_of_birth),
      guardian_name = case when p_payload ? 'guardian_name' then nullif(p_payload->>'guardian_name', '') else guardian_name end,
      relationship = case when p_payload ? 'relationship' then nullif(p_payload->>'relationship', '') else relationship end,
      phone_number = case when p_payload ? 'phone_number' then nullif(p_payload->>'phone_number', '') else phone_number end,
      profession = case when p_payload ? 'profession' then nullif(p_payload->>'profession', '') else profession end,
      residential_address = case when p_payload ? 'residential_address' then nullif(p_payload->>'residential_address', '') else residential_address end,
      residential_status = case when p_payload ? 'residential_status' then nullif(p_payload->>'residential_status', '') else residential_status end,
      year_admitted = case when p_payload ? 'year_admitted' then nullif(p_payload->>'year_admitted', '')::integer else year_admitted end,
      student_level = case when p_payload ? 'student_level' then nullif(p_payload->>'student_level', '') else student_level end,
      passport_url = case when p_payload ? 'passport_url' then nullif(p_payload->>'passport_url', '') else passport_url end,
      status = coalesce(nullif(p_payload->>'status', ''), status),
      inserted_by = case when p_payload ? 'inserted_by' then nullif(p_payload->>'inserted_by', '') else inserted_by end,
      updated_at = now()
  where school_id = p_school_id
    and ass_ref_id = p_ass_ref_id
  returning * into saved;

  if saved.id is null then
    raise exception 'Student record was not found.';
  end if;

  return saved;
end;
$$;

grant execute on function public.secure_update_student_by_ass_ref(uuid, text, jsonb) to authenticated, service_role;
