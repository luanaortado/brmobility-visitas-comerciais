-- Fechamento regionais: não altera dados anteriores.
create table public.regional_visit_checks (
  visit_id uuid primary key references public.visits(id) on delete restrict,
  operations_contact boolean not null default false,
  duration_minutes integer not null check(duration_minutes between 1 and 15),
  misuse text not null, training text not null, improvements text not null, actions text not null,
  email_recipient text not null, email_sent_on date not null, email_evidence text not null,
  status text not null default 'Pendente' check(status in ('Pendente','Ajustar','Aprovada')),
  review_note text not null default '', submitted_at timestamptz not null default now(),
  reviewed_at timestamptz, reviewed_by uuid references public.profiles(id)
);
alter table public.regional_visit_checks enable row level security;
create policy regional_checks_read on public.regional_visit_checks for select to authenticated
using (exists(select 1 from public.visits v where v.id=visit_id and public.can_view_client_id(v.client_id)));
grant select on public.regional_visit_checks to authenticated;
revoke insert,update,delete on public.regional_visit_checks from authenticated,anon;

create function public.submit_regional_check(target_visit uuid,details jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.visits; result public.regional_visit_checks;
begin
  if not coalesce(public.has_permission('record_visits'),false) then raise exception 'Sem alçada para registrar visitas.'; end if;
  select * into v from public.visits where id=target_visit for update;
  if not found or v.status::text <> 'Realizada' or v.archived_at is not null then raise exception 'Selecione uma visita realizada.'; end if;
  if not coalesce(public.can_view_client_id(v.client_id),false) then raise exception 'Sem acesso ao posto.'; end if;
  if v.representative_id <> auth.uid() and not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.role::text in ('admin','manager')) then raise exception 'Somente o autor ou a gestão pode preencher o checklist.'; end if;
  if not exists(select 1 from public.clients c where c.id=v.client_id and upper(c.state) in ('PE','PA','CE','BA','GO','DF')) then raise exception 'Posto fora das regionais configuradas.'; end if;
  if exists(select 1 from public.regional_visit_checks where visit_id=target_visit and status='Aprovada') then raise exception 'Visita aprovada: a gestão deve solicitar ajuste antes de editar.'; end if;
  if (details->>'email_sent_on')::date < v.visit_date or (details->>'email_sent_on')::date > current_date then raise exception 'Data do e-mail inválida.'; end if;
  if coalesce(details->>'email_recipient','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Informe o e-mail do anfitrião.'; end if;
  if exists(select 1 from unnest(array['misuse','training','improvements','actions','email_evidence']) key where coalesce(trim(details->>key),'')='') then raise exception 'Complete a pauta e o comprovante do e-mail.'; end if;
  insert into public.regional_visit_checks(visit_id,operations_contact,duration_minutes,misuse,training,improvements,actions,email_recipient,email_sent_on,email_evidence)
  values(target_visit,coalesce((details->>'operations_contact')::boolean,false),(details->>'duration_minutes')::integer,trim(details->>'misuse'),trim(details->>'training'),trim(details->>'improvements'),trim(details->>'actions'),trim(details->>'email_recipient'),(details->>'email_sent_on')::date,trim(details->>'email_evidence'))
  on conflict(visit_id) do update set operations_contact=excluded.operations_contact,duration_minutes=excluded.duration_minutes,misuse=excluded.misuse,training=excluded.training,improvements=excluded.improvements,actions=excluded.actions,email_recipient=excluded.email_recipient,email_sent_on=excluded.email_sent_on,email_evidence=excluded.email_evidence,status='Pendente',review_note='',submitted_at=now(),reviewed_at=null,reviewed_by=null returning * into result;
  return to_jsonb(result);
end $$;

create function public.protect_approved_regional_visit() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if exists(select 1 from public.regional_visit_checks where visit_id=old.id and status='Aprovada') and row(new.client_id,new.representative_id,new.visit_date,new.status,new.received_by,new.received_by_role,new.viewed_ticket_report,new.has_complaint,new.complaint_description,new.topics_and_solutions,new.meeting_mode,new.archived_at) is distinct from row(old.client_id,old.representative_id,old.visit_date,old.status,old.received_by,old.received_by_role,old.viewed_ticket_report,old.has_complaint,old.complaint_description,old.topics_and_solutions,old.meeting_mode,old.archived_at) then raise exception 'A gestão deve pedir ajuste no fechamento antes de alterar uma visita aprovada.'; end if;
  return new;
end $$;
create trigger protect_approved_regional_visit before update on public.visits for each row execute function public.protect_approved_regional_visit();
revoke all on function public.submit_regional_check(uuid,jsonb), public.protect_approved_regional_visit() from public;
grant execute on function public.submit_regional_check(uuid,jsonb) to authenticated;
