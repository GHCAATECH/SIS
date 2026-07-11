-- Automatic best-three Core/Elective totals and class positions.

create or replace function public.axiom_current_academic_year()
returns text
language sql
stable
as $$
  select case
    when extract(month from timezone('Africa/Accra', now())) >= 9
      then extract(year from timezone('Africa/Accra', now()))::int::text || '/' ||
           (extract(year from timezone('Africa/Accra', now()))::int + 1)::text
    else (extract(year from timezone('Africa/Accra', now()))::int - 1)::text || '/' ||
         extract(year from timezone('Africa/Accra', now()))::int::text
  end;
$$;

alter table public.assessment_modes
  add column if not exists weight_percent numeric(5,2);

update public.assessment_modes
set weight_percent = case display_order
  when 1 then 15
  when 2 then 15
  when 3 then 10
  when 4 then 20
  when 5 then 40
  else coalesce(weight_percent, 0)
end;

alter table public.assessment_modes
  alter column weight_percent set default 0,
  alter column weight_percent set not null;

alter table public.assessment_modes
  drop constraint if exists assessment_modes_weight_percent_check;
alter table public.assessment_modes
  add constraint assessment_modes_weight_percent_check
  check (weight_percent >= 0 and weight_percent <= 100);

alter table public.assessments
  add column if not exists academic_year text;

update public.assessments
set academic_year = public.axiom_current_academic_year()
where academic_year is null or btrim(academic_year) = '';

alter table public.assessments
  alter column academic_year set default public.axiom_current_academic_year(),
  alter column academic_year set not null;

-- Replace the old uniqueness rule so a new academic year cannot overwrite history.
do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select c.conname
    from pg_constraint c
    where c.conrelid = 'public.assessments'::regclass
      and c.contype = 'u'
      and pg_get_constraintdef(c.oid) ilike '%class_id%'
      and pg_get_constraintdef(c.oid) ilike '%subject_id%'
      and pg_get_constraintdef(c.oid) ilike '%assessment_mode_id%'
      and pg_get_constraintdef(c.oid) not ilike '%academic_year%'
  loop
    execute format('alter table public.assessments drop constraint %I', constraint_name);
  end loop;
end;
$$;

create unique index if not exists assessments_academic_scope_uidx
on public.assessments (
  school_id, academic_year, semester, year_level,
  class_id, subject_id, assessment_mode_id
);

create table if not exists public.result_summaries (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  academic_year text not null,
  term text not null,
  programme_id uuid not null references public.programmes(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  best_three_core_total numeric(7,2) not null default 0,
  best_three_elective_total numeric(7,2) not null default 0,
  overall_total numeric(7,2) not null default 0,
  class_position integer not null default 1,
  class_size integer not null default 1,
  calculated_at timestamptz not null default now(),
  unique (school_id, academic_year, term, programme_id, class_id, student_id)
);

create index if not exists idx_result_summaries_student
on public.result_summaries (school_id, student_id, academic_year, term);

create index if not exists idx_result_summaries_class
on public.result_summaries (school_id, academic_year, term, programme_id, class_id, class_position);

alter table public.result_summaries enable row level security;

drop policy if exists "Allow public read result summaries" on public.result_summaries;
create policy "Allow public read result summaries"
on public.result_summaries for select
using (true);

revoke insert, update, delete on public.result_summaries from anon, authenticated;
grant select on public.result_summaries to anon, authenticated;

create or replace function public.recalculate_class_positions(
  p_school_id uuid,
  p_academic_year text,
  p_term text,
  p_programme_id uuid,
  p_class_id uuid
)
returns setof public.result_summaries
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.classes c
    where c.id = p_class_id
      and c.school_id = p_school_id
      and c.programme_id = p_programme_id
  ) then
    raise exception 'The selected class does not belong to the selected school and programme.';
  end if;

  with eligible_students as (
    select s.id as student_id
    from public.students s
    where s.school_id = p_school_id
      and s.class_id = p_class_id
      and coalesce(s.status, 'Active') not in ('Transferred', 'Dropped', 'Completed')
  ),
  subject_totals as (
    select
      sc.student_id,
      a.subject_id,
      case when lower(coalesce(sub.subject_type, 'Elective')) = 'core' then true else false end as is_core,
      round(sum(
        case
          when sc.score is null then 0
          when a.overall_score is not null and a.overall_score > 0
            then least((sc.score / a.overall_score) * am.weight_percent, am.weight_percent)
          else (sc.score * am.weight_percent / 100.0)
        end
      ), 2) as subject_total
    from public.assessment_scores sc
    join public.assessments a on a.id = sc.assessment_id
    join public.assessment_modes am on am.id = a.assessment_mode_id
    join public.subjects sub on sub.id = a.subject_id
    join eligible_students es on es.student_id = sc.student_id
    where a.school_id = p_school_id
      and a.class_id = p_class_id
      and a.academic_year = p_academic_year
      and a.semester = p_term
    group by sc.student_id, a.subject_id,
      case when lower(coalesce(sub.subject_type, 'Elective')) = 'core' then true else false end
  ),
  ranked_subjects as (
    select
      st.*,
      row_number() over (
        partition by st.student_id, st.is_core
        order by st.subject_total desc, st.subject_id
      ) as subject_rank
    from subject_totals st
  ),
  student_totals as (
    select
      es.student_id,
      round(coalesce(sum(rs.subject_total) filter (where rs.is_core and rs.subject_rank <= 3), 0), 2) as core_total,
      round(coalesce(sum(rs.subject_total) filter (where not rs.is_core and rs.subject_rank <= 3), 0), 2) as elective_total
    from eligible_students es
    left join ranked_subjects rs on rs.student_id = es.student_id
    group by es.student_id
  ),
  positioned as (
    select
      st.student_id,
      st.core_total,
      st.elective_total,
      round(st.core_total + st.elective_total, 2) as overall_total,
      (rank() over (order by (st.core_total + st.elective_total) desc))::integer as class_position,
      (count(*) over ())::integer as class_size
    from student_totals st
  )
  insert into public.result_summaries as summary (
    school_id, academic_year, term, programme_id, class_id, student_id,
    best_three_core_total, best_three_elective_total, overall_total,
    class_position, class_size, calculated_at
  )
  select
    p_school_id, p_academic_year, p_term, p_programme_id, p_class_id, positioned.student_id,
    positioned.core_total, positioned.elective_total, positioned.overall_total,
    positioned.class_position, positioned.class_size, now()
  from positioned
  on conflict (school_id, academic_year, term, programme_id, class_id, student_id)
  do update set
    best_three_core_total = excluded.best_three_core_total,
    best_three_elective_total = excluded.best_three_elective_total,
    overall_total = excluded.overall_total,
    class_position = excluded.class_position,
    class_size = excluded.class_size,
    calculated_at = excluded.calculated_at;

  delete from public.result_summaries summary
  where summary.school_id = p_school_id
    and summary.academic_year = p_academic_year
    and summary.term = p_term
    and summary.programme_id = p_programme_id
    and summary.class_id = p_class_id
    and not exists (
      select 1
      from public.students s
      where s.id = summary.student_id
        and s.school_id = p_school_id
        and s.class_id = p_class_id
        and coalesce(s.status, 'Active') not in ('Transferred', 'Dropped', 'Completed')
    );

  return query
  select summary.*
  from public.result_summaries summary
  where summary.school_id = p_school_id
    and summary.academic_year = p_academic_year
    and summary.term = p_term
    and summary.programme_id = p_programme_id
    and summary.class_id = p_class_id
  order by summary.class_position, summary.student_id;
