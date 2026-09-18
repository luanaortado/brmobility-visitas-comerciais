-- PostgreSQL requires a commit before a newly-added enum value can be used.
alter type public.client_scope_type add value if not exists 'administrator';
