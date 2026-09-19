alter table public.visits
  add column if not exists meeting_mode text not null default 'Presencial';

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname='visits_meeting_mode_check'
  ) then
    alter table public.visits add constraint visits_meeting_mode_check
    check (meeting_mode in ('Presencial','Videoconferência'));
  end if;
end $$;
