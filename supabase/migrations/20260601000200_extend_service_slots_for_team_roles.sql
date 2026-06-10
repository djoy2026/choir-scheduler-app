-- Extend service_slots so generated slots can be traced back to team_roles.
-- Existing slot behavior is preserved: slot_name, role_name, slot_status,
-- assigned_user_id, and color_code remain the fields used by the current app.

alter table public.service_slots
add column if not exists team_role_id uuid null
references public.team_roles(id) on delete set null;

alter table public.service_slots
add column if not exists role_instance_number integer null;

alter table public.service_slots
drop constraint if exists service_slots_role_instance_number_positive;

alter table public.service_slots
add constraint service_slots_role_instance_number_positive
check (role_instance_number is null or role_instance_number > 0)
not valid;

create index if not exists idx_service_slots_team_role_id
on public.service_slots (team_role_id);

create index if not exists idx_service_slots_service_instance_id
on public.service_slots (service_instance_id);

create index if not exists idx_service_slots_assigned_user_id
on public.service_slots (assigned_user_id);

create index if not exists idx_service_slots_slot_status
on public.service_slots (slot_status);

create unique index if not exists ux_service_slots_one_role_instance_per_service
on public.service_slots (
  service_instance_id,
  team_role_id,
  role_instance_number
)
where team_role_id is not null
  and role_instance_number is not null;

comment on column public.service_slots.team_role_id is
  'Optional source team_roles row used to generate this service slot.';

comment on column public.service_slots.role_instance_number is
  '1-based slot number for generated roles with quantity greater than one.';
