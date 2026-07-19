-- Permit the same house name once for Male and once for Female.
-- A duplicate with the same school, house name, and gender remains blocked.
alter table public.houses
  drop constraint if exists houses_school_id_name_key;

alter table public.houses
  drop constraint if exists houses_school_id_name_gender_key;

alter table public.houses
  add constraint houses_school_id_name_gender_key
  unique (school_id, name, gender);