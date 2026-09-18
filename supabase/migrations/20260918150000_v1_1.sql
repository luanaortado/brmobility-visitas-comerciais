-- Pacote V1.1: perfil 30 segundos, contatos, visitas, auditoria, acesso e sync.
do $$ begin
  create type public.visit_motive as enum ('Relacionamento','Acompanhamento operacional','Reclamação','Renovação','Expansão/Nova oportunidade','Treinamento','Outro');
exception when duplicate_object then null; end $$;

alter type public.client_scope_type add value if not exists 'administrator';

alter table public.clients
  add column if not exists permanent_id uuid not null default gen_random_uuid(),
  add column if not exists sync_updated_at timestamptz not null default now(),
  add column if not exists sync_source text not null default 'import' check (sync_source in ('app','sheet','import','system')),
  add column if not exists archived_at timestamptz;
create unique index if not exists clients_permanent_id_idx on public.clients(permanent_id);

alter table public.profiles
  add column if not exists can_view_financial boolean not null default false,
  add column if not exists can_edit_financial boolean not null default false,
  add column if not exists can_view_contract_value boolean not null default false,
  add column if not exists can_edit_profile boolean not null default false,
  add column if not exists can_edit_contacts boolean not null default false,
  add column if not exists can_record_visits boolean not null default true,
  add column if not exists deactivated_at timestamptz;

alter table public.user_scopes
  add column if not exists administrator text,
  add column if not exists can_edit_financial boolean not null default false,
  add column if not exists can_view_contract_value boolean not null default false,
  add column if not exists can_edit_profile boolean not null default false;
alter table public.user_scopes drop constraint if exists user_scopes_check;
alter table public.user_scopes add constraint user_scopes_check check (
  (scope_type='client' and client_id is not null) or
  (scope_type='state' and state is not null) or
  (scope_type='region' and region_id is not null) or
  (scope_type='account_manager' and account_manager is not null) or
  (scope_type='administrator' and administrator is not null)
);

alter table public.visits
  add column if not exists visit_motive public.visit_motive not null default 'Relacionamento',
  add column if not exists opportunity_identified boolean not null default false,
  add column if not exists opportunity_description text,
  add column if not exists archived_at timestamptz,
  add constraint visits_opportunity_description_check check (not opportunity_identified or nullif(trim(opportunity_description),'') is not null);

create table if not exists public.client_contacts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  name text not null,
  role text,
  phone text,
  email text,
  is_primary boolean not null default false,
  active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists one_primary_contact_per_client on public.client_contacts(client_id) where is_primary and active;

insert into public.client_contacts(client_id,name,role,phone,email,is_primary)
select id,primary_contact_name,primary_contact_role,primary_contact_phone,primary_contact_email,true
from public.clients c
where nullif(trim(primary_contact_name),'') is not null
  and not exists (select 1 from public.client_contacts cc where cc.client_id=c.id and cc.is_primary and cc.active);

alter table public.audit_log
  add column if not exists client_id uuid references public.clients(id) on delete restrict,
  add column if not exists source text not null default 'app',
  add column if not exists actor_name text,
  add column if not exists event_type text;
create index if not exists audit_client_timeline_idx on public.audit_log(client_id,changed_at desc);

create table if not exists public.sheet_sync_queue (
  id bigint generated always as identity primary key,
  client_id uuid not null references public.clients(id) on delete restrict,
  field_name text not null,
  field_value jsonb,
  source_updated_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','processing','synced','error','superseded')),
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index if not exists sheet_sync_pending_idx on public.sheet_sync_queue(status,created_at) where status='pending';

create or replace function public.has_permission(permission_name text)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(p.active and (
    p.role='admin' or
    (p.role in ('manager','supervisor') and permission_name <> 'manage_users') or
    case permission_name
      when 'view_financial' then p.can_view_financial
      when 'edit_financial' then p.can_edit_financial
      when 'view_contract_value' then p.can_view_contract_value
      when 'edit_profile' then p.can_edit_profile
      when 'edit_contacts' then p.can_edit_contacts
      when 'record_visits' then p.can_record_visits
      when 'manage_users' then p.role='admin'
      else false end
  ),false) from public.profiles p where p.id=auth.uid()
$$;

create or replace function public.can_view_client(target public.clients)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select p.active and (p.role in ('admin','manager') or exists (
    select 1 from public.user_scopes s where s.profile_id=p.id and s.can_view and (
      (s.scope_type='client' and s.client_id=target.id) or
      (s.scope_type='state' and s.state=target.state) or
      (s.scope_type='region' and s.region_id=target.region_id) or
      (s.scope_type='account_manager' and s.account_manager=target.current_account_manager) or
      (s.scope_type='administrator' and s.administrator=target.administrator)
    ))) from public.profiles p where p.id=auth.uid()),false)
