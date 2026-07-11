-- Allow student records to be marked as Repeated from Manage Students.

alter table students
drop constraint if exists students_status_check;

alter table students
add constraint students_status_check
check (status in ('Active', 'Transferred', 'Dropped', 'Repeated'));
