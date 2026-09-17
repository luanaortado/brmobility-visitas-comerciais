# BRMobility — Perfil do Cliente e Visitas Comerciais

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

## Segurança dos dados

Os 126 registros reais importados da planilha ficam apenas em `supabase/import/clients.json`, arquivo ignorado pelo Git. A demonstração pública usa dados ilustrativos. A produção consulta o Supabase após autenticação, com Row Level Security em todas as tabelas sensíveis.

## Configuração

1. Crie um projeto Supabase e execute `supabase/migrations/20260917120000_initial.sql` no SQL Editor.
2. Copie `.env.example` para `.env.local` e preencha a URL e a chave pública do projeto.
3. Compartilhe a planilha com o e-mail da conta de serviço do Google com permissão de edição.
4. Cadastre os segredos das Edge Functions: `GOOGLE_SERVICE_ACCOUNT_EMAIL`, `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY`, `GOOGLE_SHEET_ID` e `APP_ORIGIN`.
5. Publique as funções `sync-contact` e `invite-user`.
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
