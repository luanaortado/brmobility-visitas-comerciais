-- V1.2: planejamento mensal, validação e envio para pagamento.
alter table public.regional_monthly_plans
  add column if not exists guidance text not null default '',
  add column if not exists priority text not null default 'Normal',
  add column if not exists source text not null default 'Manual';

alter table public.regional_monthly_plans drop constraint if exists regional_monthly_plans_priority_check;
alter table public.regional_monthly_plans add constraint regional_monthly_plans_priority_check check(priority in ('Normal','Alta','Urgente'));
alter table public.regional_monthly_plans drop constraint if exists regional_monthly_plans_source_check;
alter table public.regional_monthly_plans add constraint regional_monthly_plans_source_check check(source in ('Manual','Chamados'));

alter table public.regional_visit_checks
  alter column email_recipient drop not null,
  alter column email_recipient set default '',
  alter column email_sent_on drop not null,
  alter column email_evidence drop not null,
  alter column email_evidence set default '',
  add column if not exists payment_status text not null default 'Pendente',
  add column if not exists payment_sent_at timestamptz,
  add column if not exists payment_sent_by uuid references public.profiles(id);

alter table public.regional_visit_checks drop constraint if exists regional_visit_checks_payment_status_check;
alter table public.regional_visit_checks add constraint regional_visit_checks_payment_status_check check(payment_status in ('Pendente','Enviado','Não se aplica'));

create table if not exists public.regional_visit_events (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid references public.visits(id) on delete restrict,
  plan_id uuid references public.regional_monthly_plans(id) on delete restrict,
  event_type text not null,
  note text not null default '',
  actor_id uuid not null references public.profiles(id),
  actor_name text not null,
  created_at timestamptz not null default now()
);
alter table public.regional_visit_events enable row level security;
drop policy if exists regional_visit_events_read on public.regional_visit_events;
create policy regional_visit_events_read on public.regional_visit_events for select to authenticated using (
  (visit_id is not null and exists(select 1 from public.visits v where v.id=visit_id and public.can_view_client_id(v.client_id))) or
  (plan_id is not null and exists(select 1 from public.regional_monthly_plans p where p.id=plan_id and public.can_view_client_id(p.client_id)))
);
grant select on public.regional_visit_events to authenticated;
revoke insert,update,delete on public.regional_visit_events from authenticated,anon;

create or replace function public.set_regional_month_plan_v12(month_start date,at_name text,post_ids uuid[],visit_day date,visit_guidance text default '',visit_priority text default 'Normal')
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb; actor_name text;
begin
  select p.full_name into actor_name from public.profiles p where p.id=auth.uid() and p.active and p.role::text in ('admin','manager');
  if actor_name is null then raise exception 'Somente a gestão define os postos do mês.'; end if;
  if month_start is null or visit_day is null or date_trunc('month',month_start)::date<>month_start or date_trunc('month',visit_day)::date<>month_start or coalesce(trim(at_name),'')='' or coalesce(cardinality(post_ids),0)=0 then raise exception 'Informe mês, regional, postos e data prevista no mês.'; end if;
  if visit_priority not in ('Normal','Alta','Urgente') then raise exception 'Prioridade inválida.'; end if;
  perform pg_advisory_xact_lock(20261026);
  if exists(select 1 from unnest(post_ids) id where not exists(select 1 from public.clients c where c.id=id and upper(c.state) in ('PE','PA','CE','BA','GO','DF','RJ') and public.can_view_client_id(c.id))) then raise exception 'Posto fora das regionais configuradas ou sem acesso.'; end if;
  insert into public.regional_monthly_plans(period,client_id,regional_name,planned_date,guidance,priority,source,updated_by)
  select month_start,id,trim(at_name),visit_day,trim(coalesce(visit_guidance,'')),visit_priority,'Manual',auth.uid() from (select distinct unnest(post_ids) id) selected
  on conflict(period,client_id) do update set regional_name=excluded.regional_name,planned_date=excluded.planned_date,guidance=excluded.guidance,priority=excluded.priority,source='Manual',active=true,updated_by=auth.uid(),updated_at=now();
  insert into public.regional_visit_events(plan_id,event_type,note,actor_id,actor_name)
  select p.id,'Planejamento atualizado',concat(p.regional_name,' · ',p.priority,' · ',p.planned_date),auth.uid(),actor_name from public.regional_monthly_plans p where p.period=month_start and p.client_id=any(post_ids);
  select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) into result from public.regional_monthly_plans p where p.period=month_start and p.client_id=any(post_ids) and p.active;
  return result;
