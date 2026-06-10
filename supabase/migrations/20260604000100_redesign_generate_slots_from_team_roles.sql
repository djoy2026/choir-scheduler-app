-- Redesign slot generation to be quantity-aware, additive, and idempotent.
--
-- Standard team mode:
--   Generate slots from active roles assigned directly to the service team.
--
-- Children's Ministry Live Schedule mode:
--   When the selected service team is named "Children's Ministry Live Schedule",
--   generate slots from active roles assigned to every other team in the same
--   ministry. Prefix slot_name with the source team name.
--
-- Existing service_slots are never updated or deleted. A generated candidate
-- is inserted only when its slot_name does not already exist for the service.

drop function if exists public.generate_slots_from_team_roles(uuid);

create function public.generate_slots_from_team_roles(
  p_service_instance_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team_id uuid;
  v_ministry_id uuid;
  v_team_name text;
  v_is_live_schedule boolean;
  v_created_count integer;
begin
  select
    service_instances.team_id,
    service_instances.ministry_id,
    teams.name
  into
    v_team_id,
    v_ministry_id,
    v_team_name
  from public.service_instances
  join public.teams
    on teams.id = service_instances.team_id
  where service_instances.id = p_service_instance_id;

  if v_team_id is null then
    raise exception 'Service instance not found: %', p_service_instance_id;
  end if;

  v_is_live_schedule :=
    v_team_name = 'Children''s Ministry Live Schedule';

  -- Serialize generation for the same service instance so concurrent calls
  -- cannot both observe and insert the same missing slot_name.
  perform pg_advisory_xact_lock(
    hashtextextended(p_service_instance_id::text, 0)
  );

  with source_roles as (
    select
      team_roles.id as team_role_id,
      team_roles.role_name,
      team_roles.quantity,
      team_roles.display_order,
      teams.id as source_team_id,
      teams.name as source_team_name
    from public.team_roles
    join public.teams
      on teams.id = team_roles.team_id
    where team_roles.is_active = true
      and (
        (
          not v_is_live_schedule
          and team_roles.team_id = v_team_id
        )
        or
        (
          v_is_live_schedule
          and teams.ministry_id = v_ministry_id
          and teams.id <> v_team_id
        )
      )
  ),
  raw_generated_candidates as (
    select
      source_roles.team_role_id,
      role_instances.instance_number as role_instance_number,
      case
        when source_roles.quantity = 1
          then source_roles.role_name
        else source_roles.role_name || ' ' || role_instances.instance_number::text
      end as generated_role_name,
      case
        when v_is_live_schedule then
          source_roles.source_team_name || ' - ' ||
          case
            when source_roles.quantity = 1
              then source_roles.role_name
            else source_roles.role_name || ' ' || role_instances.instance_number::text
          end
        when source_roles.quantity = 1 then
          source_roles.role_name
        else
          source_roles.role_name || ' ' || role_instances.instance_number::text
      end as generated_slot_name,
      source_roles.source_team_name,
      source_roles.display_order
    from source_roles
    cross join lateral generate_series(
      1,
      source_roles.quantity
    ) as role_instances(instance_number)
  ),
  generated_candidates as (
    select
      raw_generated_candidates.*,
      row_number() over (
        partition by raw_generated_candidates.generated_slot_name
        order by
          raw_generated_candidates.display_order,
          raw_generated_candidates.team_role_id,
          raw_generated_candidates.role_instance_number
      ) as candidate_rank
    from raw_generated_candidates
  ),
  inserted_slots as (
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
      generated_candidates.team_role_id,
      generated_candidates.role_instance_number,
      generated_candidates.generated_slot_name,
      generated_candidates.generated_role_name,
      'open',
      null,
      'amber'
    from generated_candidates
    where generated_candidates.candidate_rank = 1
      and not exists (
        select 1
        from public.service_slots existing_slots
        where existing_slots.service_instance_id = p_service_instance_id
          and existing_slots.slot_name =
            generated_candidates.generated_slot_name
      )
    order by
      generated_candidates.source_team_name,
      generated_candidates.display_order,
      generated_candidates.generated_role_name
    returning id
  )
  select count(*)::integer
  into v_created_count
  from inserted_slots;

  return v_created_count;
end;
$$;

comment on function public.generate_slots_from_team_roles(uuid) is
  'Adds missing quantity-aware service slots by slot_name and returns the number created. Supports standard teams and the Children''s Ministry Live Schedule aggregate team.';

revoke all on function public.generate_slots_from_team_roles(uuid) from public;
grant execute on function public.generate_slots_from_team_roles(uuid)
to authenticated;
