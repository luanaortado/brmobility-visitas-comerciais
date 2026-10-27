-- Gestão mensal de visitas dos Regionais: carteira, validação e pagamento.
-- Mantém os registros anteriores e evolui o fluxo sem excluir histórico.

alter table public.profiles
  add column if not exists can_validate_regional_visits boolean not null default false;

update public.profiles
set can_validate_regional_visits = lower(email) = 'luana@brmobility.com.br';

create table if not exists public.regional_directory (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  full_name text not null,
  display_name text not null,
  email text not null unique,
  phone text not null default '',
  relationship_type text not null default 'Regional' check (relationship_type in ('Regional','Comercial Local')),
  states text[] not null default '{}',
  active boolean not null default true,
  issues_invoice boolean not null default false,
  paid_per_visit boolean not null default true,
  visit_fee numeric(12,2) not null default 90,
  fixed_monthly_amount numeric(12,2),
  requires_email_formalization boolean not null default false,
  can_access_trello boolean not null default false,
  allows_travel_expense boolean not null default false,
  tax_id text,
  legal_name text,
  pix_key text,
  payment_document text not null default 'Não aplicável',
  finance_email text,
  started_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.regional_directory enable row level security;
drop policy if exists regional_directory_self_read on public.regional_directory;
create policy regional_directory_self_read on public.regional_directory for select to authenticated
using (profile_id=auth.uid() or public.is_admin_or_manager());
revoke insert,update,delete on public.regional_directory from authenticated,anon;
grant select on public.regional_directory to authenticated;

create or replace function public.can_validate_regional_visits()
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select p.active and p.can_validate_regional_visits from public.profiles p where p.id=auth.uid()),false)
$$;

create or replace function public.can_view_client(target public.clients)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select p.active and (
    p.role in ('admin','manager','supervisor','viewer') or
    exists(select 1 from public.regional_directory r where r.profile_id=p.id and r.active and upper(target.state)=any(r.states)) or
    exists(select 1 from public.user_scopes s where s.profile_id=p.id and s.can_view and (
      (s.scope_type='client' and s.client_id=target.id) or
      (s.scope_type='state' and s.state=target.state) or
      (s.scope_type='region' and s.region_id=target.region_id) or
      (s.scope_type='account_manager' and s.account_manager=target.current_account_manager) or
      (s.scope_type='administrator' and s.administrator=target.administrator)
    ))
  ) from public.profiles p where p.id=auth.uid()),false)
$$;

create or replace function public.get_visible_clients()
returns setof jsonb language sql stable security definer set search_path=public as $$
  select to_jsonb(c)
    || jsonb_build_object('financial_status',case when public.has_permission('view_financial') then to_jsonb(c.financial_status) else 'null'::jsonb end)
    || jsonb_build_object('contract_value',case when public.has_permission('view_contract_value') then to_jsonb(c.contract_value) else 'null'::jsonb end)
    || jsonb_build_object('trello_url',case when public.is_admin_or_manager() or coalesce((select r.can_access_trello from public.regional_directory r where r.profile_id=auth.uid()),false) or public.current_profile_role()='viewer' then to_jsonb(c.trello_url) else 'null'::jsonb end)
  from public.clients c
  where c.archived_at is null and public.can_view_client(c)
  order by c.site_name
$$;

alter table public.regional_monthly_plans
  alter column planned_date drop not null,
  add column if not exists relationship_reason boolean not null default false,
  add column if not exists ticket_volume_reason boolean not null default false,
  add column if not exists requested_at timestamptz not null default now(),
  add column if not exists requested_by uuid references public.profiles(id);

update public.regional_monthly_plans
set priority=case when priority='Urgente' then 'Alta' else 'Média' end
where priority not in ('Alta','Média');
alter table public.regional_monthly_plans drop constraint if exists regional_monthly_plans_priority_check;
alter table public.regional_monthly_plans add constraint regional_monthly_plans_priority_check check(priority in ('Alta','Média'));

alter table public.regional_visit_checks
  add column if not exists email_formalized boolean not null default false,
  add column if not exists travel_amount numeric(12,2) not null default 0,
  add column if not exists travel_note text not null default '',
  add column if not exists travel_approved boolean not null default false,
  add column if not exists paid_at timestamptz;

update public.regional_visit_checks
set email_formalized=(email_sent_on is not null or nullif(trim(email_evidence),'') is not null);

alter table public.regional_visit_checks drop constraint if exists regional_visit_checks_payment_status_check;
alter table public.regional_visit_checks add constraint regional_visit_checks_payment_status_check
check(payment_status in ('Pendente','NF Solicitada','NF Recebida','Enviado ao Financeiro','Pago','Não se aplica'));

