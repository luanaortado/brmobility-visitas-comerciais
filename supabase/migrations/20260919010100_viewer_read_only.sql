-- Diretoria: acesso a toda a carteira, sem qualquer permissão de escrita.
create or replace function public.can_view_client(target public.clients)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select p.active and (p.role in ('admin','manager','viewer') or exists (
    select 1 from public.user_scopes s where s.profile_id=p.id and s.can_view and (
      (s.scope_type='client' and s.client_id=target.id) or
      (s.scope_type='state' and s.state=target.state) or
      (s.scope_type='region' and s.region_id=target.region_id) or
      (s.scope_type='account_manager' and s.account_manager=target.current_account_manager) or
      (s.scope_type='administrator' and s.administrator=target.administrator)
    ))) from public.profiles p where p.id=auth.uid()),false)
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,full_name,email,role)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1)),new.email,
    case when new.raw_user_meta_data->>'role' in ('admin','manager','supervisor','representative','viewer') then (new.raw_user_meta_data->>'role')::public.app_role else 'representative' end);
  return new;
end $$;

drop policy if exists visits_scoped_insert on public.visits;
create policy visits_scoped_insert on public.visits for insert
with check (
  representative_id=auth.uid()
  and public.can_view_client_id(client_id)
  and public.has_permission('record_visits')
);

drop policy if exists visits_owner_update on public.visits;
create policy visits_owner_update on public.visits for update
using (public.is_admin_or_manager() or (representative_id=auth.uid() and public.has_permission('record_visits')))
with check (public.is_admin_or_manager() or (representative_id=auth.uid() and public.has_permission('record_visits')));

drop policy if exists client_notes_scoped_insert on public.client_notes;
create policy client_notes_scoped_insert on public.client_notes for insert
with check (updated_by=auth.uid() and public.can_view_client_id(client_id) and public.has_permission('edit_profile'));

drop policy if exists client_notes_scoped_update on public.client_notes;
create policy client_notes_scoped_update on public.client_notes for update
using (public.can_view_client_id(client_id) and public.has_permission('edit_profile'))
with check (updated_by=auth.uid() and public.can_view_client_id(client_id) and public.has_permission('edit_profile'));
