-- Store the gender served by each house. Existing houses remain editable so
-- administrators can set the correct Male or Female value after this migration.
alter table public.houses
  add column if not exists gender text;

alter table public.houses
  drop constraint if exists houses_gender_check;

alter table public.houses
  add constraint houses_gender_check
  check (gender is null or gender in ('Male', 'Female'));
