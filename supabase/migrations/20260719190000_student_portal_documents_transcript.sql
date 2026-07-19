-- Student portal reads for password-session users. The session token determines
-- the student; browser-supplied student IDs are never trusted.

create or replace function public.current_student_id_or_session(
  p_session_token text default null
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select login.student_id
      from public.student_login_sessions login
      join public.students student on student.id = login.student_id
      where login.session_token = p_session_token
        and login.expires_at > now()
        and coalesce(student.status, 'Active') <> 'Deleted'
      limit 1
    ),
    (
      select student.id
      from public.students student
      where student.auth_user_id = auth.uid()
        and coalesce(student.status, 'Active') <> 'Deleted'
      limit 1
    )
  );
$$;

grant execute on function public.current_student_id_or_session(text)
  to anon, authenticated, service_role;

create or replace function public.secure_student_portal_documents(
  p_session_token text default null
)
returns setof public.documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
begin
  v_student_id := public.current_student_id_or_session(p_session_token);

  if v_student_id is null then
    raise exception 'Student session expired. Please logout and login again.';
  end if;

  if nullif(trim(coalesce(p_session_token, '')), '') is not null then
    update public.student_login_sessions
    set last_seen_at = now()
    where session_token = p_session_token
      and student_id = v_student_id
      and expires_at > now();
  end if;

  return query
    select document.*
    from public.documents document
    where document.owner_type = 'student'
      and document.student_id = v_student_id
    order by document.uploaded_at desc;
end;
$$;

create or replace function public.secure_student_portal_transcript(
  p_session_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_student jsonb;
  v_scores jsonb;
  v_summaries jsonb;
begin
  v_student_id := public.current_student_id_or_session(p_session_token);

  if v_student_id is null then
    raise exception 'Student session expired. Please logout and login again.';
  end if;

  if nullif(trim(coalesce(p_session_token, '')), '') is not null then
    update public.student_login_sessions
    set last_seen_at = now()
    where session_token = p_session_token
      and student_id = v_student_id
      and expires_at > now();
  end if;

  select to_jsonb(student) || jsonb_build_object(
    'classes', jsonb_build_object(
      'name', class_row.name,
      'programmes', jsonb_build_object('name', programme.name)
    )
  )
  into v_student
  from public.students student
  left join public.classes class_row on class_row.id = student.class_id
  left join public.programmes programme on programme.id = class_row.programme_id
  where student.id = v_student_id;

  select coalesce(jsonb_agg(
    to_jsonb(score) || jsonb_build_object(
      'assessments', to_jsonb(assessment) || jsonb_build_object(
        'subjects', to_jsonb(subject),
        'classes', to_jsonb(class_row),
        'assessment_modes', to_jsonb(mode)
      )
    ) order by score.updated_at desc
  ), '[]'::jsonb)
  into v_scores
  from public.assessment_scores score
  join public.assessments assessment on assessment.id = score.assessment_id
  left join public.subjects subject on subject.id = assessment.subject_id
  left join public.classes class_row on class_row.id = assessment.class_id
  left join public.assessment_modes mode on mode.id = assessment.assessment_mode_id
  where score.student_id = v_student_id
    and assessment.status = 'Submitted';

  select coalesce(jsonb_agg(
    to_jsonb(summary) order by summary.calculated_at desc
  ), '[]'::jsonb)
  into v_summaries
  from public.result_summaries summary
  where summary.student_id = v_student_id;

  return jsonb_build_object(
    'student', coalesce(v_student, '{}'::jsonb),
    'scores', v_scores,
    'summaries', v_summaries
  );
end;
$$;

revoke all on function public.secure_student_portal_documents(text)
  from public;
revoke all on function public.secure_student_portal_transcript(text)
  from public;

grant execute on function public.secure_student_portal_documents(text)
  to anon, authenticated, service_role;
grant execute on function public.secure_student_portal_transcript(text)
  to anon, authenticated, service_role;
