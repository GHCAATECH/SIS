-- Keep department names synchronized when an administrator edits a department.

create or replace function public.sync_department_name_to_links()
returns trigger
language plpgsql
as $$
begin
  if new.name is distinct from old.name then
    update public.programmes
    set department = new.name
    where school_id = new.school_id
      and department_id = new.id;

    update public.staff_users
    set department = new.name
    where school_id = new.school_id
      and lower(btrim(coalesce(department, ''))) = lower(btrim(old.name));

    update public.scheme_of_work
    set department = new.name
    where school_id = new.school_id
      and lower(btrim(department)) = lower(btrim(old.name))
      and status in ('Pending HOD', 'Pending Head Academic');
  end if;

  return new;
end;
$$;

drop trigger if exists sync_department_name_to_links
on public.departments;

create trigger sync_department_name_to_links
after update of name on public.departments
for each row
execute function public.sync_department_name_to_links();
