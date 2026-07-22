-- Step 5 scaling: filter-first document manager loading.
-- Run this in Supabase SQL editor before relying on the new filtered document UI online.

create extension if not exists pg_trgm;

create index if not exists idx_documents_school_owner_uploaded
  on public.documents (school_id, owner_type, uploaded_at desc);

create index if not exists idx_documents_school_student_uploaded
  on public.documents (school_id, student_id, uploaded_at desc);

create index if not exists idx_documents_school_staff_uploaded
  on public.documents (school_id, staff_user_id, uploaded_at desc);

create index if not exists idx_documents_title_trgm
  on public.documents using gin (title gin_trgm_ops);

create index if not exists idx_documents_file_name_trgm
  on public.documents using gin (file_name gin_trgm_ops);

create index if not exists idx_students_school_class_status
  on public.students (school_id, class_id, status);

create index if not exists idx_students_ass_ref_trgm
  on public.students using gin (ass_ref_id gin_trgm_ops);

create index if not exists idx_staff_users_staff_id_trgm
  on public.staff_users using gin (staff_id gin_trgm_ops);

create or replace function public.secure_list_document_owners(
  p_school_id uuid,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_type text := lower(coalesce(p_filters->>'ownerType', p_filters->>'type', ''));
  v_search text := nullif(trim(coalesce(p_filters->>'search', '')), '');
  v_class_id uuid := null;
  v_limit integer := least(greatest(coalesce((p_filters->>'limit')::integer, 50), 1), 100);
  v_offset integer := greatest(coalesce((p_filters->>'from')::integer, ((greatest(coalesce((p_filters->>'page')::integer, 1), 1) - 1) * least(greatest(coalesce((p_filters->>'limit')::integer, 50), 1), 100))), 0);
  v_classes jsonb := '[]'::jsonb;
  v_students jsonb := '[]'::jsonb;
  v_staff jsonb := '[]'::jsonb;
begin
  if coalesce(p_filters->>'classId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_class_id := (p_filters->>'classId')::uuid;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name), '[]'::jsonb)
    into v_classes
  from public.classes c
  where c.school_id = p_school_id;

  if v_owner_type = 'student' then
    select coalesce(jsonb_agg(to_jsonb(src)), '[]'::jsonb)
      into v_students
    from (
      select
        s.id,
        s.ass_ref_id,
        s.ass_ref_id as student_id,
        concat_ws(' ', s.first_name, s.surname, s.other_names) as name,
        s.first_name,
        s.surname,
        s.other_names,
        s.class_id,
        c.name as class_name
      from public.students s
      left join public.classes c on c.id = s.class_id
      where s.school_id = p_school_id
        and coalesce(s.status, '') <> 'Deleted'
        and (v_class_id is null or s.class_id = v_class_id)
        and (
          v_search is null
          or s.ass_ref_id ilike '%' || v_search || '%'
          or concat_ws(' ', s.first_name, s.surname, s.other_names) ilike '%' || v_search || '%'
        )
      order by s.surname nulls last, s.first_name nulls last, s.ass_ref_id
      offset v_offset
      limit v_limit
    ) src;
  elsif v_owner_type = 'staff' then
    select coalesce(jsonb_agg(to_jsonb(src)), '[]'::jsonb)
      into v_staff
    from (
      select
        su.id,
        su.staff_id,
        coalesce(su.full_name, su.staff_name, su.name) as name,
        su.full_name,
        su.staff_name,
        su.name,
        su.email
      from public.staff_users su
      where su.school_id = p_school_id
        and coalesce(su.status, 'Active') <> 'Deleted'
        and (
          v_search is null
          or su.staff_id ilike '%' || v_search || '%'
          or coalesce(su.full_name, su.staff_name, su.name, '') ilike '%' || v_search || '%'
          or coalesce(su.email, '') ilike '%' || v_search || '%'
        )
      order by coalesce(su.full_name, su.staff_name, su.name) nulls last, su.staff_id
      offset v_offset
      limit v_limit
    ) src;
  end if;

  return jsonb_build_object(
    'classes', v_classes,
    'students', v_students,
    'staff', v_staff
  );
end;
$$;

create or replace function public.secure_list_documents(
  p_school_id uuid,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_type text := lower(coalesce(p_filters->>'ownerType', p_filters->>'type', ''));
  v_search text := nullif(trim(coalesce(p_filters->>'search', '')), '');
  v_owner_id uuid := null;
  v_limit integer := least(greatest(coalesce((p_filters->>'limit')::integer, 100), 1), 500);
  v_offset integer := greatest(coalesce((p_filters->>'from')::integer, ((greatest(coalesce((p_filters->>'page')::integer, 1), 1) - 1) * least(greatest(coalesce((p_filters->>'limit')::integer, 100), 1), 500))), 0);
  v_rows jsonb := '[]'::jsonb;
begin
  if coalesce(p_filters->>'ownerId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_owner_id := (p_filters->>'ownerId')::uuid;
  end if;

  select coalesce(jsonb_agg(to_jsonb(src)), '[]'::jsonb)
    into v_rows
  from (
    select
      d.*,
      case
        when d.owner_type = 'student' then concat_ws(' ', s.first_name, s.surname, s.other_names)
        else coalesce(su.full_name, su.staff_name, su.name)
      end as owner_name,
      case
        when d.owner_type = 'student' then s.ass_ref_id
        else su.staff_id
      end as owner_code
    from public.documents d
    left join public.students s on s.id = d.student_id
    left join public.staff_users su on su.id = d.staff_user_id
    where d.school_id = p_school_id
      and (v_owner_type = '' or d.owner_type = v_owner_type)
      and (
        v_owner_id is null
        or (d.owner_type = 'student' and d.student_id = v_owner_id)
        or (d.owner_type = 'staff' and d.staff_user_id = v_owner_id)
      )
      and (
        v_search is null
        or d.title ilike '%' || v_search || '%'
        or d.file_name ilike '%' || v_search || '%'
        or concat_ws(' ', s.first_name, s.surname, s.other_names) ilike '%' || v_search || '%'
        or coalesce(s.ass_ref_id, '') ilike '%' || v_search || '%'
        or coalesce(su.full_name, su.staff_name, su.name, '') ilike '%' || v_search || '%'
        or coalesce(su.staff_id, '') ilike '%' || v_search || '%'
      )
    order by d.uploaded_at desc nulls last, d.id desc
    offset v_offset
    limit v_limit
  ) src;

  return v_rows;
end;
$$;

grant execute on function public.secure_list_document_owners(uuid, jsonb) to anon, authenticated;
grant execute on function public.secure_list_documents(uuid, jsonb) to anon, authenticated;
