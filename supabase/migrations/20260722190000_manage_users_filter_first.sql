-- Filter-first Manage Users loading for school administrators.

create extension if not exists pg_trgm;

create index if not exists idx_staff_users_school_category_name
  on public.staff_users (school_id, category, lower(coalesce(full_name, staff_name, '')));

create index if not exists idx_staff_users_school_role
  on public.staff_users (school_id, role);

create index if not exists idx_staff_users_school_status_name
  on public.staff_users (school_id, status, lower(coalesce(full_name, staff_name, '')));

create index if not exists idx_staff_users_school_phone
  on public.staff_users (school_id, phone);

create index if not exists idx_staff_users_full_name_trgm
  on public.staff_users using gin (full_name gin_trgm_ops);

create index if not exists idx_staff_users_staff_name_trgm
  on public.staff_users using gin (staff_name gin_trgm_ops);

create index if not exists idx_staff_users_staff_id_trgm
  on public.staff_users using gin (staff_id gin_trgm_ops);

create index if not exists idx_staff_users_email_trgm
  on public.staff_users using gin (email gin_trgm_ops);

create or replace function public.secure_list_staff_users(
  p_school_id uuid,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rows jsonb;
  v_limit integer := least(greatest(coalesce(nullif(p_filters->>'limit', '')::integer, 100), 1), 500);
  v_page integer := greatest(coalesce(nullif(p_filters->>'page', '')::integer, 1), 1);
  v_offset integer := 0;
  v_search text := nullif(btrim(coalesce(p_filters->>'search', '')), '');
  v_category text := nullif(btrim(coalesce(p_filters->>'category', '')), '');
  v_role text := nullif(btrim(coalesce(p_filters->>'role', '')), '');
  v_status text := nullif(btrim(coalesce(p_filters->>'status', '')), '');
begin
  if p_school_id is null then
    raise exception 'School context is required.';
  end if;

  v_offset := (v_page - 1) * v_limit;

  select coalesce(jsonb_agg(to_jsonb(staff_row) - 'sort_name' order by sort_name, staff_id), '[]'::jsonb)
    into rows
  from (
    select
      staff.*,
      lower(coalesce(nullif(staff.full_name, ''), nullif(staff.staff_name, ''), staff.staff_id, staff.email, '')) as sort_name
    from public.staff_users staff
    where staff.school_id = p_school_id
      and (v_category is null or staff.category = v_category)
      and (v_role is null or staff.role = v_role)
      and (v_status is null or staff.status = v_status)
      and (
        v_search is null
        or staff.full_name ilike '%' || v_search || '%'
        or staff.staff_name ilike '%' || v_search || '%'
        or staff.staff_id ilike '%' || v_search || '%'
        or staff.email ilike '%' || v_search || '%'
        or staff.phone ilike '%' || v_search || '%'
        or staff.username ilike '%' || v_search || '%'
      )
    order by lower(coalesce(nullif(staff.full_name, ''), nullif(staff.staff_name, ''), staff.staff_id, staff.email, '')), staff.staff_id
    offset v_offset
    limit v_limit
  ) staff_row;

  return rows;
end;
$$;

grant execute on function public.secure_list_staff_users(uuid, jsonb)
  to anon, authenticated, service_role;