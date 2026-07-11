-- Grants for browser access using the Supabase anon key.
-- This is permissive for local prototype use. Tighten with RLS before production.

grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;

alter default privileges in schema public
grant select, insert, update, delete on tables to anon, authenticated, service_role;

alter default privileges in schema public
grant usage, select on sequences to anon, authenticated, service_role;

alter default privileges in schema public
grant execute on functions to anon, authenticated, service_role;

