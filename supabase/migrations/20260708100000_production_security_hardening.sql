-- Production hardening for AXIOMBYTE SMS multi-school security.
-- Run AFTER the existing schema migrations.
-- Important: create/link Supabase Auth users to staff_users.auth_user_id, students.auth_user_id,
-- and super_admins.auth_user_id before enforcing this in production.

create extension if not exists pgcrypto;

alter table public.schools
  add column if not exists status text not null default 'Active'
    check (status in ('Active', 'Suspended'));

alter table public.staff_users
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null;

alter table public.students
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null;

alter table public.super_admins
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null;

create index if not exists idx_staff_users_auth_user_id on public.staff_users(auth_user_id);
create index if not exists idx_students_auth_user_id on public.students(auth_user_id);
create index if not exists idx_super_admins_auth_user_id on public.super_admins(auth_user_id);

create or replace function public.current_staff_user()
returns public.staff_users
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.staff_users
  where auth_user_id = auth.uid()
    and status = 'Active'
  limit 1;
$$;

create or replace function public.current_student_user()
returns public.students
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.students
  where auth_user_id = auth.uid()
    and coalesce(status, 'Active') not in ('Transferred', 'Dropped', 'Completed')
  limit 1;
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.super_admins
    where auth_user_id = auth.uid()
      and status = 'Active'
  );
$$;

create or replace function public.can_manage_school(p_school_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin()
    or exists (
      select 1
      from public.staff_users staff
      where staff.auth_user_id = auth.uid()
        and staff.school_id = p_school_id
        and staff.status = 'Active'
        and staff.category = 'School Administrator'
    );
$$;

create or replace function public.current_school_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select staff.school_id from public.staff_users staff where staff.auth_user_id = auth.uid() and staff.status = 'Active' limit 1),
    (select student.school_id from public.students student where student.auth_user_id = auth.uid() limit 1)
  );
$$;

create or replace function public.is_teaching_staff_for_school(p_school_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff_users staff
    where staff.auth_user_id = auth.uid()
      and staff.school_id = p_school_id
      and staff.status = 'Active'
      and staff.category = 'Teaching Staff'
  );
$$;

