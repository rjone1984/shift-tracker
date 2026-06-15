-- Message Board storage (anonymous 24-hour whiteboard)
-- Run this in Supabase SQL editor.

create extension if not exists pgcrypto;

alter table public.pw_profiles
  add column if not exists message_board_access boolean not null default true;

create table if not exists public.pw_message_board_posts (
  id uuid primary key default gen_random_uuid(),
  message_text text not null,
  message_drawing text,
  message_drawing_theme text,
  thread_title text,
  thread_root_id uuid,
  parent_post_id uuid,
  author_user_id uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint pw_message_board_posts_message_not_empty check (length(trim(message_text)) > 0),
  constraint pw_message_board_posts_expiry_after_create check (expires_at > created_at)
);

-- Upgrade for existing installs:
alter table public.pw_message_board_posts
  add column if not exists message_drawing text;
alter table public.pw_message_board_posts
  add column if not exists message_drawing_theme text;
alter table public.pw_message_board_posts
  add column if not exists thread_title text;
alter table public.pw_message_board_posts
  add column if not exists thread_root_id uuid;
alter table public.pw_message_board_posts
  add column if not exists parent_post_id uuid;
alter table public.pw_message_board_posts
  add column if not exists author_user_id uuid;

create index if not exists pw_message_board_posts_created_at_idx
  on public.pw_message_board_posts (created_at desc);

create index if not exists pw_message_board_posts_expires_at_idx
  on public.pw_message_board_posts (expires_at);
create index if not exists pw_message_board_posts_thread_root_idx
  on public.pw_message_board_posts (thread_root_id, created_at);
create index if not exists pw_message_board_posts_parent_idx
  on public.pw_message_board_posts (parent_post_id, created_at);
create index if not exists pw_message_board_posts_author_idx
  on public.pw_message_board_posts (author_user_id, created_at desc);

alter table public.pw_message_board_posts enable row level security;

-- Everyone signed in can read and post.
drop policy if exists "pw_message_board_select_authenticated" on public.pw_message_board_posts;
create policy "pw_message_board_select_authenticated"
  on public.pw_message_board_posts
  for select
  to authenticated
  using (true);

drop policy if exists "pw_message_board_insert_authenticated" on public.pw_message_board_posts;
create policy "pw_message_board_insert_authenticated"
  on public.pw_message_board_posts
  for insert
  to authenticated
  with check (true);

drop policy if exists "pw_message_board_delete_own" on public.pw_message_board_posts;
create policy "pw_message_board_delete_own"
  on public.pw_message_board_posts
  for delete
  to authenticated
  using (author_user_id = auth.uid());

-- Optional cleanup helper: safely remove expired rows.
create or replace function public.pw_message_board_cleanup_expired()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.pw_message_board_posts
  where expires_at <= now();
$$;

-- Private direct messages are configured in:
-- docs/sql/message-board-private-messaging.sql
