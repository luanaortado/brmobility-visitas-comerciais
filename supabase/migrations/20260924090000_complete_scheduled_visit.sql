-- Converte o compromisso existente em visita realizada e mantém os efeitos do registro.
create or replace function public.apply_visit_effects()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='Realizada' and (tg_op='INSERT' or old.status is distinct from 'Realizada') then
    update public.clients set relationship=new.relationship, updated_at=now() where id=new.client_id;
    if new.next_visit_date is not null then
      insert into public.visits(client_id,representative_id,visit_date,status,received_by,received_by_role,relationship,topics_and_solutions,original_representative_name)
      values(new.client_id,new.representative_id,new.next_visit_date,'Programada','A confirmar','Gestor',new.relationship,'Visita gerada automaticamente',new.original_representative_name);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists apply_visit_effects on public.visits;
create trigger apply_visit_effects
after insert or update of status on public.visits
for each row execute function public.apply_visit_effects();
