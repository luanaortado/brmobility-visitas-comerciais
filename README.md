# BRMobility — Perfil do Cliente e Visitas Comerciais V1.1

V1 do painel comercial da BRMobility, com React, Supabase/PostgreSQL e publicação preparada para Netlify.

## O que está pronto

- autenticação por e-mail e redefinição segura de senha;
- carteira filtrada por cliente, UF, região, responsável ou liberação individual;
- perfil do cliente com contrato, operação, financeiro, contato e links externos;
- edição do contato principal com sincronização para a aba `Perfil do Cliente`;
- auditoria de inclusões e alterações, incluindo valor anterior, novo valor, usuário e horário;
- formulário e histórico de visitas, com reclamação condicional e atualização do relacionamento;
- geração automática da próxima visita na agenda;
- dashboard de visitas, relacionamento, financeiro e clientes em atenção;
- administração de usuários e alçadas com convites por link — sem senhas definitivas no chat;
- histórico de responsáveis preservado por intervalos de vigência.
- visão “30 segundos” com atalhos Trello/Chamados, contato acionável e datas em mês/ano;
- múltiplos contatos, timeline única, motivo da visita e oportunidades;
- sincronização bidirecional por UUID permanente, fila anti-loop e última alteração válida;
- permissões separadas para financeiro, valor contratual, perfil, contatos e visitas;
- dashboard de cobertura com indicadores clicáveis e interface mobile-first.

## Segurança dos dados

Os 126 registros reais importados da planilha ficam apenas em `supabase/import/clients.json`, arquivo ignorado pelo Git. A demonstração pública usa dados ilustrativos. A produção consulta o Supabase após autenticação, com Row Level Security em todas as tabelas sensíveis.

## Configuração

1. Crie um projeto Supabase e aplique as migrations em ordem, incluindo `20260918150000_v1_1.sql`.
2. Copie `.env.example` para `.env.local` e preencha a URL e a chave pública do projeto.
3. Compartilhe a planilha com o e-mail da conta de serviço do Google com permissão de edição.
4. Cadastre os segredos das Edge Functions: `GOOGLE_SERVICE_ACCOUNT_EMAIL`, `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY`, `GOOGLE_SHEET_ID`, `GOOGLE_SHEET_TAB`, `SHEET_SYNC_SECRET` e `APP_ORIGIN`.
5. Publique as funções `sync-client`, `pull-sheet`, `backfill-sheet-ids` e `invite-user`. Execute `backfill-sheet-ids` uma vez e programe `pull-sheet` (ou conecte-o a um webhook da planilha).
6. Com a chave de serviço apenas no terminal local, execute `pnpm import:clients` para carregar a base inicial.
7. No Netlify, configure somente `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY`. Nunca configure a chave `service_role` como variável `VITE_*`.

## Desenvolvimento

```bash
pnpm install
pnpm dev
pnpm build
pnpm lint
```

O arquivo `netlify.toml` já inclui fallback de SPA e cabeçalhos de segurança.

## Primeira administradora

Crie o primeiro usuário pelo painel do Supabase e ajuste o perfil correspondente:

```sql
update public.profiles set role = 'admin' where email = 'email-da-administradora';
```

Depois, novos usuários devem ser convidados pela área **Usuários e alçadas**, recebendo um link temporário para definir a própria senha.
