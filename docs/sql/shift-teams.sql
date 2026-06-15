-- Shift Teams support for User Management
-- Run this in the same Supabase project used by the suite.

alter table if exists public.pw_profiles
  add column if not exists shift_team text;

alter table if exists public.pw_requests
  add column if not exists shift_team text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pw_profiles_shift_team_check'
  ) then
    alter table public.pw_profiles
      add constraint pw_profiles_shift_team_check
      check (shift_team is null or shift_team in ('A','B','C','D','E'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pw_requests_shift_team_check'
  ) then
    alter table public.pw_requests
      add constraint pw_requests_shift_team_check
      check (shift_team is null or shift_team in ('A','B','C','D','E'));
  end if;
end $$;

create index if not exists pw_profiles_shift_team_idx on public.pw_profiles(shift_team);
create index if not exists pw_requests_shift_team_idx on public.pw_requests(shift_team);
