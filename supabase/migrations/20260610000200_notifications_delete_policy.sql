-- Allow users to delete only their own notifications.
-- Table privileges and RLS are both required for Supabase delete() calls.

drop policy if exists "Users can delete own notifications"
  on public.notifications;

create policy "Users can delete own notifications"
  on public.notifications
  for delete
  using (auth.uid() = user_id);

grant delete on public.notifications to authenticated;