create or replace function public.set_regional_month_plan_v2(
  month_start date, at_name text, post_ids uuid[], visit_guidance text,
  visit_priority text, relationship_reason boolean, ticket_volume_reason boolean
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb; actor_name text;
begin
  select p.full_name into actor_name from public.profiles p where p.id=auth.uid() and p.active and p.role::text in ('admin','manager');
  if actor_name is null then raise exception 'Somente a gestão solicita visitas.'; end if;
  if month_start is null or date_trunc('month',month_start)::date<>month_start or coalesce(trim(at_name),'')='' or coalesce(cardinality(post_ids),0)=0 then raise exception 'Informe mês, Regional e postos.'; end if;
  if visit_priority not in ('Alta','Média') then raise exception 'Prioridade inválida.'; end if;
  if not coalesce(relationship_reason,false) and not coalesce(ticket_volume_reason,false) then raise exception 'Selecione ao menos um motivo.'; end if;
  if coalesce(trim(visit_guidance),'')='' then raise exception 'Inclua um breve relato para a visita.'; end if;
  perform pg_advisory_xact_lock(20261027);
  if exists(select 1 from unnest(post_ids) id where not exists(select 1 from public.clients c where c.id=id and public.can_view_client(c))) then raise exception 'Posto sem acesso ou não encontrado.'; end if;
  insert into public.regional_monthly_plans(period,client_id,regional_name,planned_date,guidance,priority,source,relationship_reason,ticket_volume_reason,requested_by,updated_by)
  select month_start,id,trim(at_name),null,trim(visit_guidance),visit_priority,'Manual',relationship_reason,ticket_volume_reason,auth.uid(),auth.uid()
  from (select distinct unnest(post_ids) id) selected
  on conflict(period,client_id) do update set regional_name=excluded.regional_name,planned_date=null,guidance=excluded.guidance,priority=excluded.priority,source='Manual',relationship_reason=excluded.relationship_reason,ticket_volume_reason=excluded.ticket_volume_reason,requested_at=now(),requested_by=auth.uid(),active=true,updated_by=auth.uid(),updated_at=now();
  insert into public.regional_visit_events(plan_id,event_type,note,actor_id,actor_name)
  select p.id,'Visita solicitada',concat(p.regional_name,' · ',p.priority,' · ',case when p.relationship_reason then 'Relacionamento ' else '' end,case when p.ticket_volume_reason then 'Volume de chamados' else '' end),auth.uid(),actor_name
  from public.regional_monthly_plans p where p.period=month_start and p.client_id=any(post_ids);
  select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) into result from public.regional_monthly_plans p where p.period=month_start and p.client_id=any(post_ids) and p.active;
  return result;
end $$;
revoke all on function public.set_regional_month_plan_v2(date,text,uuid[],text,text,boolean,boolean) from public;
grant execute on function public.set_regional_month_plan_v2(date,text,uuid[],text,text,boolean,boolean) to authenticated;

