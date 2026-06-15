-- Message Board private messaging
-- Run this once in Supabase SQL editor.

create extension if not exists pgcrypto;

create table if not exists public.pw_message_board_private_threads (
  id uuid primary key default gen_random_uuid(),
  participant_a_user_id uuid not null,
  participant_b_user_id uuid not null,
  auto_delete_enabled boolean not null default false,
  auto_delete_seconds integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pw_mb_private_threads_distinct_participants
    check (participant_a_user_id <> participant_b_user_id),
  constraint pw_mb_private_threads_timer_valid
    check (
      (auto_delete_enabled = false and auto_delete_seconds is null)
      or
      (auto_delete_enabled = true and auto_delete_seconds between 60 and 604800)
    )
);

alter table public.pw_message_board_private_threads
  add column if not exists auto_delete_enabled boolean not null default false;
alter table public.pw_message_board_private_threads
  add column if not exists auto_delete_seconds integer;
alter table public.pw_message_board_private_threads
  add column if not exists created_at timestamptz not null default now();
alter table public.pw_message_board_private_threads
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists pw_mb_private_threads_pair_uidx
  on public.pw_message_board_private_threads (
    least(participant_a_user_id::text, participant_b_user_id::text),
    greatest(participant_a_user_id::text, participant_b_user_id::text)
  );

create index if not exists pw_mb_private_threads_updated_idx
  on public.pw_message_board_private_threads (updated_at desc);

create table if not exists public.pw_message_board_private_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.pw_message_board_private_threads(id) on delete cascade,
  sender_user_id uuid not null,
  message_text text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  constraint pw_mb_private_messages_not_empty check (length(trim(message_text)) > 0),
  constraint pw_mb_private_messages_expiry_after_create check (expires_at is null or expires_at > created_at)
);

alter table public.pw_message_board_private_messages
  add column if not exists expires_at timestamptz;
alter table public.pw_message_board_private_messages
  add column if not exists created_at timestamptz not null default now();

create index if not exists pw_mb_private_messages_thread_created_idx
  on public.pw_message_board_private_messages (thread_id, created_at);

create index if not exists pw_mb_private_messages_thread_sender_idx
  on public.pw_message_board_private_messages (thread_id, sender_user_id, created_at desc);

create index if not exists pw_mb_private_messages_expires_idx
  on public.pw_message_board_private_messages (expires_at);

