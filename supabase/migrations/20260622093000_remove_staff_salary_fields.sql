-- Remove salary fields from AXIOMBYTE SMS staff user registration.
-- Run this in Supabase SQL Editor after removing the fields from Add User.

alter table staff_users
drop column if exists salary_level,
drop column if exists salary_scale,
drop column if exists salary_amount;