$$;

-- Financial fields are masked in the database, not only in the interface.
create or replace function public.get_visible_clients()
returns setof jsonb language sql stable security definer set search_path=public as $$
  select to_jsonb(c)
    || jsonb_build_object('financial_status',case when public.has_permission('view_financial') then to_jsonb(c.financial_status) else 'null'::jsonb end)
    || jsonb_build_object('contract_value',case when public.has_permission('view_contract_value') then to_jsonb(c.contract_value) else 'null'::jsonb end)
  from public.clients c
  where c.archived_at is null and public.can_view_client(c)
  order by c.site_name
$$;
revoke all on function public.get_visible_clients() from public;
grant execute on function public.get_visible_clients() to authenticated;

create or replace function public.update_client_management_profile(
  target_client_id uuid,
  new_relationship public.relationship_level,
  new_financial public.financial_status,
  new_training text,
  new_account_manager text,
  new_last_fleet_change date
)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.can_view_client((select c from public.clients c where c.id=target_client_id)) or not public.has_permission('edit_profile') then
    raise exception 'Sem permissão para editar este perfil.';
  end if;
  if new_financial is distinct from (select financial_status from public.clients where id=target_client_id) and not public.has_permission('edit_financial') then
    raise exception 'Sem permissão para editar o financeiro.';
  end if;
  if new_training not in ('Sim','Não') or nullif(trim(new_account_manager),'') is null then raise exception 'Dados do perfil inválidos.'; end if;
  update public.clients set relationship=new_relationship,financial_status=new_financial,training=new_training,
    current_account_manager=trim(new_account_manager),last_fleet_change=date_trunc('month',new_last_fleet_change)::date,
    sheet_sync_status='pending',sync_source='app',sync_updated_at=now(),updated_at=now()
  where id=target_client_id;
end $$;
revoke all on function public.update_client_management_profile(uuid,public.relationship_level,public.financial_status,text,text,date) from public;
grant execute on function public.update_client_management_profile(uuid,public.relationship_level,public.financial_status,text,text,date) to authenticated;

