-- Full staff profile fields for AXIOMBYTE SMS Add User page.
-- Run this in Supabase SQL Editor to save the expanded staff registration form.

alter table staff_users
add column if not exists staff_name text,
add column if not exists staff_id text,
add column if not exists gender text,
add column if not exists date_of_birth date,
add column if not exists nationality text,
add column if not exists marital_status text,
add column if not exists profile_photo text,
add column if not exists ghana_card_number text,
add column if not exists social_security_number text,
add column if not exists ntc_number text,
add column if not exists alternate_phone text,
add column if not exists residential_address text,
add column if not exists digital_address text,
add column if not exists emergency_contact_name text,
add column if not exists emergency_contact_phone text,
add column if not exists emergency_contact_relationship text,
add column if not exists first_appointment_date date,
add column if not exists date_posted_to_station date,
add column if not exists rank text,
add column if not exists date_placed_on_rank date,
add column if not exists employment_status text,
add column if not exists trained_status text,
add column if not exists position_responsibility text,
add column if not exists department text,
add column if not exists house_assigned text,
add column if not exists professional_qualification text,
add column if not exists academic_qualification text,
add column if not exists bank_name text,
add column if not exists branch_name text,
add column if not exists account_number text,
add column if not exists account_name text;

create index if not exists idx_staff_users_staff_id on staff_users(staff_id);
