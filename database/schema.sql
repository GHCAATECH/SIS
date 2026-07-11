-- AXIOMBYTE SMS database schema
-- Target: PostgreSQL / Supabase compatible

create extension if not exists pgcrypto;

create table if not exists schools (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists programmes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  name text not null,
  code text,
  department text,
  created_at timestamptz not null default now(),
  unique (school_id, name)
);

create table if not exists subjects (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  programme_id uuid references programmes(id) on delete cascade,
  name text not null,
  code text,
  subject_type text not null check (subject_type in ('Core', 'Elective')),
  applies_to_all_programmes boolean not null default false,
  created_at timestamptz not null default now(),
  unique (school_id, programme_id, name)
);

create table if not exists classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  programme_id uuid not null references programmes(id) on delete restrict,
  name text not null,
  year_level text,
  class_teacher text,
  created_at timestamptz not null default now(),
  unique (school_id, name)
);

create table if not exists class_subjects (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references classes(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete restrict,
  option_no integer not null check (option_no between 1 and 12),
  created_at timestamptz not null default now(),
  unique (class_id, option_no),
  unique (class_id, subject_id)
);

create table if not exists houses (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  name text not null,
  residential_status text not null check (residential_status in ('Boarding', 'Day')),
  patron text,
  capacity integer,
  created_at timestamptz not null default now(),
  unique (school_id, name)
);

create table if not exists students (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  class_id uuid references classes(id) on delete set null,
  house_id uuid references houses(id) on delete set null,
  ass_ref_id text not null unique,
  surname text not null,
  first_name text not null,
  other_names text,
  ghana_card_number text,
  gender text not null check (gender in ('Male', 'Female')),
  disability_status text not null default 'No' check (disability_status in ('No', 'Yes')),
  date_of_birth date not null,
  guardian_name text,
  relationship text,
  phone_number text,
  profession text,
  residential_address text,
  residential_status text check (residential_status in ('Boarding', 'Day')),
  year_admitted integer,
  passport_url text,
  status text not null default 'Active' check (status in ('Active', 'Transferred', 'Dropped', 'Repeated')),
  inserted_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists student_subjects (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete restrict,
  option_no integer check (option_no between 1 and 12),
  status text not null default 'Active' check (status in ('Active', 'Dropped', 'Repeated')),
  created_at timestamptz not null default now(),
  unique (student_id, subject_id)
);

create table if not exists staff_users (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  staff_name text,
  staff_id text,
  gender text,
  date_of_birth date,
  nationality text,
  marital_status text,
  profile_photo text,
  ghana_card_number text,
  social_security_number text,
  ntc_number text,
  full_name text not null,
  username text not null unique,
  email text not null unique,
  phone text,
  alternate_phone text,
  residential_address text,
  digital_address text,
  emergency_contact_name text,
  emergency_contact_phone text,
  emergency_contact_relationship text,
  category text not null check (category in ('School Administrator', 'Teaching Staff', 'Non-Teaching Staff')),
  role text not null,
  first_appointment_date date,
  date_posted_to_station date,
  rank text,
  date_placed_on_rank date,
  employment_status text,
  trained_status text,
  position_responsibility text,
  department text,
  house_assigned text,
  professional_qualification text,
  academic_qualification text,
  bank_name text,
  branch_name text,
  account_number text,
  account_name text,
  account_password text,
  must_change_password boolean not null default true,
  status text not null default 'Active' check (status in ('Active', 'Suspended')),
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists user_privileges (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  staff_user_id uuid not null references staff_users(id) on delete cascade,
  page_key text not null,
  created_at timestamptz not null default now(),
  unique (school_id, staff_user_id, page_key)
);

create table if not exists documents (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  owner_type text not null check (owner_type in ('student', 'staff')),
  student_id uuid references students(id) on delete cascade,
  staff_user_id uuid references staff_users(id) on delete cascade,
  title text not null,
  file_name text not null,
  file_type text,
  file_size bigint,
  file_url text,
  uploaded_at timestamptz not null default now(),
  check (
    (owner_type = 'student' and student_id is not null and staff_user_id is null)
    or
    (owner_type = 'staff' and staff_user_id is not null and student_id is null)
  )
);

create table if not exists assessment_modes (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  display_order integer not null unique
);

create table if not exists assessments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  class_id uuid not null references classes(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete restrict,
  assessment_mode_id uuid not null references assessment_modes(id) on delete restrict,
  year_level text not null,
  semester text not null,
  overall_score numeric(5,2) check (overall_score >= 0 and overall_score <= 100),
  status text not null default 'Draft' check (status in ('Draft', 'Submitted')),
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  unique (class_id, subject_id, assessment_mode_id, semester, year_level)
);

create table if not exists assessment_scores (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references assessments(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  score numeric(5,2) check (score >= 0 and score <= 100),
  grade text,
  remark text,
  updated_at timestamptz not null default now(),
  unique (assessment_id, student_id)
);

create index if not exists idx_students_school_class on students(school_id, class_id);
create index if not exists idx_students_ass_ref on students(ass_ref_id);
create index if not exists idx_user_privileges_staff on user_privileges(staff_user_id);
create index if not exists idx_documents_student on documents(student_id);
create index if not exists idx_documents_staff on documents(staff_user_id);
create index if not exists idx_scores_assessment on assessment_scores(assessment_id);

insert into assessment_modes (display_order, name) values
  (1, 'Individual Class Assessments (e.g., Classwork, Quizzes, Homework)'),
  (2, 'Mid-Sem'),
  (3, 'Practical or Portfolio or Performance Assessment (Individual)'),
  (4, 'Group Projects, Research, or Case Studies, Practical/Lab work, Workshops, Performances, Presentations (Out of Class)'),
  (5, 'Supervised individual Termly')
on conflict (display_order) do update set name = excluded.name;
