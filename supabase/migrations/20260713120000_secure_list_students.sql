-- Secure student listing for Manage Students.
-- Run this after production RLS is enabled.

create or replace function public.secure_list_students(p_school_id uuid)
returns table (
  id uuid,
  school_id uuid,
  class_id uuid,
  house_id uuid,
  auth_user_id uuid,
  ass_ref_id text,
  surname text,
  first_name text,
  other_names text,
  ghana_card_number text,
  gender text,
  disability_status text,
  date_of_birth date,
  guardian_name text,
  relationship text,
  phone_number text,
  profession text,
  residential_address text,
  residential_status text,
  year_admitted integer,
  student_level text,
  passport_url text,
  status text,
  inserted_by text,
  created_at timestamptz,
  updated_at timestamptz,
  classes jsonb,
  houses jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id,
    s.school_id,
    s.class_id,
    s.house_id,
    s.auth_user_id,
    s.ass_ref_id,
    s.surname,
    s.first_name,
    s.other_names,
    s.ghana_card_number,
    s.gender,
    s.disability_status,
    s.date_of_birth,
    s.guardian_name,
    s.relationship,
    s.phone_number,
    s.profession,
    s.residential_address,
    s.residential_status,
    s.year_admitted,
    s.student_level,
    s.passport_url,
    s.status,
    s.inserted_by,
    s.created_at,
    s.updated_at,
    case
      when c.id is null then null
      else jsonb_build_object(
        'name', c.name,
        'year_level', c.year_level,
        'programmes', case
          when p.id is null then null
          else jsonb_build_object('name', p.name)
        end
      )
    end as classes,
    case
      when h.id is null then null
      else jsonb_build_object('name', h.name)
    end as houses
  from public.students s
  left join public.classes c on c.id = s.class_id
  left join public.programmes p on p.id = c.programme_id
  left join public.houses h on h.id = s.house_id
  where s.school_id = p_school_id
    and (
      s.auth_user_id = auth.uid()
      or public.can_manage_school(s.school_id)
      or public.has_page_privilege('studentperprogram', s.school_id)
      or public.has_page_privilege('cass', s.school_id)
      or public.has_page_privilege('downloadresult', s.school_id)
      or public.has_page_privilege('transcript', s.school_id)
    )
  order by s.created_at desc;
$$;

grant execute on function public.secure_list_students(uuid) to authenticated, service_role;
