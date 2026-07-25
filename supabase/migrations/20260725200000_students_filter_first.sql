-- Filter-first student listing for Manage Students and other student lookup pages.

create extension if not exists pg_trgm;

create index if not exists idx_students_school_level_class_status_created
  on public.students (school_id, student_level, class_id, status, created_at desc);

create index if not exists idx_students_school_class_created
  on public.students (school_id, class_id, created_at desc);

create index if not exists idx_students_ass_ref_trgm
  on public.students using gin (ass_ref_id gin_trgm_ops);

create index if not exists idx_students_first_name_trgm
  on public.students using gin (first_name gin_trgm_ops);

create index if not exists idx_students_surname_trgm
  on public.students using gin (surname gin_trgm_ops);

create index if not exists idx_students_other_names_trgm
  on public.students using gin (other_names gin_trgm_ops);

create index if not exists idx_students_phone_number_trgm
  on public.students using gin (phone_number gin_trgm_ops);

create or replace function public.secure_list_students(
  p_school_id uuid,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rows jsonb;
  v_limit integer := least(greatest(coalesce(nullif(p_filters->>'limit', '')::integer, 1000), 1), 5000);
  v_page integer := greatest(coalesce(nullif(p_filters->>'page', '')::integer, 1), 1);
  v_offset integer := 0;
  v_year_level text := nullif(btrim(coalesce(p_filters->>'yearLevel', p_filters->>'year_level', '')), '');
  v_status text := nullif(btrim(coalesce(p_filters->>'status', '')), '');
  v_search text := nullif(btrim(coalesce(p_filters->>'search', '')), '');
  v_include_deleted boolean := coalesce((p_filters->>'includeDeleted')::boolean, false);
  v_class_id uuid := nullif(p_filters->>'classId', '')::uuid;
begin
  if p_school_id is null then
    raise exception 'School context is required.';
  end if;

  if not (
    public.can_manage_school(p_school_id)
    or public.has_page_privilege('studentperprogram', p_school_id)
    or public.has_page_privilege('cass', p_school_id)
    or public.has_page_privilege('downloadresult', p_school_id)
    or public.has_page_privilege('transcript', p_school_id)
    or exists (
      select 1
      from public.students own_student
      where own_student.school_id = p_school_id
        and own_student.auth_user_id = auth.uid()
    )
  ) then
    raise exception 'Access denied for student listing.';
  end if;

  v_offset := (v_page - 1) * v_limit;

  select coalesce(jsonb_agg(row_payload order by row_created_at desc, row_ass_ref_id), '[]'::jsonb)
    into rows
  from (
    select
      s.created_at as row_created_at,
      s.ass_ref_id as row_ass_ref_id,
      jsonb_build_object(
        'id', s.id,
        'school_id', s.school_id,
        'class_id', s.class_id,
        'house_id', s.house_id,
        'auth_user_id', s.auth_user_id,
        'ass_ref_id', s.ass_ref_id,
        'surname', s.surname,
        'first_name', s.first_name,
        'other_names', s.other_names,
        'ghana_card_number', s.ghana_card_number,
        'gender', s.gender,
        'disability_status', s.disability_status,
        'date_of_birth', s.date_of_birth,
        'guardian_name', s.guardian_name,
        'relationship', s.relationship,
        'phone_number', s.phone_number,
        'profession', s.profession,
        'residential_address', s.residential_address,
        'residential_status', s.residential_status,
        'year_admitted', s.year_admitted,
        'student_level', s.student_level,
        'passport_url', s.passport_url,
        'status', s.status,
        'inserted_by', s.inserted_by,
        'created_at', s.created_at,
        'updated_at', s.updated_at,
        'classes', case
          when cls.id is null then null
          else jsonb_build_object(
            'id', cls.id,
            'name', cls.name,
            'year_level', cls.year_level,
            'programmes', case
              when programme.id is null then null
              else jsonb_build_object('name', programme.name)
            end
          )
        end,
        'houses', case
          when house.id is null then null
          else jsonb_build_object('name', house.name)
        end
      ) as row_payload
    from public.students s
    left join public.classes cls on cls.id = s.class_id
    left join public.programmes programme on programme.id = cls.programme_id
    left join public.houses house on house.id = s.house_id
    where s.school_id = p_school_id
      and (v_include_deleted or lower(coalesce(s.status, 'active')) <> 'deleted')
      and (v_class_id is null or s.class_id = v_class_id)
      and (
        p_filters->'classIds' is null
        or jsonb_array_length(coalesce(p_filters->'classIds', '[]'::jsonb)) = 0
        or exists (
          select 1
          from jsonb_array_elements_text(p_filters->'classIds') class_filter(id_text)
          where nullif(class_filter.id_text, '')::uuid = s.class_id
        )
      )
      and (v_year_level is null or coalesce(nullif(s.student_level, ''), nullif(cls.year_level, '')) = v_year_level)
      and (v_status is null or s.status = v_status)
      and (
        v_search is null
        or s.ass_ref_id ilike '%' || v_search || '%'
        or s.first_name ilike '%' || v_search || '%'
        or s.surname ilike '%' || v_search || '%'
        or s.other_names ilike '%' || v_search || '%'
        or s.phone_number ilike '%' || v_search || '%'
      )
    order by s.created_at desc, s.ass_ref_id
    offset v_offset
    limit v_limit
  ) listed_students;

  return rows;
end;
$$;

grant execute on function public.secure_list_students(uuid, jsonb)
  to anon, authenticated, service_role;
