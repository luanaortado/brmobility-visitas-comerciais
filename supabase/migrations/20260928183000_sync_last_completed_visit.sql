-- Keep the client's last completed visit in sync with the visit history.
-- The text column is retained for compatibility with the original spreadsheet.
create or replace function public.refresh_client_last_visit()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  target_client_id uuid;
  latest_visit date;
begin
  target_client_id := coalesce(new.client_id, old.client_id);

  select max(v.visit_date)
    into latest_visit
  from public.visits v
  where v.client_id=target_client_id
    and v.status='Realizada'
    and v.archived_at is null;

  update public.clients
     set legacy_last_contact=latest_visit::text,
         sheet_sync_status='pending',
         sync_source='app',
         sync_updated_at=now(),
         updated_at=now()
   where id=target_client_id
     and legacy_last_contact is distinct from latest_visit::text;

  return coalesce(new,old);
end $$;

drop trigger if exists refresh_client_last_visit_after_write on public.visits;
create trigger refresh_client_last_visit_after_write
after insert or update of client_id,visit_date,status,archived_at on public.visits
for each row execute function public.refresh_client_last_visit();

create or replace function public.queue_client_sheet_sync()
returns trigger language plpgsql security definer set search_path=public as $$
declare f text;
begin
  if new.sync_source<>'app' then return new; end if;
  foreach f in array array['relationship','financial_status','training','current_account_manager','last_fleet_change','legacy_last_contact','primary_contact_name','primary_contact_role','primary_contact_phone','primary_contact_email'] loop
    if to_jsonb(new)->f is distinct from to_jsonb(old)->f then
      update public.sheet_sync_queue set status='superseded' where client_id=new.id and field_name=f and status='pending';
      insert into public.sheet_sync_queue(client_id,field_name,field_value,source_updated_at) values(new.id,f,to_jsonb(new)->f,new.sync_updated_at);
    end if;
  end loop;
  return new;
end $$;

-- Repair clients that already have completed visits, including Bangu and Barra.
with latest as (
  select client_id,max(visit_date) as visit_date
  from public.visits
  where status='Realizada' and archived_at is null
  group by client_id
)
update public.clients c
   set legacy_last_contact=l.visit_date::text,
       sheet_sync_status='pending',
       sync_source='app',
       sync_updated_at=now(),
       updated_at=now()
  from latest l
 where c.id=l.client_id
   and c.legacy_last_contact is distinct from l.visit_date::text;
