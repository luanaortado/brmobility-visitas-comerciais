alter type public.visit_motive add value if not exists 'Reversão de Cancelamento';

create or replace function public.update_client_trello_link(target_client_id uuid, new_trello_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_url text := nullif(trim(coalesce(new_trello_url, '')), '');
begin
  if not public.can_view_client((select c from public.clients c where c.id = target_client_id))
    or not public.has_permission('edit_profile') then
    raise exception 'Sem permissão para editar este perfil.';
  end if;

  if normalized_url is not null and normalized_url !~* '^https?://' then
    raise exception 'Informe um link válido do Trello.';
  end if;

  update public.clients
  set trello_url = normalized_url,
      sync_source = 'app',
      sync_updated_at = now(),
      updated_at = now()
  where id = target_client_id;

  if not found then raise exception 'Cliente não encontrado.'; end if;
end;
$$;

revoke all on function public.update_client_trello_link(uuid, text) from public, anon;
grant execute on function public.update_client_trello_link(uuid, text) to authenticated;
