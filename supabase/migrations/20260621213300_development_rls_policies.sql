-- Development RLS policies for AXIOMBYTE SMS.
-- These allow anon/authenticated browser access while building.
-- Tighten before production.

alter table schools enable row level security;
alter table programmes enable row level security;
alter table subjects enable row level security;
alter table classes enable row level security;
alter table class_subjects enable row level security;
alter table houses enable row level security;
alter table students enable row level security;
alter table student_subjects enable row level security;
alter table staff_users enable row level security;
alter table user_privileges enable row level security;
alter table documents enable row level security;
alter table assessment_modes enable row level security;
alter table assessments enable row level security;
alter table assessment_scores enable row level security;

create policy "dev access schools" on schools for all using (true) with check (true);
create policy "dev access programmes" on programmes for all using (true) with check (true);
create policy "dev access subjects" on subjects for all using (true) with check (true);
create policy "dev access classes" on classes for all using (true) with check (true);
create policy "dev access class_subjects" on class_subjects for all using (true) with check (true);
create policy "dev access houses" on houses for all using (true) with check (true);
create policy "dev access students" on students for all using (true) with check (true);
create policy "dev access student_subjects" on student_subjects for all using (true) with check (true);
create policy "dev access staff_users" on staff_users for all using (true) with check (true);
create policy "dev access user_privileges" on user_privileges for all using (true) with check (true);
create policy "dev access documents" on documents for all using (true) with check (true);
create policy "dev access assessment_modes" on assessment_modes for all using (true) with check (true);
create policy "dev access assessments" on assessments for all using (true) with check (true);
create policy "dev access assessment_scores" on assessment_scores for all using (true) with check (true);
