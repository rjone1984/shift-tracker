-- User Management app: admin-only server-side enforcement RPCs
-- Run this in Supabase SQL editor before using /user-management.

drop function if exists public.pw_is_admin_user();
drop function if exists public.pw_is_admin_user(uuid);

create or replace function public.pw_is_admin_user(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists(
      select 1
      from public.pw_profiles p
      where p.id = coalesce(p_uid, auth.uid())
        and p.role = 'admin'
        and coalesce(p.disabled, false) = false
    )
    or exists(
      select 1
      from public.kiln_users k
      where k.auth_user_id = coalesce(p_uid, auth.uid())
        and coalesce(k.is_admin, false) = true
        and coalesce(k.is_locked, false) = false
  );
$$;

create or replace function public.pw_is_admin_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.pw_is_admin_user(auth.uid()::uuid);
$$;

revoke all on function public.pw_is_admin_user() from public;
revoke all on function public.pw_is_admin_user(uuid) from public;
grant execute on function public.pw_is_admin_user() to authenticated;
grant execute on function public.pw_is_admin_user(uuid) to authenticated;

alter table public.pw_profiles
  add column if not exists message_board_access boolean not null default true;

alter table if exists public.pw_requests
  add column if not exists message_board_access boolean not null default true;
alter table if exists public.pw_requests
  add column if not exists kiln_roles jsonb not null default '[]'::jsonb;
alter table if exists public.pw_requests
  add column if not exists logs_access boolean not null default true;

drop trigger if exists pw_protect_admin_profile_trigger on public.pw_profiles;
drop function if exists public.pw_protect_admin_profile();
create or replace function public.pw_protect_admin_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.role, '') = 'admin'
     or (tg_op = 'UPDATE' and coalesce(old.role, '') = 'admin') then
    new.role := 'admin';
    new.approved := true;
    new.disabled := false;
    new.shift_tracker_access := true;
    new.holiday_requests_access := true;
    new.credit_hours_access := true;
    new.message_board_access := true;
    new.holiday_manager_auth_user_id := null;
  end if;
  return new;
end;
$$;
create trigger pw_protect_admin_profile_trigger
before insert or update on public.pw_profiles
for each row
execute function public.pw_protect_admin_profile();

drop trigger if exists pw_protect_admin_kiln_user_trigger on public.kiln_users;
drop function if exists public.pw_protect_admin_kiln_user();
create or replace function public.pw_protect_admin_kiln_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.is_admin, false) = true
     or (tg_op = 'UPDATE' and coalesce(old.is_admin, false) = true) then
    new.is_admin := true;
    new.is_locked := false;
    new.shift_log_access := true;
  end if;
  return new;
end;
$$;
create trigger pw_protect_admin_kiln_user_trigger
before insert or update on public.kiln_users
for each row
execute function public.pw_protect_admin_kiln_user();

drop function if exists public.pw_admin_user_management_snapshot();
create or replace function public.pw_admin_user_management_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.pw_is_admin_user(v_uid) then
    raise exception 'admin_only' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'profiles',
      coalesce(
        (
          select jsonb_agg(to_jsonb(p) order by coalesce(p.full_name, p.email, ''))
          from (
            select
              id,
              full_name,
              email,
              approved,
              disabled,
              role,
              shift_tracker_access,
              holiday_requests_access,
              credit_hours_access,
              message_board_access,
              holiday_manager_auth_user_id,
              work_role_type,
              shift_team,
              must_reset_password
            from public.pw_profiles
          ) p
        ),
        '[]'::jsonb
      ),
    'kiln_users',
      coalesce(
        (
          select jsonb_agg(to_jsonb(k) order by coalesce(k.locked_name, k.email, k.username, ''))
          from (
            select
              auth_user_id,
              username,
              locked_name,
              email,
              is_admin,
              is_shift_manager,
              is_day_manager,
              is_electrician,
              is_mechanical,
              is_process_operator,
              is_cement_analyst,
              is_day_staff,
              is_burner,
              is_locked,
              shift_log_access,
              must_reset_password
            from public.kiln_users
          ) k
        ),
        '[]'::jsonb
      )
  );
end;
$$;
revoke all on function public.pw_admin_user_management_snapshot() from public;
grant execute on function public.pw_admin_user_management_snapshot() to authenticated;

