create or replace function public.update_client_management_profile(
  target_client_id uuid,
  new_relationship public.relationship_level,
  new_financial public.financial_status,
  new_training text,
  new_account_manager text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_or_manager() then
    raise exception 'Apenas administradores e gestores podem alterar o perfil gerencial.';
  end if;

  if new_training not in ('Sim', 'Não') then
    raise exception 'Treinamento deve ser Sim ou Não.';
  end if;

  if nullif(trim(new_account_manager), '') is null then
    raise exception 'O responsável comercial é obrigatório.';
  end if;

  update public.clients
  set relationship = new_relationship,
      financial_status = new_financial,
      training = new_training,
      current_account_manager = trim(new_account_manager),
      sheet_sync_status = 'pending',
      updated_at = now()
  where id = target_client_id;

  if not found then
    raise exception 'Cliente não encontrado.';
  end if;
end;
$$;

revoke all on function public.update_client_management_profile(uuid, public.relationship_level, public.financial_status, text, text) from public;
grant execute on function public.update_client_management_profile(uuid, public.relationship_level, public.financial_status, text, text) to authenticated;
