-- Update slot generation to use each service instance's team role configuration.
-- This preserves the existing RPC name used by Flutter:
-- generate_slots_from_team_roles(p_service_instance_id)
--
-- The function is idempotent. Re-running it for the same service inserts
-- missing generated slots and leaves existing generated slots unchanged.

create or replace function public.generate_slots_from_team_roles(
  p_service_instance_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team_id uuid;
begin
  select service_instances.team_id
  into v_team_id
  from public.service_instances
  where service_instances.id = p_service_instance_id;

  if v_team_id is null then
    raise exception 'Service instance not found: %', p_service_instance_id;
  end if;

  insert into public.service_slots (
    service_instance_id,
    team_role_id,
    role_instance_number,
    slot_name,
    role_name,
    slot_status,
    assigned_user_id,
    color_code
  )
  select
    p_service_instance_id,
    team_roles.id,
    role_instances.instance_number,
    case
      when team_roles.quantity = 1 then team_roles.role_name
      else team_roles.role_name || ' ' || role_instances.instance_number::text
    end as slot_name,
    case
      when team_roles.quantity = 1 then team_roles.role_name
      else team_roles.role_name || ' ' || role_instances.instance_number::text
    end as role_name,
    'open' as slot_status,
    null as assigned_user_id,
    'amber' as color_code
  from public.team_roles
  cross join lateral generate_series(
    1,
    team_roles.quantity
  ) as role_instances(instance_number)
  where team_roles.team_id = v_team_id
    and team_roles.is_active = true
  order by
    team_roles.display_order,
    team_roles.role_name,
    role_instances.instance_number
  on conflict (
    service_instance_id,
    team_role_id,
    role_instance_number
  )
  where team_role_id is not null
    and role_instance_number is not null
  do nothing;
end;
$$;

comment on function public.generate_slots_from_team_roles(uuid) is
  'Generates open service_slots from active team_roles and role quantities for a service_instance.';

revoke all on function public.generate_slots_from_team_roles(uuid) from public;
grant execute on function public.generate_slots_from_team_roles(uuid) to authenticated;
