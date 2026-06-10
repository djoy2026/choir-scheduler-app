-- Add foundational team management metadata.
--
-- Teams are never deleted by the app. Admins can deactivate teams to preserve
-- history while hiding them from volunteer scheduling views.

alter table public.teams
add column if not exists display_order integer;

alter table public.teams
add column if not exists is_active boolean;

update public.teams
set display_order = case name
  when 'Nursery' then 10
  when 'Kindies' then 20
  when '2 Year Olds' then 30
  when '3 Year Olds' then 40
  when '4 Year Olds' then 50
  when '1st Grade' then 60
  when '2nd Grade' then 70
  when '3rd Grade' then 80
  when '4th Grade' then 90
  when '5th Grade' then 100
  when 'All Kids Choir Volunteers' then 200
  when 'All Main Choir Volunteers' then 300
  else coalesce(display_order, 999)
end
where display_order is null
   or name in (
    'Nursery',
    'Kindies',
    '2 Year Olds',
    '3 Year Olds',
    '4 Year Olds',
    '1st Grade',
    '2nd Grade',
    '3rd Grade',
    '4th Grade',
    '5th Grade',
    'All Kids Choir Volunteers',
    'All Main Choir Volunteers'
   );

update public.teams
set is_active = true
where is_active is null;

alter table public.teams
alter column display_order set default 999;

alter table public.teams
alter column display_order set not null;

alter table public.teams
alter column is_active set default true;

alter table public.teams
alter column is_active set not null;

create index if not exists idx_teams_ministry_active_order
on public.teams (ministry_id, is_active, display_order, name);

comment on column public.teams.display_order is
  'Admin-managed ordering value for displaying teams within a ministry.';

comment on column public.teams.is_active is
  'When false, the team is hidden from volunteer scheduling views while history is preserved.';