drop function if exists public.pw_admin_user_management_update_user(
  uuid,
  text,
  text,
  text,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  uuid,
  text,
  text,
  jsonb,
  boolean,
  boolean,
  boolean
);
create or replace function public.pw_admin_user_management_update_user(
  p_user_id uuid,
  p_full_name text default null,
  p_email text default null,
  p_platform_role text default null,
  p_approved boolean default null,
  p_disabled boolean default null,
  p_shift_tracker_access boolean default null,
  p_holiday_requests_access boolean default null,
  p_credit_hours_access boolean default null,
  p_message_board_access boolean default null,
  p_holiday_manager_auth_user_id uuid default null,
  p_work_role_type text default null,
  p_shift_team text default null,
  p_kiln_role text default null,
  p_kiln_roles jsonb default null,
  p_shift_log_access boolean default null,
  p_is_locked boolean default null,
  p_must_reset_password boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_existing_email text := null;
  v_existing_full_name text := null;
  v_existing_role text := null;
  v_email text;
  v_full_name text;
  v_platform_role text;
  v_work_role_type text;
  v_shift_team text;
  v_kiln_role text;
  v_kiln_roles jsonb := null;
  v_shift_log_access boolean;
  v_lock_value boolean;
  v_username text;
  v_has_kiln boolean := false;
  v_base_username text;
  v_suffix integer := 2;
  v_has_work_role_type_col boolean := false;
  v_has_pw_reset_col boolean := false;
  v_use_roles_array boolean := false;
  v_has_shift_role boolean := false;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required' using errcode = '22023';
  end if;

  if not public.pw_is_admin_user(v_uid) then
    raise exception 'admin_only' using errcode = '42501';
  end if;

  if not exists(select 1 from public.pw_profiles where id = p_user_id) then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  v_existing_email := (
    select email
    from public.pw_profiles
    where id = p_user_id
    limit 1
  );
  v_existing_full_name := (
    select full_name
    from public.pw_profiles
    where id = p_user_id
    limit 1
  );
  v_existing_role := (
    select role
    from public.pw_profiles
    where id = p_user_id
    limit 1
  );

  v_email := lower(coalesce(nullif(trim(p_email), ''), v_existing_email));
  v_full_name := coalesce(nullif(trim(p_full_name), ''), v_existing_full_name);
  v_platform_role := lower(coalesce(nullif(trim(p_platform_role), ''), coalesce(v_existing_role, 'viewer')));
  if v_platform_role not in ('admin', 'reviewer', 'editor', 'viewer', 'none') then
    v_platform_role := coalesce(v_existing_role, 'viewer');
  end if;

  v_work_role_type := lower(coalesce(nullif(trim(p_work_role_type), ''), ''));
  if v_work_role_type not in ('day', 'shift') then
    v_work_role_type := null;
  end if;

  v_shift_team := upper(coalesce(nullif(trim(p_shift_team), ''), ''));
  if v_shift_team not in ('A','B','C','D','E') then
    v_shift_team := null;
  end if;

  v_kiln_roles := case
    when p_kiln_roles is null then null
    when jsonb_typeof(p_kiln_roles) = 'array' then p_kiln_roles
    else null
  end;
  v_use_roles_array := v_kiln_roles is not null;
  v_kiln_role := lower(coalesce(nullif(trim(p_kiln_role), ''), ''));
  if v_use_roles_array then
    v_kiln_role := case
      when coalesce(v_kiln_roles @> '["admin"]'::jsonb, false) then 'admin'
      when coalesce(v_kiln_roles @> '["shift_manager"]'::jsonb, false) then 'shift_manager'
      when coalesce(v_kiln_roles @> '["day_manager"]'::jsonb, false) then 'day_manager'
      when coalesce(v_kiln_roles @> '["burner"]'::jsonb, false) then 'burner'
      when coalesce(v_kiln_roles @> '["cement_analyst"]'::jsonb, false) then 'cement_analyst'
      when coalesce(v_kiln_roles @> '["electrician"]'::jsonb, false) then 'electrician'
      when coalesce(v_kiln_roles @> '["mechanical"]'::jsonb, false) then 'mechanical'
      when coalesce(v_kiln_roles @> '["process_operator"]'::jsonb, false) then 'process_operator'
      when coalesce(v_kiln_roles @> '["day_staff"]'::jsonb, false) then 'day_staff'
      else 'none'
    end;
    v_has_shift_role := coalesce(
      v_kiln_roles @> '["shift_manager"]'::jsonb
      or v_kiln_roles @> '["burner"]'::jsonb
      or v_kiln_roles @> '["cement_analyst"]'::jsonb
      or v_kiln_roles @> '["electrician"]'::jsonb
      or v_kiln_roles @> '["mechanical"]'::jsonb
      or v_kiln_roles @> '["process_operator"]'::jsonb,
      false
    );
  elsif v_kiln_role not in ('none','admin','shift_manager','day_manager','burner','cement_analyst','electrician','mechanical','process_operator','day_staff') then
    v_kiln_role := null;
  end if;

  if p_shift_log_access is not null then
    v_shift_log_access := p_shift_log_access;
  elsif v_use_roles_array then
    v_shift_log_access := jsonb_array_length(v_kiln_roles) > 0;
  elsif v_kiln_role is not null then
    v_shift_log_access := (v_kiln_role <> 'none');
  else
    v_shift_log_access := null;
  end if;

  v_lock_value := coalesce(p_is_locked, p_disabled);

  update public.pw_profiles
  set
    full_name = coalesce(v_full_name, full_name),
    email = coalesce(v_email, email),
    role = v_platform_role,
    approved = coalesce(p_approved, approved),
    disabled = coalesce(p_disabled, disabled),
    shift_tracker_access = coalesce(p_shift_tracker_access, shift_tracker_access),
    holiday_requests_access = coalesce(p_holiday_requests_access, holiday_requests_access),
    credit_hours_access = coalesce(p_credit_hours_access, credit_hours_access),
    message_board_access = coalesce(p_message_board_access, message_board_access),
    holiday_manager_auth_user_id = case
      when v_use_roles_array and coalesce(v_kiln_roles @> '["admin"]'::jsonb, false) then null
      when not v_use_roles_array and v_kiln_role = 'admin' then null
      else p_holiday_manager_auth_user_id
    end,
    shift_team = case
      when v_use_roles_array then
        case
          when v_work_role_type = 'shift' and v_has_shift_role then coalesce(v_shift_team, shift_team)
          else null
        end
      when v_kiln_role in ('none', 'admin') then null
      when v_work_role_type = 'day' then null
      else coalesce(v_shift_team, shift_team)
    end
  where id = p_user_id;

  v_has_work_role_type_col := exists(
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'pw_profiles'
      and column_name = 'work_role_type'
  );

  if v_has_work_role_type_col and v_work_role_type is not null then
    execute 'update public.pw_profiles set work_role_type = $1 where id = $2'
    using v_work_role_type, p_user_id;
  end if;

  v_has_pw_reset_col := exists(
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'pw_profiles'
      and column_name = 'must_reset_password'
  );

  if v_has_pw_reset_col and p_must_reset_password is not null then
    execute 'update public.pw_profiles set must_reset_password = $1 where id = $2'
    using p_must_reset_password, p_user_id;
  end if;

  v_username := (
    select username
    from public.kiln_users
    where auth_user_id = p_user_id
    limit 1
  );

  v_has_kiln := v_username is not null;

  if not v_has_kiln and (
    (v_use_roles_array and jsonb_array_length(v_kiln_roles) > 0)
    or (v_kiln_role is not null and v_kiln_role <> 'none')
    or coalesce(v_shift_log_access, false)
    or v_lock_value is not null
    or p_must_reset_password is not null
  ) then
    v_base_username := regexp_replace(split_part(coalesce(v_email, ''), '@', 1), '[^a-z0-9_]+', '', 'g');
    if v_base_username is null or v_base_username = '' then
      v_base_username := 'user_' || substr(replace(p_user_id::text, '-', ''), 1, 8);
    end if;
    v_username := v_base_username;
    while exists(select 1 from public.kiln_users where username = v_username) loop
      v_username := v_base_username || '_' || v_suffix::text;
      v_suffix := v_suffix + 1;
    end loop;

    insert into public.kiln_users (
      auth_user_id,
      username,
      locked_name,
      email,
      is_admin,
      is_shift_manager,
      is_day_manager,
      is_electrician,
      is_mechanical,
      is_process_operator,
      is_cement_analyst,
      is_day_staff,
      is_burner,
      is_locked,
      shift_log_access,
      must_reset_password
    )
    values (
      p_user_id,
      v_username,
      v_full_name,
      v_email,
      case when v_use_roles_array then coalesce(v_kiln_roles @> '["admin"]'::jsonb, false) else coalesce(v_kiln_role = 'admin', false) end,
      case when v_use_roles_array then coalesce(v_kiln_roles @> '["shift_manager"]'::jsonb, false) else coalesce(v_kiln_role = 'shift_manager', false) end,
      case when v_use_roles_array then coalesce(v_kiln_roles @> '["day_manager"]'::jsonb, false) else coalesce(v_kiln_role = 'day_manager', false) end,
      case when v_use_roles_array then coalesce(v_kiln_roles @> '["electrician"]'::jsonb, false) else coalesce(v_kiln_role = 'electrician', false) end,
      case when v_use_roles_array then coalesce(v_kiln_roles @> '["mechanical"]'::jsonb, false) else coalesce(v_kiln_role = 'mechanical', false) end,
      case when v_use_roles_array then coalesce(v_kiln_roles @> '["process_operator"]'::jsonb, false) else coalesce(v_kiln_role = 'process_operator', false) end,
      case when v_use_roles_array then coalesce(v_kiln_roles @> '["cement_analyst"]'::jsonb, false) else coalesce(v_kiln_role = 'cement_analyst', false) end,
      case when v_use_roles_array then coalesce(v_kiln_roles @> '["day_staff"]'::jsonb, false) else coalesce(v_kiln_role = 'day_staff', false) end,
      case when v_use_roles_array then coalesce(v_kiln_roles @> '["burner"]'::jsonb, false) else coalesce(v_kiln_role = 'burner', false) end,
      coalesce(v_lock_value, false),
      coalesce(v_shift_log_access, false),
      coalesce(p_must_reset_password, false)
    );
    v_has_kiln := true;
  end if;

  if v_has_kiln then
    update public.kiln_users
    set
      locked_name = coalesce(v_full_name, locked_name),
      email = coalesce(v_email, email),
      is_admin = case
        when v_use_roles_array then coalesce(v_kiln_roles @> '["admin"]'::jsonb, false)
        when v_kiln_role is null then is_admin
        else v_kiln_role = 'admin'
      end,
      is_shift_manager = case
        when v_use_roles_array then coalesce(v_kiln_roles @> '["shift_manager"]'::jsonb, false)
        when v_kiln_role is null then is_shift_manager
        else v_kiln_role = 'shift_manager'
      end,
      is_day_manager = case
        when v_use_roles_array then coalesce(v_kiln_roles @> '["day_manager"]'::jsonb, false)
        when v_kiln_role is null then is_day_manager
        else v_kiln_role = 'day_manager'
      end,
      is_electrician = case
        when v_use_roles_array then coalesce(v_kiln_roles @> '["electrician"]'::jsonb, false)
        when v_kiln_role is null then is_electrician
        else v_kiln_role = 'electrician'
      end,
      is_mechanical = case
        when v_use_roles_array then coalesce(v_kiln_roles @> '["mechanical"]'::jsonb, false)
        when v_kiln_role is null then is_mechanical
        else v_kiln_role = 'mechanical'
      end,
      is_process_operator = case
        when v_use_roles_array then coalesce(v_kiln_roles @> '["process_operator"]'::jsonb, false)
        when v_kiln_role is null then is_process_operator
        else v_kiln_role = 'process_operator'
      end,
      is_cement_analyst = case
        when v_use_roles_array then coalesce(v_kiln_roles @> '["cement_analyst"]'::jsonb, false)
        when v_kiln_role is null then is_cement_analyst
        else v_kiln_role = 'cement_analyst'
      end,
      is_day_staff = case
        when v_use_roles_array then coalesce(v_kiln_roles @> '["day_staff"]'::jsonb, false)
        when v_kiln_role is null then is_day_staff
        else v_kiln_role = 'day_staff'
      end,
      is_burner = case
        when v_use_roles_array then coalesce(v_kiln_roles @> '["burner"]'::jsonb, false)
        when v_kiln_role is null then is_burner
        else v_kiln_role = 'burner'
      end,
      shift_log_access = coalesce(v_shift_log_access, shift_log_access),
      is_locked = coalesce(v_lock_value, is_locked),
      must_reset_password = coalesce(p_must_reset_password, must_reset_password)
    where auth_user_id = p_user_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'user_id', p_user_id
  );
end;
$$;
revoke all on function public.pw_admin_user_management_update_user(
  uuid,
  text,
  text,
  text,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  uuid,
  text,
  text,
  text,
  jsonb,
  boolean,
  boolean,
  boolean
) from public;
grant execute on function public.pw_admin_user_management_update_user(
  uuid,
  text,
  text,
  text,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  uuid,
  text,
  text,
  text,
  jsonb,
  boolean,
  boolean,
  boolean
) to authenticated;