create table if not exists public.pw_message_board_private_reads (
  thread_id uuid not null references public.pw_message_board_private_threads(id) on delete cascade,
  user_id uuid not null,
  last_read_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

alter table public.pw_message_board_private_reads
  add column if not exists created_at timestamptz not null default now();
alter table public.pw_message_board_private_reads
  add column if not exists updated_at timestamptz not null default now();

create index if not exists pw_mb_private_reads_user_idx
  on public.pw_message_board_private_reads (user_id, updated_at desc);

alter table public.pw_message_board_private_threads enable row level security;
alter table public.pw_message_board_private_messages enable row level security;
alter table public.pw_message_board_private_reads enable row level security;

grant select, insert, update, delete on public.pw_message_board_private_threads to authenticated;
grant select, insert, update, delete on public.pw_message_board_private_messages to authenticated;
grant select, insert, update, delete on public.pw_message_board_private_reads to authenticated;

create or replace function public.pw_message_board_private_user_is_admin(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select
    exists (
      select 1
      from public.pw_profiles p
      where p.id = p_user_id
        and lower(coalesce(p.role, '')) = 'admin'
    );
$$;
revoke all on function public.pw_message_board_private_user_is_admin(uuid) from public;
grant execute on function public.pw_message_board_private_user_is_admin(uuid) to authenticated;

create or replace function public.pw_message_board_private_send_message(
  p_thread_id uuid,
  p_message_text text
)
returns uuid
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_user uuid := auth.uid();
  v_thread record;
  v_other uuid;
  v_seconds integer;
  v_expires timestamptz;
  v_message_id uuid;
  v_text text := btrim(coalesce(p_message_text, ''));
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if p_thread_id is null then
    raise exception 'Thread required' using errcode = '22004';
  end if;

  if v_text = '' then
    raise exception 'Message required' using errcode = '22004';
  end if;

  select participant_a_user_id, participant_b_user_id, auto_delete_enabled, auto_delete_seconds
    into v_thread
  from public.pw_message_board_private_threads
  where id = p_thread_id;

  if not found then
    raise exception 'Thread not found' using errcode = 'P0002';
  end if;

  if v_user <> v_thread.participant_a_user_id and v_user <> v_thread.participant_b_user_id then
    raise exception 'Not a participant' using errcode = '42501';
  end if;

  v_other := case
    when v_user = v_thread.participant_a_user_id then v_thread.participant_b_user_id
    else v_thread.participant_a_user_id
  end;

  if public.pw_message_board_private_user_is_admin(v_other) then
    raise exception 'Private messages to admin accounts are not allowed.' using errcode = '42501';
  end if;

  if v_thread.auto_delete_enabled = true and v_thread.auto_delete_seconds between 60 and 604800 then
    v_seconds := v_thread.auto_delete_seconds;
    v_expires := now() + make_interval(secs => v_seconds);
  end if;

  insert into public.pw_message_board_private_messages (
    thread_id,
    sender_user_id,
    message_text,
    expires_at
  )
  values (
    p_thread_id,
    v_user,
    v_text,
    v_expires
  )
  returning id into v_message_id;

  update public.pw_message_board_private_threads
    set updated_at = now()
    where id = p_thread_id;

  return v_message_id;
end;
$$;
revoke all on function public.pw_message_board_private_send_message(uuid, text) from public;
grant execute on function public.pw_message_board_private_send_message(uuid, text) to authenticated;

drop policy if exists "pw_mb_private_threads_select" on public.pw_message_board_private_threads;
create policy "pw_mb_private_threads_select"
  on public.pw_message_board_private_threads
  for select
  to authenticated
  using (
    auth.uid() = participant_a_user_id
    or auth.uid() = participant_b_user_id
  );

drop policy if exists "pw_mb_private_threads_insert" on public.pw_message_board_private_threads;
create policy "pw_mb_private_threads_insert"
  on public.pw_message_board_private_threads
  for insert
  to authenticated
  with check (
    (auth.uid() = participant_a_user_id or auth.uid() = participant_b_user_id)
    and not public.pw_message_board_private_user_is_admin(
      case
        when auth.uid() = participant_a_user_id then participant_b_user_id
        else participant_a_user_id
      end
    )
  );

drop policy if exists "pw_mb_private_threads_update" on public.pw_message_board_private_threads;
create policy "pw_mb_private_threads_update"
  on public.pw_message_board_private_threads
  for update
  to authenticated
  using (
    auth.uid() = participant_a_user_id
    or auth.uid() = participant_b_user_id
  )
  with check (
    auth.uid() = participant_a_user_id
    or auth.uid() = participant_b_user_id
  );

drop policy if exists "pw_mb_private_threads_delete" on public.pw_message_board_private_threads;
create policy "pw_mb_private_threads_delete"
  on public.pw_message_board_private_threads
  for delete
  to authenticated
  using (
    auth.uid() = participant_a_user_id
    or auth.uid() = participant_b_user_id
  );

drop policy if exists "pw_mb_private_messages_select" on public.pw_message_board_private_messages;
create policy "pw_mb_private_messages_select"
  on public.pw_message_board_private_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.pw_message_board_private_threads t
      where t.id = pw_message_board_private_messages.thread_id
        and (auth.uid() = t.participant_a_user_id or auth.uid() = t.participant_b_user_id)
    )
  );

drop policy if exists "pw_mb_private_messages_insert" on public.pw_message_board_private_messages;
create policy "pw_mb_private_messages_insert"
  on public.pw_message_board_private_messages
  for insert
  to authenticated
  with check (
    sender_user_id = auth.uid()
    and exists (
      select 1
      from public.pw_message_board_private_threads t
      where t.id = pw_message_board_private_messages.thread_id
        and (auth.uid() = t.participant_a_user_id or auth.uid() = t.participant_b_user_id)
        and not public.pw_message_board_private_user_is_admin(
          case
            when auth.uid() = t.participant_a_user_id then t.participant_b_user_id
            else t.participant_a_user_id
          end
        )
    )
  );

drop policy if exists "pw_mb_private_messages_delete_own" on public.pw_message_board_private_messages;
create policy "pw_mb_private_messages_delete_own"
  on public.pw_message_board_private_messages
  for delete
  to authenticated
  using (
    sender_user_id = auth.uid()
    and exists (
      select 1
      from public.pw_message_board_private_threads t
      where t.id = pw_message_board_private_messages.thread_id
        and (auth.uid() = t.participant_a_user_id or auth.uid() = t.participant_b_user_id)
    )
  );

