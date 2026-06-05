create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  title text not null,
  message text not null,
  notification_type text not null,
  is_read boolean not null default false,
  related_service_instance_id uuid null references public.service_instances(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_user_id
  on public.notifications (user_id);

create index if not exists idx_notifications_is_read
  on public.notifications (is_read);

create index if not exists idx_notifications_created_at_desc
  on public.notifications (created_at desc);

alter table public.notifications enable row level security;

drop policy if exists "Users can view own notifications"
  on public.notifications;

create policy "Users can view own notifications"
  on public.notifications
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users can update own notifications"
  on public.notifications;

create policy "Users can update own notifications"
  on public.notifications
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Admins can create notifications"
  on public.notifications;

create policy "Admins can create notifications"
  on public.notifications
  for insert
  with check (
    exists (
      select 1
      from public.profiles
      where profiles.id = auth.uid()
        and profiles.role = 'admin'
    )
  );

drop policy if exists "Users can create admin notifications"
  on public.notifications;

create policy "Users can create admin notifications"
  on public.notifications
  for insert
  with check (
    exists (
      select 1
      from public.profiles
      where profiles.id = notifications.user_id
        and profiles.role = 'admin'
    )
  );
