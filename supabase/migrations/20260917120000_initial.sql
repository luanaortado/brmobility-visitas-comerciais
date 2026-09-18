create extension if not exists pgcrypto;

create type public.app_role as enum ('admin', 'manager', 'supervisor', 'representative');
create type public.relationship_level as enum ('Excelente', 'Sensível', 'Crítico');
create type public.financial_status as enum ('Adimplente', 'Inadimplência Moderada', 'Inadimplente Crítico');
create type public.visit_status as enum ('Programada', 'Realizada', 'Atrasada', 'Cancelada', 'Reagendada');
create type public.client_scope_type as enum ('client', 'state', 'region', 'account_manager');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  role public.app_role not null default 'representative',
  job_title text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.regions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  states text[] not null default '{}',
  created_at timestamptz not null default now()
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  source_sheet_id text,
  source_sheet_name text not null default 'Perfil do Cliente',
  source_row integer unique,
  status text,
  start_date date,
  end_date date,
  contract_number text,
  legal_name text not null,
  site_name text not null,
  administrator text,
  segment text,
  quantity integer not null default 0,
  contract_value numeric(14,2),
  state char(2),
  region_id uuid references public.regions(id),
  current_account_manager text,
  relationship public.relationship_level not null default 'Excelente',
  financial_status public.financial_status not null default 'Adimplente',
  last_fleet_change date,
  adjustment text,
  ticket_report_url text,
  trello_url text,
  sla text,
  misuse_history text,
  logistics_complexity text,
  training text,
  legacy_last_contact text,
  address text,
  primary_contact_name text,
  primary_contact_role text,
  primary_contact_phone text,
  primary_contact_email text,
  sheet_sync_status text not null default 'pending' check (sheet_sync_status in ('pending','synced','error')),
  sheet_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index clients_state_idx on public.clients(state);
create index clients_manager_idx on public.clients(current_account_manager);
create index clients_attention_idx on public.clients(relationship, financial_status);

create table public.client_notes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique references public.clients(id) on delete cascade,
  note text not null default '',
  updated_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Time-bounded assignments preserve ownership history when a portfolio changes.
create table public.client_assignments (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  profile_id uuid not null references public.profiles(id),
  valid_from timestamptz not null default now(),
  valid_to timestamptz,
  assigned_by uuid references public.profiles(id),
  note text,
  check (valid_to is null or valid_to > valid_from)
);
create unique index one_current_assignment_per_user_client on public.client_assignments(client_id, profile_id) where valid_to is null;

create table public.user_scopes (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  scope_type public.client_scope_type not null,
  client_id uuid references public.clients(id) on delete cascade,
  state char(2),
  region_id uuid references public.regions(id) on delete cascade,
  account_manager text,
  can_view boolean not null default true,
  can_edit_contact boolean not null default false,
  can_record_visit boolean not null default true,
  can_view_financial boolean not null default false,
  granted_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (
    (scope_type = 'client' and client_id is not null) or
    (scope_type = 'state' and state is not null) or
    (scope_type = 'region' and region_id is not null) or
    (scope_type = 'account_manager' and account_manager is not null)
  )
);

create table public.visits (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  representative_id uuid not null references public.profiles(id) on delete restrict,
  visit_date date not null,
  visit_time time,
  status public.visit_status not null default 'Realizada',
  received_by text not null,
  received_by_role text not null check (received_by_role in ('Gestor','Coordenador','Supervisor')),
  relationship public.relationship_level not null,
  viewed_ticket_report boolean not null default false,
  has_complaint boolean not null default false,
  complaint_description text,
  topics_and_solutions text not null,
  next_visit_date date,
  original_representative_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not has_complaint or nullif(trim(complaint_description),'') is not null)
);
create index visits_client_date_idx on public.visits(client_id, visit_date desc);
create index visits_representative_date_idx on public.visits(representative_id, visit_date desc);

create table public.audit_log (
  id bigint generated always as identity primary key,
  table_name text not null,
  record_id uuid not null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  old_values jsonb,
  new_values jsonb,
  changed_fields text[] not null default '{}',
  request_id text
);
create index audit_record_idx on public.audit_log(table_name, record_id, changed_at desc);

create or replace function public.current_profile_role()
returns public.app_role language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() and active $$;

create or replace function public.is_admin_or_manager()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.current_profile_role() in ('admin','manager'), false) $$;

create or replace function public.can_view_client(target public.clients)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_admin_or_manager() or exists (
    select 1 from public.user_scopes s
    where s.profile_id = auth.uid() and s.can_view and (
      (s.scope_type='client' and s.client_id=target.id) or
      (s.scope_type='state' and s.state=target.state) or
      (s.scope_type='region' and s.region_id=target.region_id) or
      (s.scope_type='account_manager' and s.account_manager=target.current_account_manager)
    )
  )
$$;

create or replace function public.can_edit_client_contact(target public.clients)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_admin_or_manager() or exists (
    select 1 from public.user_scopes s where s.profile_id=auth.uid() and s.can_edit_contact and (
      (s.scope_type='client' and s.client_id=target.id) or
      (s.scope_type='state' and s.state=target.state) or
      (s.scope_type='region' and s.region_id=target.region_id) or
      (s.scope_type='account_manager' and s.account_manager=target.current_account_manager)
    )
  )
$$;

