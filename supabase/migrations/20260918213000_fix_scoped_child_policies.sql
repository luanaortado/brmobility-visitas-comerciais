-- Keep child-table policies compatible with clients being readable only through
-- the masked get_visible_clients() RPC.
create or replace function public.can_view_client_id(target_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(public.can_view_client(c),false)
  from public.clients c
  where c.id=target_client_id
$$;

revoke all on function public.can_view_client_id(uuid) from public;
grant execute on function public.can_view_client_id(uuid) to authenticated;

drop policy if exists visits_scoped_select on public.visits;
create policy visits_scoped_select on public.visits for select
using (public.can_view_client_id(client_id));

drop policy if exists visits_scoped_insert on public.visits;
create policy visits_scoped_insert on public.visits for insert
with check (representative_id=auth.uid() and public.can_view_client_id(client_id));

drop policy if exists client_notes_scoped_select on public.client_notes;
create policy client_notes_scoped_select on public.client_notes for select
using (public.can_view_client_id(client_id));

drop policy if exists client_notes_scoped_insert on public.client_notes;
create policy client_notes_scoped_insert on public.client_notes for insert
with check (updated_by=auth.uid() and public.can_view_client_id(client_id));

drop policy if exists client_notes_scoped_update on public.client_notes;
create policy client_notes_scoped_update on public.client_notes for update
using (public.can_view_client_id(client_id))
with check (updated_by=auth.uid() and public.can_view_client_id(client_id));

drop policy if exists contacts_select on public.client_contacts;
create policy contacts_select on public.client_contacts for select
using (public.can_view_client_id(client_id));

drop policy if exists contacts_write on public.client_contacts;
create policy contacts_write on public.client_contacts for all
using (public.has_permission('edit_contacts') and public.can_view_client_id(client_id))
with check (public.has_permission('edit_contacts') and public.can_view_client_id(client_id));

drop policy if exists audit_scoped_select on public.audit_log;
create policy audit_scoped_select on public.audit_log for select using (
  public.is_admin_or_manager() or changed_by=auth.uid() or
  (client_id is not null and public.can_view_client_id(client_id))
);
