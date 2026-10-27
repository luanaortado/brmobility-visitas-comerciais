-- Simplifica o fechamento regional e habilita uma prévia segura por usuário.

create or replace function public.list_view_as_users()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor_name text; result jsonb;
begin
  select public.normalize_regional_at_name(p.full_name) into actor_name
  from public.profiles p where p.id=auth.uid() and p.active;
  if actor_name is null or (actor_name not like 'luana%' and actor_name not like 'jessica%') then
    raise exception 'Somente Luana e Jéssica podem usar a visualização por usuário.';
  end if;

  with available as (
    select p.id,p.full_name,p.role::text as role,coalesce(r.states,'{}'::text[]) as states
    from public.profiles p
    left join public.regional_directory r on r.profile_id=p.id and r.active
    where p.active
    union all
    select r.id,r.full_name,'representative',r.states
    from public.regional_directory r
    where r.active and r.profile_id is null
  )
  select coalesce(jsonb_agg(to_jsonb(available) order by full_name),'[]'::jsonb) into result from available;
  return result;
end $$;

revoke all on function public.list_view_as_users() from public;
grant execute on function public.list_view_as_users() to authenticated;

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
  if exists(select 1 from unnest(array['misuse','training','improvements','actions']) key where coalesce(trim(details->>key),'')='') then raise exception 'Selecione uma resposta para cada item do complemento.'; end if;
  select full_name into actor_name from public.profiles where id=auth.uid();
  insert into public.regional_visit_checks(visit_id,operations_contact,duration_minutes,misuse,training,improvements,actions,email_recipient,email_formalized,travel_amount,travel_note)
  values(target_visit,coalesce((details->>'operations_contact')::boolean,false),0,trim(details->>'misuse'),trim(details->>'training'),trim(details->>'improvements'),trim(details->>'actions'),trim(coalesce(details->>'email_recipient','')),coalesce((details->>'email_formalized')::boolean,false),greatest(coalesce((details->>'travel_amount')::numeric,0),0),trim(coalesce(details->>'travel_note','')))
  on conflict(visit_id) do update set operations_contact=excluded.operations_contact,duration_minutes=0,misuse=excluded.misuse,training=excluded.training,improvements=excluded.improvements,actions=excluded.actions,email_recipient=excluded.email_recipient,email_formalized=excluded.email_formalized,travel_amount=excluded.travel_amount,travel_note=excluded.travel_note,travel_approved=false,status='Pendente',review_note='',submitted_at=now(),reviewed_at=null,reviewed_by=null,payment_status='Pendente',payment_sent_at=null,payment_sent_by=null,paid_at=null returning * into result;
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
    if trim(r.misuse)='' or trim(r.training)='' or trim(r.improvements)='' or trim(r.actions)='' then raise exception 'Complete a pauta e os encaminhamentos.'; end if;
    if email_required and (not r.email_formalized or coalesce(r.email_recipient,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then raise exception 'A formalização por e-mail precisa ser confirmada.'; end if;
    if not exists(select 1 from public.regional_monthly_plans p where p.active and p.client_id=v.client_id and p.period=date_trunc('month',v.visit_date)::date and public.normalize_regional_at_name(p.regional_name)=public.normalize_regional_at_name(v.original_representative_name)) then raise exception 'Inclua o posto no planejamento do Regional antes de validar.'; end if;
  elsif trim(coalesce(reason,''))='' then raise exception 'Informe o ajuste necessário.';
  end if;
  update public.regional_visit_checks set status=case when approve then 'Aprovada' else 'Ajustar' end,review_note=case when approve then '' else trim(reason) end,reviewed_at=now(),reviewed_by=auth.uid(),travel_approved=approve and travel_amount>0,payment_status=case when approve and non_billable then 'Não se aplica' else 'Pendente' end,payment_sent_at=null,payment_sent_by=null,paid_at=null where visit_id=target_visit returning * into r;
  insert into public.regional_visit_events(visit_id,event_type,note,actor_id,actor_name) values(target_visit,case when approve then 'Visita validada' else 'Ajuste solicitado' end,case when approve then '' else trim(reason) end,auth.uid(),coalesce(actor_name,'Luana'));
  return to_jsonb(r);
end $$;

revoke all on function public.submit_regional_check(uuid,jsonb),public.review_regional_check(uuid,boolean,text) from public;
grant execute on function public.submit_regional_check(uuid,jsonb),public.review_regional_check(uuid,boolean,text) to authenticated;
