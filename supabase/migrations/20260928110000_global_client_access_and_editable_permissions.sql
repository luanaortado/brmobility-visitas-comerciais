-- Todos os usuários ativos enxergam toda a carteira. As alçadas controlam ações,
-- não quais clientes aparecem.
create or replace function public.can_view_client(target public.clients)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select p.active from public.profiles p where p.id=auth.uid()),false)
$$;

-- Preserva o comportamento atual de gestores antes de tornar as permissões
-- individuais efetivamente editáveis.
update public.profiles
set can_view_financial=true,
    can_edit_financial=true,
    can_view_contract_value=true,
    can_edit_profile=true,
    can_edit_contacts=true,
    can_record_visits=true
where role in ('manager','supervisor');

update public.profiles
set can_edit_financial=false,
    can_edit_profile=false,
    can_edit_contacts=false,
    can_record_visits=false
where role='viewer';

create or replace function public.has_permission(permission_name text)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(p.active and case
    when p.role='admin' then true
    when p.role='viewer' and permission_name not in ('view_financial','view_contract_value') then false
    when permission_name='view_financial' then p.can_view_financial
    when permission_name='edit_financial' then p.can_edit_financial
    when permission_name='view_contract_value' then p.can_view_contract_value
    when permission_name='edit_profile' then p.can_edit_profile
    when permission_name='edit_contacts' then p.can_edit_contacts
    when permission_name='record_visits' then p.can_record_visits
    else false end,false)
  from public.profiles p where p.id=auth.uid()
$$;

create or replace function public.admin_update_user_access(
  target_profile_id uuid,
  new_role public.app_role,
  new_active boolean,
  new_can_view_financial boolean,
  new_can_edit_financial boolean,
  new_can_view_contract_value boolean,
  new_can_edit_profile boolean,
  new_can_edit_contacts boolean,
  new_can_record_visits boolean
)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.current_profile_role() <> 'admin' then
    raise exception 'Apenas administradores podem alterar alçadas.';
  end if;
  if target_profile_id=auth.uid() and (new_role <> 'admin' or not new_active) then
    raise exception 'O administrador não pode remover o próprio acesso.';
  end if;

  update public.profiles set
    role=new_role,
    active=new_active,
    can_view_financial=new_can_view_financial,
    can_edit_financial=case when new_role='viewer' then false else new_can_edit_financial end,
    can_view_contract_value=new_can_view_contract_value,
    can_edit_profile=case when new_role='viewer' then false else new_can_edit_profile end,
    can_edit_contacts=case when new_role='viewer' then false else new_can_edit_contacts end,
    can_record_visits=case when new_role='viewer' then false else new_can_record_visits end,
    deactivated_at=case when new_active then null else coalesce(deactivated_at,now()) end,
    updated_at=now()
  where id=target_profile_id;

  if not found then raise exception 'Usuário não encontrado.'; end if;
end $$;

revoke all on function public.admin_update_user_access(uuid,public.app_role,boolean,boolean,boolean,boolean,boolean,boolean,boolean) from public;
grant execute on function public.admin_update_user_access(uuid,public.app_role,boolean,boolean,boolean,boolean,boolean,boolean,boolean) to authenticated;
