alter table public.assessments
  add column if not exists inserted_by text;

update public.assessments
set inserted_by = 'System'
where inserted_by is null or btrim(inserted_by) = '';
