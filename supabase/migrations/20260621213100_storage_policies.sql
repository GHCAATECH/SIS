-- Storage policies for AXIOMBYTE SMS browser uploads
-- For production, tighten these to authenticated users and school-specific folders.

update storage.buckets
set public = true
where id = 'student-passports';

create policy "Allow public read student passports"
on storage.objects for select
using (bucket_id = 'student-passports');

create policy "Allow public upload student passports"
on storage.objects for insert
with check (bucket_id = 'student-passports');

create policy "Allow public update student passports"
on storage.objects for update
using (bucket_id = 'student-passports')
with check (bucket_id = 'student-passports');

create policy "Allow public delete student passports"
on storage.objects for delete
using (bucket_id = 'student-passports');

create policy "Allow public read student documents"
on storage.objects for select
using (bucket_id = 'student-documents');

create policy "Allow public upload student documents"
on storage.objects for insert
with check (bucket_id = 'student-documents');

create policy "Allow public update student documents"
on storage.objects for update
using (bucket_id = 'student-documents')
with check (bucket_id = 'student-documents');

create policy "Allow public delete student documents"
on storage.objects for delete
using (bucket_id = 'student-documents');

create policy "Allow public read staff documents"
on storage.objects for select
using (bucket_id = 'staff-documents');

create policy "Allow public upload staff documents"
on storage.objects for insert
with check (bucket_id = 'staff-documents');

create policy "Allow public update staff documents"
on storage.objects for update
using (bucket_id = 'staff-documents')
with check (bucket_id = 'staff-documents');

create policy "Allow public delete staff documents"
on storage.objects for delete
using (bucket_id = 'staff-documents');
