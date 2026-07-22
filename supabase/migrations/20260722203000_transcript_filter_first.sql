-- Step 6 scaling: filter-first and batch transcript export.
-- Run this in Supabase SQL editor before using large transcript exports online.

create extension if not exists pg_trgm;

create index if not exists idx_students_school_level_class_status
  on public.students (school_id, student_level, class_id, status);

create index if not exists idx_students_name_trgm
  on public.students using gin ((concat_ws(' ', first_name, surname, other_names)) gin_trgm_ops);

create index if not exists idx_assessment_scores_student_updated
  on public.assessment_scores (student_id, updated_at desc);

create index if not exists idx_assessments_school_status_year_semester
  on public.assessments (school_id, status, year_level, semester);

create index if not exists idx_result_summaries_school_student
  on public.result_summaries (school_id, student_id, calculated_at desc);

create or replace function public.secure_list_transcript_students(
  p_school_id uuid,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_search text := nullif(trim(coalesce(p_filters->>'search', '')), '');
  v_year text := nullif(trim(coalesce(p_filters->>'yearLevel', p_filters->>'year', '')), '');
  v_programme text := nullif(trim(coalesce(p_filters->>'programmeName', p_filters->>'programme', '')), '');
  v_class_name text := nullif(trim(coalesce(p_filters->>'className', '')), '');
  v_class_id uuid := null;
  v_limit integer := least(greatest(coalesce((p_filters->>'limit')::integer, 500), 1), 1000);
  v_page integer := greatest(coalesce((p_filters->>'page')::integer, 1), 1);
  v_offset integer := greatest(coalesce((p_filters->>'from')::integer, (greatest(coalesce((p_filters->>'page')::integer, 1), 1) - 1) * least(greatest(coalesce((p_filters->>'limit')::integer, 500), 1), 1000)), 0);
  v_rows jsonb := '[]'::jsonb;
begin
  if coalesce(p_filters->>'classId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_class_id := (p_filters->>'classId')::uuid;
  end if;

  select coalesce(jsonb_agg(to_jsonb(src)), '[]'::jsonb)
    into v_rows
  from (
    select
      s.id,
      s.ass_ref_id,
      s.first_name,
      s.surname,
      s.other_names,
      s.gender,
      s.date_of_birth,
      s.year_admitted,
      s.student_level,
      s.class_id,
      s.passport_url,
      s.profile_photo,
      s.photo_url,
      s.status,
      jsonb_build_object(
        'name', c.name,
        'programmes', jsonb_build_object('name', p.name)
      ) as classes
    from public.students s
    left join public.classes c on c.id = s.class_id
    left join public.programmes p on p.id = c.programme_id
    where s.school_id = p_school_id
      and coalesce(s.status, '') <> 'Deleted'
      and (v_year is null or coalesce(s.student_level, c.year_level, '') = v_year)
      and (v_class_id is null or s.class_id = v_class_id)
      and (v_class_name is null or c.name = v_class_name)
      and (v_programme is null or p.name = v_programme)
      and (
        v_search is null
        or s.ass_ref_id ilike '%' || v_search || '%'
        or concat_ws(' ', s.first_name, s.surname, s.other_names) ilike '%' || v_search || '%'
      )
    order by c.name nulls last, s.surname nulls last, s.first_name nulls last, s.ass_ref_id
    offset v_offset
    limit v_limit
  ) src;

  return v_rows;
end;
$$;

create or replace function public.secure_list_transcript_payloads(
  p_school_id uuid,
  p_student_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows jsonb := '[]'::jsonb;
begin
  if p_student_ids is null or array_length(p_student_ids, 1) is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'student', to_jsonb(stu),
      'scores', coalesce(score_rows.scores, '[]'::jsonb),
      'summaries', coalesce(summary_rows.summaries, '[]'::jsonb)
    )
    order by stu.surname nulls last, stu.first_name nulls last, stu.ass_ref_id
  ), '[]'::jsonb)
    into v_rows
  from (
    select
      s.*,
      jsonb_build_object(
        'name', c.name,
        'programmes', jsonb_build_object('name', p.name)
      ) as classes
    from public.students s
    left join public.classes c on c.id = s.class_id
    left join public.programmes p on p.id = c.programme_id
    where s.school_id = p_school_id
      and s.id = any(p_student_ids)
      and coalesce(s.status, '') <> 'Deleted'
  ) stu
  left join lateral (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'score', sc.score,
        'grade', sc.grade,
        'remark', sc.remark,
        'assessments', jsonb_build_object(
          'academic_year', a.academic_year,
          'year_level', a.year_level,
          'semester', a.semester,
          'overall_score', a.overall_score,
          'status', a.status,
          'subjects', jsonb_build_object(
            'name', subj.name,
            'subject_type', subj.subject_type
          ),
          'classes', jsonb_build_object('name', ac.name),
          'assessment_modes', jsonb_build_object(
            'name', am.name,
            'display_order', am.display_order
          )
        )
      )
      order by a.year_level, a.semester, subj.name, am.display_order nulls last
    ), '[]'::jsonb) as scores
    from public.assessment_scores sc
    join public.assessments a on a.id = sc.assessment_id
    left join public.subjects subj on subj.id = a.subject_id
    left join public.classes ac on ac.id = a.class_id
    left join public.assessment_modes am on am.id = a.assessment_mode_id
    where sc.student_id = stu.id
      and a.school_id = p_school_id
      and a.status = 'Submitted'
  ) score_rows on true
  left join lateral (
    select coalesce(jsonb_agg(to_jsonb(rs) order by rs.calculated_at desc), '[]'::jsonb) as summaries
    from public.result_summaries rs
    where rs.school_id = p_school_id
      and rs.student_id = stu.id
  ) summary_rows on true;

  return v_rows;
end;
$$;

grant execute on function public.secure_list_transcript_students(uuid, jsonb) to anon, authenticated;
grant execute on function public.secure_list_transcript_payloads(uuid, uuid[]) to anon, authenticated;