create or replace function public.audit_changes()
returns trigger language plpgsql security definer set search_path=public as $$
declare old_j jsonb; new_j jsonb; fields text[];
begin
  old_j := case when tg_op='INSERT' then null else to_jsonb(old) end;
  new_j := case when tg_op='DELETE' then null else to_jsonb(new) end;
  if tg_op='UPDATE' then
    select coalesce(array_agg(n.key order by n.key),'{}') into fields
    from jsonb_each(new_j) n join jsonb_each(old_j) o using(key) where n.value is distinct from o.value;
  else
    fields := '{}';
  end if;
  insert into public.audit_log(table_name,record_id,action,changed_by,old_values,new_values,changed_fields,request_id)
  values(tg_table_name,coalesce(new.id,old.id),tg_op,auth.uid(),old_j,new_j,fields,current_setting('request.headers',true)::jsonb->>'x-request-id');
  return coalesce(new,old);
end $$;

create trigger audit_clients after insert or update or delete on public.clients for each row execute function public.audit_changes();
create trigger audit_client_notes after insert or update or delete on public.client_notes for each row execute function public.audit_changes();
create trigger audit_visits after insert or update or delete on public.visits for each row execute function public.audit_changes();
create trigger audit_assignments after insert or update or delete on public.client_assignments for each row execute function public.audit_changes();
create trigger audit_scopes after insert or update or delete on public.user_scopes for each row execute function public.audit_changes();

create or replace function public.apply_visit_effects()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='Realizada' then
    update public.clients set relationship=new.relationship, updated_at=now() where id=new.client_id;
  end if;
  if new.next_visit_date is not null then
    insert into public.visits(client_id,representative_id,visit_date,status,received_by,received_by_role,relationship,topics_and_solutions,original_representative_name)
    values(new.client_id,new.representative_id,new.next_visit_date,'Programada','A confirmar','Gestor',new.relationship,'Visita gerada automaticamente',new.original_representative_name);
  end if;
  return new;
end $$;
create trigger apply_visit_effects after insert on public.visits for each row when (new.status='Realizada') execute function public.apply_visit_effects();

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.client_notes enable row level security;
alter table public.client_assignments enable row level security;
alter table public.user_scopes enable row level security;
alter table public.visits enable row level security;
alter table public.audit_log enable row level security;

create policy profiles_self_select on public.profiles for select using (id=auth.uid() or public.is_admin_or_manager());
create policy profiles_admin_write on public.profiles for all using (public.current_profile_role()='admin') with check (public.current_profile_role()='admin');
create policy clients_scoped_select on public.clients for select using (public.can_view_client(clients));
create policy clients_admin_insert on public.clients for insert with check (public.is_admin_or_manager());
create policy clients_admin_update on public.clients for update using (public.is_admin_or_manager()) with check (public.is_admin_or_manager());
create policy clients_contact_update on public.clients for update using (public.can_edit_client_contact(clients)) with check (public.can_edit_client_contact(clients));
create policy client_notes_scoped_select on public.client_notes for select using (public.can_view_client((select c from public.clients c where c.id=client_id)));
create policy client_notes_scoped_insert on public.client_notes for insert with check (updated_by=auth.uid() and public.can_view_client((select c from public.clients c where c.id=client_id)));
create policy client_notes_scoped_update on public.client_notes for update using (public.can_view_client((select c from public.clients c where c.id=client_id))) with check (updated_by=auth.uid() and public.can_view_client((select c from public.clients c where c.id=client_id)));
create policy assignments_scoped_select on public.client_assignments for select using (profile_id=auth.uid() or public.is_admin_or_manager());
create policy assignments_admin_write on public.client_assignments for all using (public.is_admin_or_manager()) with check (public.is_admin_or_manager());
create policy scopes_self_select on public.user_scopes for select using (profile_id=auth.uid() or public.is_admin_or_manager());
create policy scopes_admin_write on public.user_scopes for all using (public.is_admin_or_manager()) with check (public.is_admin_or_manager());
create policy visits_scoped_select on public.visits for select using (public.can_view_client((select c from public.clients c where c.id=client_id)));
create policy visits_scoped_insert on public.visits for insert with check (representative_id=auth.uid() and public.can_view_client((select c from public.clients c where c.id=client_id)));
create policy visits_owner_update on public.visits for update using (representative_id=auth.uid() or public.is_admin_or_manager()) with check (representative_id=auth.uid() or public.is_admin_or_manager());
create policy audit_scoped_select on public.audit_log for select using (public.is_admin_or_manager() or changed_by=auth.uid());

revoke update on public.clients from authenticated;
grant select on public.clients to authenticated;
grant update(primary_contact_name,primary_contact_role,primary_contact_phone,primary_contact_email,sheet_sync_status,sheet_synced_at,updated_at) on public.clients to authenticated;
grant select,insert,update on public.client_notes to authenticated;
grant select,insert,update on public.visits to authenticated;
grant select on public.profiles,public.client_assignments,public.user_scopes,public.audit_log,public.regions to authenticated;

create or replace view public.dashboard_summary with (security_invoker=true) as
select
  count(*) as visible_clients,
  count(*) filter (where relationship='Excelente') as relationship_excellent,
  count(*) filter (where relationship='Sensível') as relationship_sensitive,
  count(*) filter (where relationship='Crítico') as relationship_critical,
  count(*) filter (where financial_status='Adimplente') as financially_current,
  count(*) filter (where financial_status='Inadimplência Moderada') as financially_moderate,
  count(*) filter (where financial_status='Inadimplente Crítico') as financially_critical
from public.clients;
grant select on public.dashboard_summary to authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,full_name,email,role)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1)),new.email,
    case when new.raw_user_meta_data->>'role' in ('admin','manager','supervisor','representative') then (new.raw_user_meta_data->>'role')::public.app_role else 'representative' end);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
