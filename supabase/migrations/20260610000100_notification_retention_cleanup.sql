-- Notification retention and user-controlled cleanup.
-- Keeps read notifications bounded without requiring cleanup from Flutter
-- screens. Unread notifications are preserved until the user reads or deletes
-- them.

create index if not exists idx_notifications_user_created_at_desc
  on public.notifications (user_id, created_at desc);

create or replace function public.cleanup_notifications_for_user(
  p_user_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted_count integer := 0;
  v_step_count integer := 0;
begin
  -- Hard age limit: remove read notifications older than 90 days.
  delete from public.notifications
  where user_id = p_user_id
    and is_read = true
    and created_at < now() - interval '90 days';

  get diagnostics v_step_count = row_count;
  v_deleted_count := v_deleted_count + v_step_count;

  -- Soft count limit: keep unread notifications and delete older read
  -- notifications when a user has more than 100 total rows.
  with ranked_notifications as (
    select
      id,
      row_number() over (
        partition by user_id
        order by created_at desc, id desc
      ) as recency_rank
    from public.notifications
    where user_id = p_user_id
  ),
  read_over_limit as (
    select notifications.id
    from public.notifications
    join ranked_notifications
      on ranked_notifications.id = notifications.id
    where ranked_notifications.recency_rank > 100
      and notifications.is_read = true
  )
  delete from public.notifications
  using read_over_limit
  where notifications.id = read_over_limit.id;

  get diagnostics v_step_count = row_count;
  v_deleted_count := v_deleted_count + v_step_count;

  return v_deleted_count;
end;
$$;

revoke all on function public.cleanup_notifications_for_user(uuid) from public;
revoke all on function public.cleanup_notifications_for_user(uuid)
  from authenticated;

create or replace function public.cleanup_notifications_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.cleanup_notifications_for_user(new.user_id);
  return new;
end;
$$;

drop trigger if exists trg_cleanup_notifications_after_insert
  on public.notifications;

create trigger trg_cleanup_notifications_after_insert
after insert on public.notifications
for each row
execute function public.cleanup_notifications_after_insert();
