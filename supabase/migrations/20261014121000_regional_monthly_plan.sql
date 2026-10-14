-- Planejamento explícito por AT, posto e competência.
create table public.regional_monthly_plans (
 id uuid primary key default gen_random_uuid(),
 period date not null check (extract(day from period)=1),
 client_id uuid not null references public.clients(id) on delete restrict,
 regional_name text not null check(trim(regional_name)<>''),
 planned_date date not null,
 active boolean not null default true,
 updated_by uuid not null references public.profiles(id),
 updated_at timestamptz not null default now(),
 unique(period,client_id),
 check(date_trunc('month',planned_date)::date=period)
);
alter table public.regional_monthly_plans enable row level security;
create policy regional_plans_read on public.regional_monthly_plans for select to authenticated
using (public.can_view_client_id(client_id));
grant select on public.regional_monthly_plans to authenticated;
revoke insert,update,delete on public.regional_monthly_plans from authenticated,anon;

create function public.set_regional_month_plan(month_start date,at_name text,post_ids uuid[],visit_day date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
 if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.role::text in ('admin','manager')) then raise exception 'Somente a gestão define os postos do mês.'; end if;
 if month_start is null or visit_day is null or date_trunc('month',month_start)::date<>month_start or date_trunc('month',visit_day)::date<>month_start or coalesce(trim(at_name),'')='' or coalesce(cardinality(post_ids),0)=0 then raise exception 'Informe mês, AT, postos e data prevista no mês.'; end if;
 perform pg_advisory_xact_lock(20261014);
 if exists(select 1 from unnest(post_ids) id where not exists(select 1 from public.clients c where c.id=id and upper(c.state) in ('PE','PA','CE','BA','GO','DF') and public.can_view_client_id(c.id))) then raise exception 'Posto fora das regionais configuradas ou sem acesso.'; end if;
 if exists(select 1 from public.visits v join public.regional_visit_checks r on r.visit_id=v.id where v.client_id=any(post_ids) and date_trunc('month',v.visit_date)::date=month_start and r.status='Aprovada') then raise exception 'Solicite ajuste das visitas aprovadas antes de alterar seu planejamento.'; end if;
 insert into public.regional_monthly_plans(period,client_id,regional_name,planned_date,updated_by)
 select month_start,id,trim(at_name),visit_day,auth.uid() from (select distinct unnest(post_ids) id) selected
 on conflict(period,client_id) do update set regional_name=excluded.regional_name,planned_date=excluded.planned_date,active=true,updated_by=auth.uid(),updated_at=now();
 select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) into result from public.regional_monthly_plans p where p.period=month_start and p.client_id=any(post_ids) and p.active;
 return result;
end $$;

create function public.remove_regional_month_plan(month_start date,post_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.role::text in ('admin','manager')) then raise exception 'Somente a gestão define os postos do mês.'; end if;
 perform pg_advisory_xact_lock(20261014);
 if exists(select 1 from public.visits v join public.regional_visit_checks r on r.visit_id=v.id where v.client_id=post_id and date_trunc('month',v.visit_date)::date=month_start and r.status='Aprovada') then raise exception 'Solicite ajuste das visitas aprovadas antes de retirar o posto.'; end if;
 update public.regional_monthly_plans set active=false,updated_by=auth.uid(),updated_at=now() where period=month_start and client_id=post_id;
end $$;
revoke all on function public.set_regional_month_plan(date,text,uuid[],date),public.remove_regional_month_plan(date,uuid) from public;
grant execute on function public.set_regional_month_plan(date,text,uuid[],date),public.remove_regional_month_plan(date,uuid) to authenticated;

create function public.normalize_regional_at_name(value text)
returns text language sql immutable strict as $$
  select trim(regexp_replace(
    translate(lower(trim(value)), 'áàãâäéèêëíìîïóòõôöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'),
    '[^a-z0-9]+', ' ', 'g'
  ))
$$;

create function public.review_regional_check(target_visit uuid,approve boolean,reason text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.visits; r public.regional_visit_checks;
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.role::text in ('admin','manager')) then raise exception 'Somente a gestão valida as visitas.'; end if;
  -- Serializa aprovações para evitar duas liberações do mesmo posto/mês.
  perform pg_advisory_xact_lock(20261014);
  select * into v from public.visits where id=target_visit for update;
  select * into r from public.regional_visit_checks where visit_id=target_visit for update;
  if not found then raise exception 'Checklist não encontrado.'; end if;
  if approve then
    if not exists(select 1 from public.clients c where c.id=v.client_id and upper(c.state) in ('PE','PA','CE','BA','GO','DF')) then raise exception 'Posto fora das regionais configuradas.'; end if;
    if v.status::text<>'Realizada' or v.archived_at is not null or coalesce(v.meeting_mode::text,'Presencial')<>'Presencial' or trim(coalesce(v.received_by,''))='' or coalesce(v.received_by_role::text,'') not in ('Gestor','Supervisor') or not r.operations_contact or not coalesce(v.viewed_ticket_report,false) or trim(coalesce(v.topics_and_solutions,''))='' or (v.has_complaint and trim(coalesce(v.complaint_description,''))='') then raise exception 'Corrija o registro da visita e confirme o contato de operações.'; end if;
    if not exists(select 1 from public.regional_monthly_plans p where p.active and p.client_id=v.client_id and p.period=date_trunc('month',v.visit_date)::date and public.normalize_regional_at_name(p.regional_name)=public.normalize_regional_at_name(v.original_representative_name)) then raise exception 'Inclua o posto no planejamento do AT responsável antes de validar.'; end if;
    if exists(select 1 from public.regional_visit_checks x join public.visits other on other.id=x.visit_id where x.status='Aprovada' and other.client_id=v.client_id and date_trunc('month',other.visit_date)=date_trunc('month',v.visit_date) and other.id<>v.id) then raise exception 'Já existe uma visita aprovada para este posto no mês.'; end if;
  elsif trim(coalesce(reason,''))='' then raise exception 'Informe o ajuste necessário.';
  end if;
  update public.regional_visit_checks set status=case when approve then 'Aprovada' else 'Ajustar' end,review_note=case when approve then '' else trim(reason) end,reviewed_at=now(),reviewed_by=auth.uid() where visit_id=target_visit returning * into r;
  return to_jsonb(r);
end $$;
revoke all on function public.normalize_regional_at_name(text),public.review_regional_check(uuid,boolean,text) from public;
grant execute on function public.review_regional_check(uuid,boolean,text) to authenticated;