end;
$$;

grant execute on function public.recalculate_class_positions(uuid, text, text, uuid, uuid)
to anon, authenticated;

create or replace function public.recalculate_positions_for_assessment(p_assessment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  context_row record;
begin
  select a.school_id, a.academic_year, a.semester, c.programme_id, a.class_id
  into context_row
  from public.assessments a
  join public.classes c on c.id = a.class_id
  where a.id = p_assessment_id;

  if found then
    perform public.recalculate_class_positions(
      context_row.school_id,
      context_row.academic_year,
      context_row.semester,
      context_row.programme_id,
      context_row.class_id
    );
  end if;
end;
$$;

create or replace function public.trg_recalculate_positions_score_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare context_row record;
begin
  for context_row in select distinct assessment_id from new_scores loop
    perform public.recalculate_positions_for_assessment(context_row.assessment_id);
  end loop;
  return null;
end;
$$;

create or replace function public.trg_recalculate_positions_score_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare context_row record;
begin
  for context_row in
    select assessment_id from new_scores
    union
    select assessment_id from old_scores
  loop
    perform public.recalculate_positions_for_assessment(context_row.assessment_id);
  end loop;
  return null;
end;
$$;

create or replace function public.trg_recalculate_positions_score_delete()
returns trigger language plpgsql security definer set search_path = public as $$
declare context_row record;
begin
  for context_row in select distinct assessment_id from old_scores loop
    perform public.recalculate_positions_for_assessment(context_row.assessment_id);
  end loop;
  return null;
end;
$$;

drop trigger if exists assessment_scores_position_insert on public.assessment_scores;
create trigger assessment_scores_position_insert
after insert on public.assessment_scores
referencing new table as new_scores
for each statement execute function public.trg_recalculate_positions_score_insert();

drop trigger if exists assessment_scores_position_update on public.assessment_scores;
create trigger assessment_scores_position_update
after update on public.assessment_scores
referencing old table as old_scores new table as new_scores
for each statement execute function public.trg_recalculate_positions_score_update();

drop trigger if exists assessment_scores_position_delete on public.assessment_scores;
create trigger assessment_scores_position_delete
after delete on public.assessment_scores
referencing old table as old_scores
for each statement execute function public.trg_recalculate_positions_score_delete();

create or replace function public.trg_recalculate_positions_assessment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.recalculate_positions_for_assessment(new.id);
  return new;
end;
$$;

drop trigger if exists assessments_position_recalculate on public.assessments;
create trigger assessments_position_recalculate
after insert or update of status, overall_score, academic_year, semester, class_id
on public.assessments
for each row execute function public.trg_recalculate_positions_assessment();

create or replace function public.trg_recalculate_positions_subject_type()
returns trigger language plpgsql security definer set search_path = public as $$
declare context_row record;
begin
  for context_row in
    select distinct a.school_id, a.academic_year, a.semester, c.programme_id, a.class_id
    from public.assessments a
    join public.classes c on c.id = a.class_id
    where a.subject_id = new.id
  loop
    perform public.recalculate_class_positions(
      context_row.school_id,
      context_row.academic_year,
      context_row.semester,
      context_row.programme_id,
      context_row.class_id
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists subjects_position_recalculate on public.subjects;
create trigger subjects_position_recalculate
after update of subject_type on public.subjects
for each row
when (old.subject_type is distinct from new.subject_type)
execute function public.trg_recalculate_positions_subject_type();
