-- AXIOMBYTE SMS seed data
-- Run after database/schema.sql

insert into schools (code, name)
values ('0021101', 'ASUOM SENIOR HIGH SCHOOL')
on conflict (code) do update set name = excluded.name;

with school as (
  select id from schools where code = '0021101'
)
insert into programmes (school_id, name, code, department)
select school.id, item.name, item.code, item.department
from school,
(values
  ('General Science', 'SCI', 'Science Department'),
  ('General Arts', 'ART', 'Arts Department'),
  ('Business', 'BUS', 'Business Department'),
  ('Visual Arts', 'VA', 'Visual Arts Department'),
  ('Home Economics', 'HE', 'Home Economics Department'),
  ('Agricultural Science', 'AGR', 'Agriculture Department')
) as item(name, code, department)
on conflict (school_id, name) do update
set code = excluded.code, department = excluded.department;

with school as (
  select id from schools where code = '0021101'
),
programmes_map as (
  select id, name from programmes where school_id = (select id from school)
)
insert into subjects (school_id, programme_id, name, code, subject_type, applies_to_all_programmes)
select
  (select id from school),
  p.id,
  item.name,
  item.code,
  item.subject_type,
  item.applies_to_all
from (values
  ('All Programmes', 'Core Mathematics', 'MATH', 'Core', true),
  ('All Programmes', 'English Language', 'ENG', 'Core', true),
  ('All Programmes', 'Integrated Science', 'SCI', 'Core', true),
  ('All Programmes', 'Social Studies', 'SOC', 'Core', true),
  ('General Science', 'Additional Mathematics', '403', 'Elective', false),
  ('General Science', 'Biology', '535', 'Elective', false),
  ('General Science', 'Chemistry', '536', 'Elective', false),
  ('General Science', 'Physics', '539', 'Elective', false),
  ('General Science', 'Physical Education & Health', '542', 'Elective', false),
  ('General Science', 'Computing', '614', 'Elective', false),
  ('General Science', 'Economics', 'ECON', 'Elective', false),
  ('General Science', 'Geography', 'GEO', 'Elective', false),
  ('Business', 'Financial Accounting', 'FA', 'Elective', false),
  ('Business', 'Cost Accounting', 'CA', 'Elective', false),
  ('Business', 'Business Management', 'BM', 'Elective', false)
) as item(programme_name, name, code, subject_type, applies_to_all)
left join programmes_map p on p.name = item.programme_name
on conflict (school_id, programme_id, name) do update
set code = excluded.code,
    subject_type = excluded.subject_type,
    applies_to_all_programmes = excluded.applies_to_all_programmes;

with school as (
  select id from schools where code = '0021101'
),
science as (
  select id from programmes where school_id = (select id from school) and name = 'General Science'
),
business as (
  select id from programmes where school_id = (select id from school) and name = 'Business'
)
insert into classes (school_id, programme_id, name, year_level, class_teacher)
select (select id from school), (select id from science), 'SCI_24', 'Year 2', 'Mr. K. Boateng'
union all
select (select id from school), (select id from business), 'BUS_24', 'Year 2', 'Ms. G. Asante'
on conflict (school_id, name) do update
set programme_id = excluded.programme_id,
    year_level = excluded.year_level,
    class_teacher = excluded.class_teacher;

with school as (
  select id from schools where code = '0021101'
)
insert into houses (school_id, name, residential_status, patron, capacity)
select school.id, item.name, item.residential_status, item.patron, item.capacity
from school,
(values
  ('Unity House', 'Boarding', 'Mr. K. Boateng', 120),
  ('Liberty House', 'Boarding', 'Mr. S. Adjei', 110),
  ('Day Students', 'Day', 'Mrs. A. Owusu', 300)
) as item(name, residential_status, patron, capacity)
on conflict (school_id, name) do update
set residential_status = excluded.residential_status,
    patron = excluded.patron,
    capacity = excluded.capacity;

with school as (
  select id from schools where code = '0021101'
),
sci as (
  select id from classes where school_id = (select id from school) and name = 'SCI_24'
),
house as (
  select id from houses where school_id = (select id from school) and name = 'Unity House'
)
insert into students (
  school_id, class_id, house_id, ass_ref_id, surname, first_name, other_names,
  gender, disability_status, date_of_birth, guardian_name, relationship,
  phone_number, profession, residential_address, residential_status,
  year_admitted, status, inserted_by
)
select (select id from school), (select id from sci), (select id from house), item.ass_ref_id,
  item.surname, item.first_name, item.other_names, item.gender, 'No', item.date_of_birth::date,
  item.guardian_name, item.relationship, item.phone_number, item.profession,
  'ASUOM', 'Boarding', 2025, 'Active', 'Admin'
from (values
  ('2400211013DB', 'TETTEY', 'FOSTER', 'ADAMNOR', 'Male', '2008-03-22', 'DANIEL TETTEY', 'Father', '0240000001', 'Farmer'),
  ('2400211013DC', 'ADDIN', 'DAVID', null, 'Male', '2007-01-30', 'AMA ADDIN', 'Mother', '0240000002', 'Trader'),
  ('2400211013DD', 'ADJEIKWEI', 'STANLEY', 'ADJEI', 'Male', '2009-04-01', 'KOFI ADJEI', 'Guardian', '0240000003', 'Teacher'),
  ('2400211013DE', 'ADUKO', 'GILBERT', null, 'Male', '2008-07-12', 'MARY ADUKO', 'Mother', '0240000004', 'Nurse'),
  ('2400211013DF', 'TEINOKIE', 'RUBY', 'AGBOZO', 'Female', '2009-04-25', 'EVELYN AGBOZO', 'Mother', '0240000005', 'Trader')
) as item(ass_ref_id, surname, first_name, other_names, gender, date_of_birth, guardian_name, relationship, phone_number, profession)
on conflict (ass_ref_id) do update
set surname = excluded.surname,
    first_name = excluded.first_name,
    other_names = excluded.other_names,
    class_id = excluded.class_id,
    house_id = excluded.house_id,
    updated_at = now();

