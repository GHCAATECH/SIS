-- Prefer the student portal session token over any stale Supabase Auth session.
-- This prevents old/mixed browser Auth sessions from making the student clearance page return [].

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

grant execute on function public.current_student_id_or_session(text) to anon, authenticated, service_role;
