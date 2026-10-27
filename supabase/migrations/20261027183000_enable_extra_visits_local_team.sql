-- Octávio e Leonardo podem agendar e registrar visitas além do planejamento mensal.

update public.profiles
set can_record_visits=true,
    updated_at=now()
where active
  and (
    lower(email) in ('comercial@brmobility.com.br','comercialrj@brmobility.com.br')
    or public.normalize_regional_at_name(full_name) like 'octavio%'
    or public.normalize_regional_at_name(full_name) like 'leonardo%'
  );

update public.regional_directory r
set profile_id=p.id,
    updated_at=now()
from public.profiles p
where r.profile_id is null
  and lower(r.email)=lower(p.email)
  and lower(p.email) in ('comercial@brmobility.com.br','comercialrj@brmobility.com.br');

create or replace function public.review_regional_check(target_visit uuid,approve boolean,reason text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.visits; r public.regional_visit_checks; actor_name text; email_required boolean; non_billable boolean; ad_hoc_allowed boolean;
begin
  if not public.can_validate_regional_visits() then raise exception 'Somente Luana pode validar as visitas.'; end if;
  select full_name into actor_name from public.profiles where id=auth.uid();
  perform pg_advisory_xact_lock(20261027);
  select * into v from public.visits where id=target_visit for update;
  select * into r from public.regional_visit_checks where visit_id=target_visit for update;
  if not found then raise exception 'Registro de validação não encontrado.'; end if;
  email_required=public.normalize_regional_at_name(v.original_representative_name) like 'leonardo%' or public.normalize_regional_at_name(v.original_representative_name) like 'octavio%';
  ad_hoc_allowed=email_required;
  non_billable=ad_hoc_allowed or public.normalize_regional_at_name(v.original_representative_name) like 'luana%';
  if approve then
    if v.status::text<>'Realizada' or v.archived_at is not null or trim(coalesce(v.received_by,''))='' or not r.operations_contact or not coalesce(v.viewed_ticket_report,false) or trim(coalesce(v.topics_and_solutions,''))='' then raise exception 'Corrija o registro e confirme o contato de operações.'; end if;
    if trim(r.misuse)='' or trim(r.training)='' or trim(r.improvements)='' or trim(r.actions)='' then raise exception 'Complete a pauta e os encaminhamentos.'; end if;
    if email_required and (not r.email_formalized or coalesce(r.email_recipient,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then raise exception 'A formalização por e-mail precisa ser confirmada.'; end if;
    if not ad_hoc_allowed and not exists(select 1 from public.regional_monthly_plans p where p.active and p.client_id=v.client_id and p.period=date_trunc('month',v.visit_date)::date and public.normalize_regional_at_name(p.regional_name)=public.normalize_regional_at_name(v.original_representative_name)) then raise exception 'Inclua o posto no planejamento do Regional antes de validar.'; end if;
  elsif trim(coalesce(reason,''))='' then raise exception 'Informe o ajuste necessário.';
  end if;
  update public.regional_visit_checks set status=case when approve then 'Aprovada' else 'Ajustar' end,review_note=case when approve then '' else trim(reason) end,reviewed_at=now(),reviewed_by=auth.uid(),travel_approved=approve and travel_amount>0,payment_status=case when approve and non_billable then 'Não se aplica' else 'Pendente' end,payment_sent_at=null,payment_sent_by=null,paid_at=null where visit_id=target_visit returning * into r;
  insert into public.regional_visit_events(visit_id,event_type,note,actor_id,actor_name) values(target_visit,case when approve then 'Visita validada' else 'Ajuste solicitado' end,case when approve then '' else trim(reason) end,auth.uid(),coalesce(actor_name,'Luana'));
  return to_jsonb(r);
end $$;

revoke all on function public.review_regional_check(uuid,boolean,text) from public;
grant execute on function public.review_regional_check(uuid,boolean,text) to authenticated;
