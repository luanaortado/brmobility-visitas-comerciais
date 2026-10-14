-- Registros de prospecção ficam separados da carteira para não afetar indicadores de clientes.
alter table public.visits drop constraint if exists visits_received_by_role_check;
alter table public.visits add constraint visits_received_by_role_check
  check (received_by_role in ('Gestor','Coordenador','Supervisor','Comprador'));

create table if not exists public.prospecting_visits (
  id uuid primary key default gen_random_uuid(),
  representative_id uuid not null references public.profiles(id) on delete restrict,
  representative_name text not null,
  company_name text not null,
  city text not null,
  state text not null,
  segment text not null,
  administrator_group text,
  contact_name text not null,
  contact_role text,
  contact_phone text,
  contact_email text,
  visit_date date not null,
  visit_time time,
  meeting_mode text not null check (meeting_mode in ('Presencial','Videoconferência')),
  topics text not null,
  estimated_vehicles integer not null check (estimated_vehicles >= 0),
  trello_url text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

alter table public.prospecting_visits enable row level security;
revoke all on public.prospecting_visits from anon;
grant select on public.prospecting_visits to authenticated;

drop policy if exists "Authenticated users view prospecting visits" on public.prospecting_visits;
create policy "Authenticated users view prospecting visits"
on public.prospecting_visits for select to authenticated
using (coalesce((select p.active from public.profiles p where p.id = auth.uid()), false));

create or replace function public.create_prospecting_visit(details jsonb)
returns public.prospecting_visits
language plpgsql security definer set search_path = public
as $$
declare
  actor public.profiles;
  saved public.prospecting_visits;
begin
  select * into actor from public.profiles where id = auth.uid() and active = true;
  if actor.id is null or not public.has_permission('record_visits') then
    raise exception 'Sem permissão para registrar visitas/reuniões.';
  end if;
  if trim(coalesce(details->>'companyName','')) = '' or trim(coalesce(details->>'city','')) = ''
    or length(trim(coalesce(details->>'state',''))) <> 2 or trim(coalesce(details->>'segment','')) = ''
    or trim(coalesce(details->>'contactName','')) = '' or trim(coalesce(details->>'topics','')) = '' then
    raise exception 'Preencha os campos obrigatórios da prospecção.';
  end if;
  if coalesce(details->>'trelloUrl','') !~* '^https?://' then
    raise exception 'Informe um link válido do cartão do Trello.';
  end if;
  insert into public.prospecting_visits (
    representative_id, representative_name, company_name, city, state, segment,
    administrator_group, contact_name, contact_role, contact_phone, contact_email,
    visit_date, visit_time, meeting_mode, topics, estimated_vehicles, trello_url
  ) values (
    actor.id, actor.full_name, trim(details->>'companyName'), trim(details->>'city'), upper(trim(details->>'state')),
    trim(details->>'segment'), nullif(trim(details->>'administratorGroup'),''), trim(details->>'contactName'),
    nullif(trim(details->>'contactRole'),''), nullif(trim(details->>'contactPhone'),''), nullif(trim(details->>'contactEmail'),''),
    (details->>'visitDate')::date, nullif(details->>'visitTime','')::time,
    case when details->>'meetingMode' = 'Videoconferência' then 'Videoconferência' else 'Presencial' end,
    trim(details->>'topics'), greatest(coalesce((details->>'estimatedVehicles')::integer,0),0), trim(details->>'trelloUrl')
  ) returning * into saved;
  return saved;
end;
$$;

revoke all on function public.create_prospecting_visit(jsonb) from public, anon;
grant execute on function public.create_prospecting_visit(jsonb) to authenticated;