create or replace function public.has_page_privilege(p_page_key text, p_school_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_school(p_school_id)
    or exists (
      select 1
      from public.staff_users staff
      join public.user_privileges priv on priv.staff_user_id = staff.id
      where staff.auth_user_id = auth.uid()
        and staff.school_id = p_school_id
        and priv.school_id = p_school_id
        and priv.page_key = p_page_key
        and staff.status = 'Active'
    );
$$;

create or replace function public.secure_save_user_privileges(
  p_school_id uuid,
  p_staff_user_id uuid,
  p_page_keys text[]
)
returns setof public.user_privileges
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_manage_school(p_school_id) then
    raise exception 'Access denied: school administrator privileges required.';
  end if;

  if not exists (select 1 from public.staff_users where id = p_staff_user_id and school_id = p_school_id) then
    raise exception 'Staff user does not belong to this school.';
  end if;

  delete from public.user_privileges
  where school_id = p_school_id
    and staff_user_id = p_staff_user_id;

  if coalesce(array_length(p_page_keys, 1), 0) > 0 then
    insert into public.user_privileges (school_id, staff_user_id, page_key)
    select p_school_id, p_staff_user_id, key_value
    from unnest(p_page_keys) as key_value
    where btrim(key_value) <> '';
  end if;

  return query
  select *
  from public.user_privileges
  where school_id = p_school_id
    and staff_user_id = p_staff_user_id
  order by page_key;
end;
$$;

create or replace function public.secure_create_staff_user(
  p_school_id uuid,
  p_payload jsonb
)
returns public.staff_users
language plpgsql
security definer
set search_path = public
as $$
declare
  saved public.staff_users;
begin
  if not public.can_manage_school(p_school_id) then
    raise exception 'Access denied: school administrator privileges required.';
  end if;

  insert into public.staff_users (
    school_id, auth_user_id, staff_name, staff_id, gender, date_of_birth, nationality,
    marital_status, profile_photo, ghana_card_number, social_security_number, ntc_number,
    full_name, username, email, phone, alternate_phone, residential_address, digital_address,
    emergency_contact_name, emergency_contact_phone, emergency_contact_relationship,
    category, role, first_appointment_date, date_posted_to_station, rank, date_placed_on_rank,
    employment_status, trained_status, position_responsibility, department, house_assigned,
    professional_qualification, academic_qualification, bank_name, branch_name, account_number,
    account_name, status
  ) values (
    p_school_id,
    nullif(p_payload->>'auth_user_id', '')::uuid,
    nullif(p_payload->>'staff_name', ''),
    nullif(p_payload->>'staff_id', ''),
    nullif(p_payload->>'gender', ''),
    nullif(p_payload->>'date_of_birth', '')::date,
    nullif(p_payload->>'nationality', ''),
    nullif(p_payload->>'marital_status', ''),
    nullif(p_payload->>'profile_photo', ''),
    nullif(p_payload->>'ghana_card_number', ''),
    nullif(p_payload->>'social_security_number', ''),
    nullif(p_payload->>'ntc_number', ''),
    coalesce(nullif(p_payload->>'full_name', ''), nullif(p_payload->>'staff_name', '')),
    coalesce(nullif(p_payload->>'username', ''), nullif(p_payload->>'staff_id', '')),
    coalesce(nullif(p_payload->>'email', ''), lower(regexp_replace(coalesce(p_payload->>'staff_id', gen_random_uuid()::text), '[^a-zA-Z0-9]+', '', 'g')) || '@axiombyte.local'),
    nullif(p_payload->>'phone', ''),
    nullif(p_payload->>'alternate_phone', ''),
    nullif(p_payload->>'residential_address', ''),
    nullif(p_payload->>'digital_address', ''),
    nullif(p_payload->>'emergency_contact_name', ''),
    nullif(p_payload->>'emergency_contact_phone', ''),
    nullif(p_payload->>'emergency_contact_relationship', ''),
    coalesce(nullif(p_payload->>'category', ''), 'Teaching Staff'),
    coalesce(nullif(p_payload->>'role', ''), nullif(p_payload->>'category', ''), 'Teaching Staff'),
    nullif(p_payload->>'first_appointment_date', '')::date,
    nullif(p_payload->>'date_posted_to_station', '')::date,
    nullif(p_payload->>'rank', ''),
    nullif(p_payload->>'date_placed_on_rank', '')::date,
    nullif(p_payload->>'employment_status', ''),
    nullif(p_payload->>'trained_status', ''),
    nullif(p_payload->>'position_responsibility', ''),
    nullif(p_payload->>'department', ''),
    nullif(p_payload->>'house_assigned', ''),
    nullif(p_payload->>'professional_qualification', ''),
    nullif(p_payload->>'academic_qualification', ''),
    nullif(p_payload->>'bank_name', ''),
    nullif(p_payload->>'branch_name', ''),
    nullif(p_payload->>'account_number', ''),
    nullif(p_payload->>'account_name', ''),
    coalesce(nullif(p_payload->>'status', ''), 'Active')
  ) returning * into saved;

  return saved;
end;
$$;

create or replace function public.secure_delete_document(p_document_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  doc public.documents;
begin
  select * into doc from public.documents where id = p_document_id;
  if not found then
    return false;
  end if;

  if not public.can_manage_school(doc.school_id)
     and not exists (
       select 1 from public.staff_users staff
       where staff.auth_user_id = auth.uid()
         and doc.owner_type = 'staff'
         and doc.staff_user_id = staff.id
     )
     and not exists (
       select 1 from public.students student
       where student.auth_user_id = auth.uid()
         and doc.owner_type = 'student'
         and doc.student_id = student.id
     ) then
    raise exception 'Access denied: you cannot delete this document.';
  end if;

  delete from public.documents where id = p_document_id;
  return true;
end;
$$;

create or replace function public.secure_save_assessment_scores(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_staff_id uuid;
  v_class_id uuid;
  v_subject_id uuid;
  v_mode_id uuid;
  v_assessment public.assessments;
  v_score jsonb;
  v_student_id uuid;
  v_score_count integer := 0;
begin
  v_school_id := nullif(p_payload->>'school_id', '')::uuid;
  if v_school_id is null then
    v_school_id := public.current_school_id();
  end if;

  select id into v_staff_id
  from public.staff_users
  where auth_user_id = auth.uid()
    and school_id = v_school_id
    and status = 'Active'
  limit 1;

  if v_staff_id is null and not public.is_super_admin() then
    raise exception 'Access denied: active staff account required.';
  end if;

  select id into v_class_id
  from public.classes
  where school_id = v_school_id
    and name = p_payload->>'className'
  limit 1;

  select id into v_subject_id
  from public.subjects
  where school_id = v_school_id
    and name = p_payload->>'subjectName'
  limit 1;

  select id into v_mode_id
  from public.assessment_modes
  where display_order = case
      when split_part(coalesce(p_payload->>'modeName', ''), '.', 1) ~ '^[0-9]+$'
      then split_part(coalesce(p_payload->>'modeName', ''), '.', 1)::int
      else null
    end
     or name = p_payload->>'modeName'
  order by display_order
  limit 1;

  if v_class_id is null or v_subject_id is null or v_mode_id is null then
    raise exception 'Class, subject, or assessment mode was not found.';
  end if;

  if not public.can_manage_school(v_school_id) and not exists (
    select 1
    from public.staff_subject_classes assign
    where assign.school_id = v_school_id
      and assign.staff_user_id = v_staff_id
      and assign.class_id = v_class_id
      and assign.subject_id = v_subject_id
  ) then
    raise exception 'You are not assigned to capture scores for this class and subject.';
  end if;

  insert into public.assessments (
    school_id, academic_year, class_id, subject_id, assessment_mode_id,
    year_level, semester, overall_score, inserted_by, status, submitted_at
  ) values (
    v_school_id,
    p_payload->>'academicYear',
    v_class_id,
    v_subject_id,
    v_mode_id,
    p_payload->>'yearLevel',
    p_payload->>'semester',
    (p_payload->>'overallScore')::numeric,
    coalesce(p_payload->>'capturedBy', 'System'),
    coalesce(p_payload->>'status', 'Draft'),
    case when p_payload->>'status' = 'Submitted' then now() else null end
  )
  on conflict (school_id, academic_year, semester, year_level, class_id, subject_id, assessment_mode_id)
  do update set
    overall_score = excluded.overall_score,
    inserted_by = excluded.inserted_by,
    status = excluded.status,
    submitted_at = excluded.submitted_at
  returning * into v_assessment;

  for v_score in select * from jsonb_array_elements(coalesce(p_payload->'scores', '[]'::jsonb)) loop
    select id into v_student_id
    from public.students
    where school_id = v_school_id
      and ass_ref_id = v_score->>'assRef'
    limit 1;

    if v_student_id is not null then
      if nullif(v_score->>'score', '')::numeric > v_assessment.overall_score then
        raise exception 'Score is greater than overall score for STD_ID %.', v_score->>'assRef';
      end if;
      insert into public.assessment_scores (assessment_id, student_id, score, grade, remark)
      values (
        v_assessment.id,
        v_student_id,
        nullif(v_score->>'score', '')::numeric,
        nullif(v_score->>'grade', ''),
        nullif(v_score->>'remark', '')
      )
      on conflict (assessment_id, student_id)
      do update set
        score = excluded.score,
        grade = excluded.grade,
        remark = excluded.remark,
        updated_at = now();
      v_score_count := v_score_count + 1;
    end if;
  end loop;

  return jsonb_build_object('assessment_id', v_assessment.id, 'score_count', v_score_count);
end;
$$;

-- Remove development/public policies. Missing policies are ignored.
do $$
declare
  policy_record record;
begin
  for policy_record in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and policyname ilike '%dev%'
       or (schemaname = 'public' and policyname ilike '%public%')
       or (schemaname = 'public' and policyname ilike '%anon%')
  loop
    execute format('drop policy if exists %I on %I.%I', policy_record.policyname, policy_record.schemaname, policy_record.tablename);
  end loop;
end;
$$;

-- Core table RLS policies.
alter table public.schools enable row level security;
alter table public.programmes enable row level security;
alter table public.subjects enable row level security;
alter table public.classes enable row level security;
alter table public.class_subjects enable row level security;
alter table public.houses enable row level security;
alter table public.students enable row level security;
alter table public.student_subjects enable row level security;
alter table public.staff_users enable row level security;
alter table public.user_privileges enable row level security;
alter table public.documents enable row level security;
alter table public.assessment_modes enable row level security;
alter table public.assessments enable row level security;
alter table public.assessment_scores enable row level security;
alter table public.result_summaries enable row level security;
alter table public.super_admins enable row level security;

create policy "schools secure read" on public.schools for select to authenticated
using (public.is_super_admin() or public.can_manage_school(id) or id = public.current_school_id());
create policy "schools secure manage" on public.schools for all to authenticated
using (public.is_super_admin()) with check (public.is_super_admin());

create policy "super admins own read" on public.super_admins for select to authenticated
using (auth_user_id = auth.uid() or public.is_super_admin());
create policy "super admins manage" on public.super_admins for all to authenticated
using (public.is_super_admin()) with check (public.is_super_admin());

create policy "staff secure read" on public.staff_users for select to authenticated
using (auth_user_id = auth.uid() or public.can_manage_school(school_id));
create policy "staff secure manage" on public.staff_users for all to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

create policy "students secure read" on public.students for select to authenticated
using (auth_user_id = auth.uid() or public.can_manage_school(school_id) or public.has_page_privilege('studentperprogram', school_id) or public.has_page_privilege('cass', school_id) or public.has_page_privilege('downloadresult', school_id) or public.has_page_privilege('transcript', school_id));
create policy "students secure manage" on public.students for all to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

create policy "school setup read programmes" on public.programmes for select to authenticated
using (public.can_manage_school(school_id) or school_id = public.current_school_id());
create policy "school setup manage programmes" on public.programmes for all to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

create policy "school setup read subjects" on public.subjects for select to authenticated
using (public.can_manage_school(school_id) or school_id = public.current_school_id());
create policy "school setup manage subjects" on public.subjects for all to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

create policy "school setup read classes" on public.classes for select to authenticated
using (public.can_manage_school(school_id) or school_id = public.current_school_id());
create policy "school setup manage classes" on public.classes for all to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

create policy "class subjects read" on public.class_subjects for select to authenticated
using (exists (select 1 from public.classes c where c.id = class_id and (public.can_manage_school(c.school_id) or c.school_id = public.current_school_id())));
create policy "class subjects manage" on public.class_subjects for all to authenticated
using (exists (select 1 from public.classes c where c.id = class_id and public.can_manage_school(c.school_id)))
with check (exists (select 1 from public.classes c where c.id = class_id and public.can_manage_school(c.school_id)));

create policy "houses read" on public.houses for select to authenticated
using (public.can_manage_school(school_id) or school_id = public.current_school_id());
create policy "houses manage" on public.houses for all to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

create policy "student subjects read" on public.student_subjects for select to authenticated
using (exists (select 1 from public.students s where s.id = student_id and (s.auth_user_id = auth.uid() or public.can_manage_school(s.school_id) or s.school_id = public.current_school_id())));
create policy "student subjects manage" on public.student_subjects for all to authenticated
using (exists (select 1 from public.students s where s.id = student_id and public.can_manage_school(s.school_id)))
with check (exists (select 1 from public.students s where s.id = student_id and public.can_manage_school(s.school_id)));

create policy "privileges read" on public.user_privileges for select to authenticated
using (public.can_manage_school(school_id) or exists (select 1 from public.staff_users staff where staff.id = staff_user_id and staff.auth_user_id = auth.uid()));
create policy "privileges manage" on public.user_privileges for all to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

create policy "documents read" on public.documents for select to authenticated
using (public.can_manage_school(school_id) or exists (select 1 from public.staff_users staff where staff.id = staff_user_id and staff.auth_user_id = auth.uid()) or exists (select 1 from public.students student where student.id = student_id and student.auth_user_id = auth.uid()));
create policy "documents insert" on public.documents for insert to authenticated
with check (public.can_manage_school(school_id) or exists (select 1 from public.staff_users staff where staff.id = staff_user_id and staff.auth_user_id = auth.uid()) or exists (select 1 from public.students student where student.id = student_id and student.auth_user_id = auth.uid()));
create policy "documents update" on public.documents for update to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));
create policy "documents delete" on public.documents for delete to authenticated
using (public.can_manage_school(school_id));

create policy "assessment modes read" on public.assessment_modes for select to authenticated using (auth.role() = 'authenticated');

create policy "assessments read" on public.assessments for select to authenticated
using (public.can_manage_school(school_id) or school_id = public.current_school_id());
create policy "assessments manage" on public.assessments for all to authenticated
using (public.can_manage_school(school_id) or public.is_teaching_staff_for_school(school_id))
with check (public.can_manage_school(school_id) or public.is_teaching_staff_for_school(school_id));

create policy "scores read" on public.assessment_scores for select to authenticated
using (exists (select 1 from public.assessments a where a.id = assessment_id and (public.can_manage_school(a.school_id) or a.school_id = public.current_school_id())));
create policy "scores manage" on public.assessment_scores for all to authenticated
using (exists (select 1 from public.assessments a where a.id = assessment_id and (public.can_manage_school(a.school_id) or public.is_teaching_staff_for_school(a.school_id))))
with check (exists (select 1 from public.assessments a where a.id = assessment_id and (public.can_manage_school(a.school_id) or public.is_teaching_staff_for_school(a.school_id))));

create policy "result summaries read" on public.result_summaries for select to authenticated
using (public.can_manage_school(school_id) or exists (select 1 from public.students s where s.id = student_id and s.auth_user_id = auth.uid()));

-- Storage: remove broad public policies and restrict by first path folder = school code.
do $$
declare storage_policy record;
begin
  for storage_policy in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and (
        policyname ilike '%public%'
        or policyname ilike '%student%'
        or policyname ilike '%staff%'
        or policyname ilike '%scheme%'
      )
  loop
    execute format('drop policy if exists %I on storage.objects', storage_policy.policyname);
  end loop;
end;
$$;

update storage.buckets
set public = false
where id in ('student-passports', 'student-documents', 'staff-documents', 'scheme-of-work');

create policy "school file read"
on storage.objects for select to authenticated
using (
  bucket_id in ('student-passports', 'student-documents', 'staff-documents', 'scheme-of-work')
  and exists (
    select 1 from public.schools s
    where s.code = (storage.foldername(name))[1]
      and (public.can_manage_school(s.id) or s.id = public.current_school_id())
  )
);

create policy "school file insert"
on storage.objects for insert to authenticated
with check (
  bucket_id in ('student-passports', 'student-documents', 'staff-documents', 'scheme-of-work')
  and exists (
    select 1 from public.schools s
    where s.code = (storage.foldername(name))[1]
      and (public.can_manage_school(s.id) or s.id = public.current_school_id())
  )
);

create policy "school file update"
on storage.objects for update to authenticated
using (
  bucket_id in ('student-passports', 'student-documents', 'staff-documents', 'scheme-of-work')
  and exists (
    select 1 from public.schools s
    where s.code = (storage.foldername(name))[1]
      and public.can_manage_school(s.id)
  )
)
with check (
  bucket_id in ('student-passports', 'student-documents', 'staff-documents', 'scheme-of-work')
  and exists (
    select 1 from public.schools s
    where s.code = (storage.foldername(name))[1]
      and public.can_manage_school(s.id)
  )
);

create policy "school file delete"
on storage.objects for delete to authenticated
using (
  bucket_id in ('student-passports', 'student-documents', 'staff-documents', 'scheme-of-work')
  and exists (
    select 1 from public.schools s
    where s.code = (storage.foldername(name))[1]
      and public.can_manage_school(s.id)
  )
);

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated, service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
grant execute on all functions in schema public to authenticated, service_role;

-- Anonymous-safe identifier resolver for Supabase Auth login.
-- It returns only the Auth email for an existing linked account, never profile data.
create or replace function public.resolve_auth_login(
  p_identifier text,
  p_account_type text default null
)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  clean_identifier text := lower(btrim(coalesce(p_identifier, '')));
  resolved_email text;
begin
  if clean_identifier = '' then
    return null;
  end if;

  if p_account_type is null or lower(p_account_type) = 'superadmin' then
    select coalesce(u.email, sa.email)
    into resolved_email
    from public.super_admins sa
    left join auth.users u on u.id = sa.auth_user_id
    where lower(sa.username) = clean_identifier
       or lower(coalesce(sa.email, '')) = clean_identifier
    limit 1;
    if resolved_email is not null then return resolved_email; end if;
  end if;

  if p_account_type is null or lower(p_account_type) = 'staff' then
    select coalesce(u.email, staff.email)
    into resolved_email
    from public.staff_users staff
    left join auth.users u on u.id = staff.auth_user_id
    where lower(coalesce(staff.staff_id, '')) = clean_identifier
       or lower(coalesce(staff.username, '')) = clean_identifier
       or lower(coalesce(staff.email, '')) = clean_identifier
    limit 1;
    if resolved_email is not null then return resolved_email; end if;
  end if;

  if p_account_type is null or lower(p_account_type) = 'student' then
    select u.email
    into resolved_email
    from public.students student
    join auth.users u on u.id = student.auth_user_id
    where lower(coalesce(student.ass_ref_id, '')) = clean_identifier
    limit 1;
    if resolved_email is not null then return resolved_email; end if;
  end if;

  if position('@' in clean_identifier) > 1 then
    return clean_identifier;
  end if;

  return null;
end;
$$;

grant execute on function public.resolve_auth_login(text, text) to anon, authenticated, service_role;


-- Additional module policies for production after development policy removal.
alter table if exists public.departments enable row level security;
alter table if exists public.staff_subject_classes enable row level security;
alter table if exists public.scheme_of_work enable row level security;
alter table if exists public.scheme_of_work_history enable row level security;

create policy "departments read" on public.departments for select to authenticated
using (public.can_manage_school(school_id) or school_id = public.current_school_id());
create policy "departments manage" on public.departments for all to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

create policy "staff subject classes read" on public.staff_subject_classes for select to authenticated
using (
  public.can_manage_school(school_id)
  or exists (select 1 from public.staff_users staff where staff.id = staff_user_id and staff.auth_user_id = auth.uid())
);
create policy "staff subject classes manage" on public.staff_subject_classes for all to authenticated
using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

create policy "scheme read" on public.scheme_of_work for select to authenticated
using (
  public.can_manage_school(school_id)
  or public.is_teaching_staff_for_school(school_id)
  or exists (select 1 from public.staff_users staff where staff.id = teacher_id and staff.auth_user_id = auth.uid())
);
create policy "scheme insert" on public.scheme_of_work for insert to authenticated
with check (
  public.can_manage_school(school_id)
  or exists (
    select 1 from public.staff_users staff
    where staff.id = teacher_id
      and staff.auth_user_id = auth.uid()
      and staff.school_id = school_id
      and staff.category = 'Teaching Staff'
      and staff.status = 'Active'
  )
);
create policy "scheme update" on public.scheme_of_work for update to authenticated
using (public.can_manage_school(school_id) or public.is_teaching_staff_for_school(school_id))
with check (public.can_manage_school(school_id) or public.is_teaching_staff_for_school(school_id));
create policy "scheme delete" on public.scheme_of_work for delete to authenticated
using (public.can_manage_school(school_id));

create policy "scheme history read" on public.scheme_of_work_history for select to authenticated
using (public.can_manage_school(school_id) or public.is_teaching_staff_for_school(school_id));
create policy "scheme history insert" on public.scheme_of_work_history for insert to authenticated
with check (public.can_manage_school(school_id) or public.is_teaching_staff_for_school(school_id));

