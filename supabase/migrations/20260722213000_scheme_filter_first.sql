-- Scheme of Work scaling: filtered list RPCs and dashboard counts.

create index if not exists idx_scheme_school_status_submitted
  on public.scheme_of_work (school_id, status, submitted_at desc);

create index if not exists idx_scheme_school_status_department_submitted
  on public.scheme_of_work (school_id, status, department, submitted_at desc);

create index if not exists idx_scheme_school_hod_reviewer_decision
  on public.scheme_of_work (school_id, hod_reviewer_id, hod_decision_at desc);

create index if not exists idx_scheme_school_head_reviewer_decision
  on public.scheme_of_work (school_id, head_academic_reviewer_id, head_academic_decision_at desc);

create index if not exists idx_scheme_history_school_scheme_created
  on public.scheme_of_work_history (school_id, scheme_id, created_at);

create or replace function public.secure_list_scheme_of_work(
  p_school_id uuid,
  p_filters jsonb default '{}'::jsonb,
  p_session_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid := nullif(p_filters->>'teacherId', '')::uuid;
  v_reviewer_id uuid := nullif(p_filters->>'reviewerId', '')::uuid;
  v_department text := nullif(btrim(p_filters->>'department'), '');
  v_status text := nullif(btrim(p_filters->>'status'), '');
  v_queue text := lower(nullif(btrim(p_filters->>'queue'), ''));
  v_history text := lower(nullif(btrim(p_filters->>'history'), ''));
  v_search text := nullif(btrim(p_filters->>'search'), '');
  v_limit integer := least(greatest(coalesce((p_filters->>'limit')::integer, 100), 1), 500);
  v_offset integer := greatest(coalesce((p_filters->>'from')::integer, 0), 0);
  v_result jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.submitted_at desc, row_data.id desc), '[]'::jsonb)
  into v_result
  from (
    select
      sow.*,
      jsonb_build_object(
        'id', su.id,
        'full_name', su.full_name,
        'staff_id', su.staff_id,
        'department', su.department,
        'position_responsibility', su.position_responsibility
      ) as teacher
    from public.scheme_of_work sow
    left join public.staff_users su on su.id = sow.teacher_id
    where sow.school_id = p_school_id
      and (v_teacher_id is null or sow.teacher_id = v_teacher_id)
      and (v_department is null or lower(btrim(sow.department)) = lower(btrim(v_department)))
      and (v_status is null or sow.status = v_status)
      and (
        v_queue is null
        or (v_queue = 'hod'
          and sow.status = 'Pending HOD'
          and (v_department is null or lower(btrim(sow.department)) = lower(btrim(v_department)))
          and (v_reviewer_id is null or sow.teacher_id <> v_reviewer_id))
        or (v_queue in ('head', 'final', 'head_academic')
          and sow.status = 'Pending Head Academic')
      )
      and (
        v_history is null
        or (v_history = 'hod' and v_reviewer_id is not null and sow.hod_reviewer_id = v_reviewer_id)
        or (v_history in ('head', 'final', 'head_academic') and v_reviewer_id is not null and sow.head_academic_reviewer_id = v_reviewer_id)
      )
      and (
        v_search is null
        or sow.title ilike '%' || v_search || '%'
        or sow.class_name ilike '%' || v_search || '%'
        or sow.subject_name ilike '%' || v_search || '%'
        or coalesce(su.full_name, '') ilike '%' || v_search || '%'
        or coalesce(su.staff_id, '') ilike '%' || v_search || '%'
      )
    order by sow.submitted_at desc, sow.id desc
    offset v_offset
    limit v_limit
  ) row_data;

  return v_result;
end;
$$;

create or replace function public.secure_scheme_work_summary(
  p_school_id uuid,
  p_staff_id uuid,
  p_department text default null,
  p_is_hod boolean default false,
  p_is_head_academic boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_department text := nullif(btrim(p_department), '');
  v_result jsonb;
begin
  select jsonb_build_object(
    'minePendingHod', count(*) filter (where teacher_id = p_staff_id and status = 'Pending HOD'),
    'minePendingFinal', count(*) filter (where teacher_id = p_staff_id and status = 'Pending Head Academic'),
    'mineApproved', count(*) filter (where teacher_id = p_staff_id and status = 'Final Approved'),
    'mineDeclined', count(*) filter (where teacher_id = p_staff_id and status like 'Declined%'),
    'hodQueue', count(*) filter (
      where p_is_hod
        and status = 'Pending HOD'
        and teacher_id <> p_staff_id
        and v_department is not null
        and lower(btrim(department)) = lower(btrim(v_department))
    ),
    'finalQueue', count(*) filter (
      where p_is_head_academic
        and status = 'Pending Head Academic'
    )
  )
  into v_result
  from public.scheme_of_work
  where school_id = p_school_id;

  return coalesce(v_result, '{}'::jsonb);
end;
$$;

grant execute on function public.secure_list_scheme_of_work(uuid, jsonb, text) to anon, authenticated, service_role;
grant execute on function public.secure_scheme_work_summary(uuid, uuid, text, boolean, boolean) to anon, authenticated, service_role;