end $$;
revoke all on function public.set_regional_month_plan_v12(date,text,uuid[],date,text,text) from public;
grant execute on function public.set_regional_month_plan_v12(date,text,uuid[],date,text,text) to authenticated;

create or replace function public.submit_regional_check(target_visit uuid,details jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.visits; result public.regional_visit_checks; actor_name text; email_required boolean; email_date date;
begin
  if not coalesce(public.has_permission('record_visits'),false) then raise exception 'Sem alçada para registrar visitas.'; end if;
  select * into v from public.visits where id=target_visit for update;
  if not found or v.status::text <> 'Realizada' or v.archived_at is not null then raise exception 'Selecione uma visita realizada.'; end if;
  if not coalesce(public.can_view_client_id(v.client_id),false) then raise exception 'Sem acesso ao posto.'; end if;
  if v.representative_id <> auth.uid() and not public.is_admin_or_manager() then raise exception 'Somente o autor ou a gestão pode preencher o registro.'; end if;
  if not exists(select 1 from public.clients c where c.id=v.client_id and upper(c.state) in ('PE','PA','CE','BA','GO','DF','RJ')) then raise exception 'Posto fora das regionais configuradas.'; end if;
  if exists(select 1 from public.regional_visit_checks where visit_id=target_visit and status='Aprovada') then raise exception 'Visita aprovada: a gestão deve solicitar ajuste antes de editar.'; end if;
  email_required=public.normalize_regional_at_name(v.original_representative_name) like 'leonardo%';
  email_date=nullif(details->>'email_sent_on','')::date;
  if email_date is not null and (email_date<v.visit_date or email_date>current_date) then raise exception 'Data do e-mail inválida.'; end if;
  if email_required and (coalesce(details->>'email_recipient','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or email_date is null or trim(coalesce(details->>'email_evidence',''))='') then raise exception 'Para Leonardo, informe o e-mail e o comprovante de formalização.'; end if;
  if exists(select 1 from unnest(array['misuse','training','improvements','actions']) key where coalesce(trim(details->>key),'')='') then raise exception 'Complete a pauta e os encaminhamentos.'; end if;
  select full_name into actor_name from public.profiles where id=auth.uid();
  insert into public.regional_visit_checks(visit_id,operations_contact,duration_minutes,misuse,training,improvements,actions,email_recipient,email_sent_on,email_evidence)
  values(target_visit,coalesce((details->>'operations_contact')::boolean,false),(details->>'duration_minutes')::integer,trim(details->>'misuse'),trim(details->>'training'),trim(details->>'improvements'),trim(details->>'actions'),trim(coalesce(details->>'email_recipient','')),email_date,trim(coalesce(details->>'email_evidence','')))
  on conflict(visit_id) do update set operations_contact=excluded.operations_contact,duration_minutes=excluded.duration_minutes,misuse=excluded.misuse,training=excluded.training,improvements=excluded.improvements,actions=excluded.actions,email_recipient=excluded.email_recipient,email_sent_on=excluded.email_sent_on,email_evidence=excluded.email_evidence,status='Pendente',review_note='',submitted_at=now(),reviewed_at=null,reviewed_by=null,payment_status='Pendente',payment_sent_at=null,payment_sent_by=null returning * into result;
  insert into public.regional_visit_events(visit_id,event_type,actor_id,actor_name) values(target_visit,'Enviada para validação',auth.uid(),coalesce(actor_name,'Usuário'));
  return to_jsonb(result);
end $$;

create or replace function public.review_regional_check(target_visit uuid,approve boolean,reason text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.visits; r public.regional_visit_checks; actor_name text; email_required boolean; non_billable boolean;
begin
  select p.full_name into actor_name from public.profiles p where p.id=auth.uid() and p.active and p.role::text in ('admin','manager');
  if actor_name is null then raise exception 'Somente a gestão valida as visitas.'; end if;
  perform pg_advisory_xact_lock(20261026);
  select * into v from public.visits where id=target_visit for update;
  select * into r from public.regional_visit_checks where visit_id=target_visit for update;
  if not found then raise exception 'Checklist não encontrado.'; end if;
  email_required=public.normalize_regional_at_name(v.original_representative_name) like 'leonardo%';
  select upper(c.state)='RJ' into non_billable from public.clients c where c.id=v.client_id;
  if approve then
    if v.status::text<>'Realizada' or v.archived_at is not null or coalesce(v.meeting_mode::text,'Presencial')<>'Presencial' or trim(coalesce(v.received_by,''))='' or coalesce(v.received_by_role::text,'') not in ('Gestor','Supervisor') or not r.operations_contact or not coalesce(v.viewed_ticket_report,false) or trim(coalesce(v.topics_and_solutions,''))='' or (v.has_complaint and trim(coalesce(v.complaint_description,''))='') then raise exception 'Corrija o registro da visita e confirme o contato de operações.'; end if;
    if r.duration_minutes not between 1 and 15 or trim(r.misuse)='' or trim(r.training)='' or trim(r.improvements)='' or trim(r.actions)='' then raise exception 'Complete a duração, pauta e encaminhamentos.'; end if;
    if email_required and (coalesce(r.email_recipient,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or r.email_sent_on is null or trim(coalesce(r.email_evidence,''))='') then raise exception 'O comprovante de e-mail é obrigatório para Leonardo.'; end if;
    if not exists(select 1 from public.regional_monthly_plans p where p.active and p.client_id=v.client_id and p.period=date_trunc('month',v.visit_date)::date and public.normalize_regional_at_name(p.regional_name)=public.normalize_regional_at_name(v.original_representative_name)) then raise exception 'Inclua o posto no planejamento do regional responsável antes de validar.'; end if;
  elsif trim(coalesce(reason,''))='' then raise exception 'Informe o ajuste necessário.';
  end if;
  update public.regional_visit_checks set status=case when approve then 'Aprovada' else 'Ajustar' end,review_note=case when approve then '' else trim(reason) end,reviewed_at=now(),reviewed_by=auth.uid(),payment_status=case when approve and non_billable then 'Não se aplica' when approve then 'Pendente' else 'Pendente' end,payment_sent_at=null,payment_sent_by=null where visit_id=target_visit returning * into r;
  insert into public.regional_visit_events(visit_id,event_type,note,actor_id,actor_name) values(target_visit,case when approve then 'Visita validada' else 'Ajuste solicitado' end,case when approve then '' else trim(reason) end,auth.uid(),actor_name);
  return to_jsonb(r);
end $$;

create or replace function public.mark_regional_payment_sent(target_visit uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result public.regional_visit_checks; actor_name text;
begin
  select p.full_name into actor_name from public.profiles p where p.id=auth.uid() and p.active and p.role::text in ('admin','manager');
  if actor_name is null then raise exception 'Somente a gestão controla o envio para pagamento.'; end if;
  update public.regional_visit_checks set payment_status='Enviado',payment_sent_at=now(),payment_sent_by=auth.uid()
  where visit_id=target_visit and status='Aprovada' and payment_status='Pendente' returning * into result;
  if result.visit_id is null then raise exception 'A visita precisa estar validada e elegível para pagamento.'; end if;
  insert into public.regional_visit_events(visit_id,event_type,actor_id,actor_name) values(target_visit,'Enviada para pagamento',auth.uid(),actor_name);
  return to_jsonb(result);
end $$;

revoke all on function public.submit_regional_check(uuid,jsonb),public.review_regional_check(uuid,boolean,text),public.mark_regional_payment_sent(uuid) from public;
grant execute on function public.submit_regional_check(uuid,jsonb),public.review_regional_check(uuid,boolean,text),public.mark_regional_payment_sent(uuid) to authenticated;