drop policy if exists "pw_mb_private_reads_select_own" on public.pw_message_board_private_reads;
create policy "pw_mb_private_reads_select_own"
  on public.pw_message_board_private_reads
  for select
  to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1
      from public.pw_message_board_private_threads t
      where t.id = pw_message_board_private_reads.thread_id
        and (auth.uid() = t.participant_a_user_id or auth.uid() = t.participant_b_user_id)
    )
  );

drop policy if exists "pw_mb_private_reads_insert_own" on public.pw_message_board_private_reads;
create policy "pw_mb_private_reads_insert_own"
  on public.pw_message_board_private_reads
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.pw_message_board_private_threads t
      where t.id = pw_message_board_private_reads.thread_id
        and (auth.uid() = t.participant_a_user_id or auth.uid() = t.participant_b_user_id)
    )
  );

drop policy if exists "pw_mb_private_reads_update_own" on public.pw_message_board_private_reads;
create policy "pw_mb_private_reads_update_own"
  on public.pw_message_board_private_reads
  for update
  to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1
      from public.pw_message_board_private_threads t
      where t.id = pw_message_board_private_reads.thread_id
        and (auth.uid() = t.participant_a_user_id or auth.uid() = t.participant_b_user_id)
    )
  )
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.pw_message_board_private_threads t
      where t.id = pw_message_board_private_reads.thread_id
        and (auth.uid() = t.participant_a_user_id or auth.uid() = t.participant_b_user_id)
    )
  );

create or replace function public.pw_message_board_private_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists pw_mb_private_threads_touch_updated_at on public.pw_message_board_private_threads;
create trigger pw_mb_private_threads_touch_updated_at
before update on public.pw_message_board_private_threads
for each row
execute function public.pw_message_board_private_touch_updated_at();

drop trigger if exists pw_mb_private_reads_touch_updated_at on public.pw_message_board_private_reads;
create trigger pw_mb_private_reads_touch_updated_at
before update on public.pw_message_board_private_reads
for each row
execute function public.pw_message_board_private_touch_updated_at();

create or replace function public.pw_message_board_private_apply_insert_timer()
returns trigger
language plpgsql
as $$
declare
  v_seconds integer;
begin
  if new.created_at is null then
    new.created_at := now();
  end if;
  if new.expires_at is not null then
    return new;
  end if;
  select auto_delete_seconds
  into v_seconds
  from public.pw_message_board_private_threads
  where id = new.thread_id
    and auto_delete_enabled = true
    and auto_delete_seconds between 60 and 604800
  limit 1;
  if v_seconds is not null then
    new.expires_at := new.created_at + make_interval(secs => v_seconds);
  end if;
  return new;
end;
$$;

drop trigger if exists pw_mb_private_messages_apply_insert_timer on public.pw_message_board_private_messages;
create trigger pw_mb_private_messages_apply_insert_timer
before insert on public.pw_message_board_private_messages
for each row
execute function public.pw_message_board_private_apply_insert_timer();

create or replace function public.pw_message_board_private_apply_thread_timer()
returns trigger
language plpgsql
as $$
begin
  if (
    old.auto_delete_enabled is distinct from new.auto_delete_enabled
    or old.auto_delete_seconds is distinct from new.auto_delete_seconds
  ) then
    if new.auto_delete_enabled = true and new.auto_delete_seconds between 60 and 604800 then
      update public.pw_message_board_private_messages
      set expires_at = created_at + make_interval(secs => new.auto_delete_seconds)
      where thread_id = new.id;
    else
      update public.pw_message_board_private_messages
      set expires_at = null
      where thread_id = new.id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pw_mb_private_threads_apply_timer on public.pw_message_board_private_threads;
create trigger pw_mb_private_threads_apply_timer
after update on public.pw_message_board_private_threads
for each row
execute function public.pw_message_board_private_apply_thread_timer();

create or replace function public.pw_message_board_private_cleanup_expired()
returns void
language sql
security definer
set search_path = public
set row_security = off
as $$
  delete from public.pw_message_board_private_messages
  where expires_at is not null
    and expires_at <= now();
$$;

revoke all on function public.pw_message_board_private_cleanup_expired() from public;
grant execute on function public.pw_message_board_private_cleanup_expired() to authenticated;
