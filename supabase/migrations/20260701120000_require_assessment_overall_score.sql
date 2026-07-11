-- Backfill legacy assessments before requiring an overall score.
update public.assessments
set overall_score = 100
where overall_score is null or overall_score <= 0;

alter table public.assessments
  alter column overall_score set not null;

alter table public.assessments
  drop constraint if exists assessments_overall_score_check;

alter table public.assessments
  add constraint assessments_overall_score_check
  check (overall_score > 0 and overall_score <= 100);