create or replace function public.set_primary_contact(target_contact_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare target_client uuid; selected public.client_contacts;
begin
  select * into selected from public.client_contacts where id=target_contact_id and active;
  target_client:=selected.client_id;
  if selected.id is null or not public.can_view_client((select c from public.clients c where c.id=target_client)) or not public.has_permission('edit_contacts') then raise exception 'Sem permissão.'; end if;
  update public.client_contacts set is_primary=false,updated_at=now() where client_id=target_client and is_primary;
  update public.client_contacts set is_primary=true,updated_at=now() where id=target_contact_id;
  update public.clients set primary_contact_name=selected.name,primary_contact_role=selected.role,primary_contact_phone=selected.phone,
    primary_contact_email=selected.email,sheet_sync_status='pending',sync_source='app',sync_updated_at=now(),updated_at=now() where id=target_client;
end $$;
grant execute on function public.set_primary_contact(uuid) to authenticated;

create or replace function public.audit_changes_v11()
returns trigger language plpgsql security definer set search_path=public as $$
declare old_j jsonb; new_j jsonb; fields text[]; linked_client uuid; actor text;
begin
  old_j:=case when tg_op='INSERT' then null else to_jsonb(old) end;
  new_j:=case when tg_op='DELETE' then null else to_jsonb(new) end;
  if tg_op='UPDATE' then select coalesce(array_agg(n.key order by n.key),'{}') into fields from jsonb_each(new_j)n join jsonb_each(old_j)o using(key) where n.value is distinct from o.value; else fields:='{}'; end if;
  linked_client:=case when tg_table_name='clients' then coalesce(new.id,old.id) else coalesce((new_j->>'client_id')::uuid,(old_j->>'client_id')::uuid) end;
  select full_name into actor from public.profiles where id=auth.uid();
  insert into public.audit_log(table_name,record_id,action,changed_by,changed_at,old_values,new_values,changed_fields,request_id,client_id,source,actor_name,event_type)
  values(tg_table_name,coalesce(new.id,old.id),tg_op,auth.uid(),now(),old_j,new_j,fields,current_setting('request.headers',true)::jsonb->>'x-request-id',linked_client,
    coalesce(new_j->>'sync_source','app'),coalesce(actor,'Sistema'),case when tg_table_name='visits' then 'Visita' when tg_table_name='client_contacts' then 'Contato' when tg_table_name in ('profiles','user_scopes') then 'Permissão e acesso' else 'Alteração de perfil' end);
  return coalesce(new,old);
end $$;
drop trigger if exists audit_clients on public.clients;
drop trigger if exists audit_visits on public.visits;
drop trigger if exists audit_contacts on public.client_contacts;
drop trigger if exists audit_scopes on public.user_scopes;
drop trigger if exists audit_profiles on public.profiles;
create trigger audit_clients after insert or update on public.clients for each row execute function public.audit_changes_v11();
create trigger audit_visits after insert or update on public.visits for each row execute function public.audit_changes_v11();
create trigger audit_contacts after insert or update on public.client_contacts for each row execute function public.audit_changes_v11();
create trigger audit_scopes after insert or update on public.user_scopes for each row execute function public.audit_changes_v11();
create trigger audit_profiles after update on public.profiles for each row execute function public.audit_changes_v11();

create or replace function public.queue_client_sheet_sync()
returns trigger language plpgsql security definer set search_path=public as $$
declare f text;
begin
  if new.sync_source<>'app' then return new; end if;
  foreach f in array array['relationship','financial_status','training','current_account_manager','last_fleet_change','primary_contact_name','primary_contact_role','primary_contact_phone','primary_contact_email'] loop
    if to_jsonb(new)->f is distinct from to_jsonb(old)->f then
      update public.sheet_sync_queue set status='superseded' where client_id=new.id and field_name=f and status='pending';
      insert into public.sheet_sync_queue(client_id,field_name,field_value,source_updated_at) values(new.id,f,to_jsonb(new)->f,new.sync_updated_at);
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists queue_client_sheet_sync on public.clients;
create trigger queue_client_sheet_sync after update on public.clients for each row execute function public.queue_client_sheet_sync();

create or replace view public.client_timeline with (security_invoker=true) as
select a.id::text,a.client_id,a.event_type,a.changed_at as occurred_at,a.actor_name,a.source,
  f.field_name,
  case when f.field_name is null then null else a.old_values->>f.field_name end old_value,
  case when f.field_name is null then null else a.new_values->>f.field_name end new_value
from public.audit_log a
cross join lateral unnest(case when cardinality(a.changed_fields)=0 then array[null::text] else a.changed_fields end) as f(field_name)
where a.client_id is not null;

alter table public.client_contacts enable row level security;
alter table public.sheet_sync_queue enable row level security;
create policy contacts_select on public.client_contacts for select using (public.can_view_client((select c from public.clients c where c.id=client_id)));
create policy contacts_write on public.client_contacts for all using (public.has_permission('edit_contacts') and public.can_view_client((select c from public.clients c where c.id=client_id))) with check (public.has_permission('edit_contacts') and public.can_view_client((select c from public.clients c where c.id=client_id)));
create policy sync_queue_admin on public.sheet_sync_queue for select using (public.current_profile_role()='admin');
grant select,insert,update on public.client_contacts to authenticated;
grant select on public.client_timeline to authenticated;
grant select on public.sheet_sync_queue to authenticated;

drop policy if exists audit_scoped_select on public.audit_log;
create policy audit_scoped_select on public.audit_log for select using (
  public.is_admin_or_manager() or changed_by=auth.uid() or
  (client_id is not null and public.can_view_client((select c from public.clients c where c.id=client_id)))
);

-- Force clients through the masked function; writes continue through audited RPCs.
revoke select on public.clients from authenticated;

-- Representatives can never delete business history; records are archived/inactivated.
revoke delete on public.visits,public.audit_log,public.client_contacts,public.clients from authenticated;

-- Protect inactive accounts even if an old access token still exists.
create or replace function public.block_inactive_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin if not exists(select 1 from public.profiles where id=auth.uid() and active) then raise exception 'Usuário desativado.'; end if; return new; end $$;
drop trigger if exists block_inactive_visits on public.visits;
create trigger block_inactive_visits before insert or update on public.visits for each statement execute function public.block_inactive_user();