create or replace function public.submit_regional_check(target_visit uuid,details jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.visits; result public.regional_visit_checks; actor_name text; email_required boolean;
begin
  if not coalesce(public.has_permission('record_visits'),false) then raise exception 'Sem alçada para registrar visitas.'; end if;
  select * into v from public.visits where id=target_visit for update;
  if not found or v.status::text<>'Realizada' or v.archived_at is not null then raise exception 'Selecione uma visita realizada.'; end if;
  if not public.can_view_client_id(v.client_id) then raise exception 'Sem acesso ao posto.'; end if;
  if v.representative_id<>auth.uid() and not public.is_admin_or_manager() then raise exception 'Somente o autor ou a gestão pode preencher o registro.'; end if;
  if exists(select 1 from public.regional_visit_checks where visit_id=target_visit and status='Aprovada') then raise exception 'Visita aprovada: a gestão deve solicitar ajuste antes de editar.'; end if;
  email_required=public.normalize_regional_at_name(v.original_representative_name) like 'leonardo%' or public.normalize_regional_at_name(v.original_representative_name) like 'octavio%';
  if email_required and (not coalesce((details->>'email_formalized')::boolean,false) or coalesce(details->>'email_recipient','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then raise exception 'Confirme a formalização e o e-mail do anfitrião.'; end if;
  if exists(select 1 from unnest(array['misuse','training','improvements','actions']) key where coalesce(trim(details->>key),'')='') then raise exception 'Complete a pauta e os encaminhamentos.'; end if;
  select full_name into actor_name from public.profiles where id=auth.uid();
  insert into public.regional_visit_checks(visit_id,operations_contact,duration_minutes,misuse,training,improvements,actions,email_recipient,email_formalized,travel_amount,travel_note)
  values(target_visit,coalesce((details->>'operations_contact')::boolean,false),(details->>'duration_minutes')::integer,trim(details->>'misuse'),trim(details->>'training'),trim(details->>'improvements'),trim(details->>'actions'),trim(coalesce(details->>'email_recipient','')),coalesce((details->>'email_formalized')::boolean,false),greatest(coalesce((details->>'travel_amount')::numeric,0),0),trim(coalesce(details->>'travel_note','')))
  on conflict(visit_id) do update set operations_contact=excluded.operations_contact,duration_minutes=excluded.duration_minutes,misuse=excluded.misuse,training=excluded.training,improvements=excluded.improvements,actions=excluded.actions,email_recipient=excluded.email_recipient,email_formalized=excluded.email_formalized,travel_amount=excluded.travel_amount,travel_note=excluded.travel_note,travel_approved=false,status='Pendente',review_note='',submitted_at=now(),reviewed_at=null,reviewed_by=null,payment_status='Pendente',payment_sent_at=null,payment_sent_by=null,paid_at=null returning * into result;
  insert into public.regional_visit_events(visit_id,event_type,actor_id,actor_name) values(target_visit,'Enviada para validação',auth.uid(),coalesce(actor_name,'Usuário'));
  return to_jsonb(result);
end $$;

create or replace function public.review_regional_check(target_visit uuid,approve boolean,reason text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.visits; r public.regional_visit_checks; actor_name text; email_required boolean; non_billable boolean;
begin
  if not public.can_validate_regional_visits() then raise exception 'Somente Luana pode validar as visitas.'; end if;
  select full_name into actor_name from public.profiles where id=auth.uid();
  perform pg_advisory_xact_lock(20261027);
  select * into v from public.visits where id=target_visit for update;
  select * into r from public.regional_visit_checks where visit_id=target_visit for update;
  if not found then raise exception 'Registro de validação não encontrado.'; end if;
  email_required=public.normalize_regional_at_name(v.original_representative_name) like 'leonardo%' or public.normalize_regional_at_name(v.original_representative_name) like 'octavio%';
  non_billable=public.normalize_regional_at_name(v.original_representative_name) like 'leonardo%' or public.normalize_regional_at_name(v.original_representative_name) like 'octavio%' or public.normalize_regional_at_name(v.original_representative_name) like 'luana%';
  if approve then
    if v.status::text<>'Realizada' or v.archived_at is not null or trim(coalesce(v.received_by,''))='' or not r.operations_contact or not coalesce(v.viewed_ticket_report,false) or trim(coalesce(v.topics_and_solutions,''))='' then raise exception 'Corrija o registro e confirme o contato de operações.'; end if;
    if r.duration_minutes not between 1 and 15 or trim(r.misuse)='' or trim(r.training)='' or trim(r.improvements)='' or trim(r.actions)='' then raise exception 'Complete a duração, pauta e encaminhamentos.'; end if;
    if email_required and (not r.email_formalized or coalesce(r.email_recipient,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then raise exception 'A formalização por e-mail precisa ser confirmada.'; end if;
    if not exists(select 1 from public.regional_monthly_plans p where p.active and p.client_id=v.client_id and p.period=date_trunc('month',v.visit_date)::date and public.normalize_regional_at_name(p.regional_name)=public.normalize_regional_at_name(v.original_representative_name)) then raise exception 'Inclua o posto no planejamento do Regional antes de validar.'; end if;
  elsif trim(coalesce(reason,''))='' then raise exception 'Informe o ajuste necessário.';
  end if;
  update public.regional_visit_checks set status=case when approve then 'Aprovada' else 'Ajustar' end,review_note=case when approve then '' else trim(reason) end,reviewed_at=now(),reviewed_by=auth.uid(),travel_approved=approve and travel_amount>0,payment_status=case when approve and non_billable then 'Não se aplica' else 'Pendente' end,payment_sent_at=null,payment_sent_by=null,paid_at=null where visit_id=target_visit returning * into r;
  insert into public.regional_visit_events(visit_id,event_type,note,actor_id,actor_name) values(target_visit,case when approve then 'Visita validada' else 'Ajuste solicitado' end,case when approve then '' else trim(reason) end,auth.uid(),coalesce(actor_name,'Luana'));
  return to_jsonb(r);
end $$;

create or replace function public.set_regional_payment_status(target_visit uuid,new_status text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result public.regional_visit_checks; actor_name text;
begin
  select p.full_name into actor_name from public.profiles p where p.id=auth.uid() and p.active and p.role::text in ('admin','manager');
  if actor_name is null then raise exception 'Somente a gestão controla pagamentos.'; end if;
  if new_status not in ('Pendente','NF Solicitada','NF Recebida','Enviado ao Financeiro','Pago') then raise exception 'Situação de pagamento inválida.'; end if;
  update public.regional_visit_checks set payment_status=new_status,payment_sent_at=case when new_status in ('Enviado ao Financeiro','Pago') then coalesce(payment_sent_at,now()) else payment_sent_at end,payment_sent_by=case when new_status in ('Enviado ao Financeiro','Pago') then auth.uid() else payment_sent_by end,paid_at=case when new_status='Pago' then now() else null end
  where visit_id=target_visit and status='Aprovada' and payment_status<>'Não se aplica' returning * into result;
  if result.visit_id is null then raise exception 'A visita precisa estar validada e elegível para pagamento.'; end if;
  insert into public.regional_visit_events(visit_id,event_type,note,actor_id,actor_name) values(target_visit,'Pagamento atualizado',new_status,auth.uid(),actor_name);
  return to_jsonb(result);
end $$;

revoke all on function public.submit_regional_check(uuid,jsonb),public.review_regional_check(uuid,boolean,text),public.set_regional_payment_status(uuid,text) from public;
grant execute on function public.submit_regional_check(uuid,jsonb),public.review_regional_check(uuid,boolean,text),public.set_regional_payment_status(uuid,text) to authenticated;

