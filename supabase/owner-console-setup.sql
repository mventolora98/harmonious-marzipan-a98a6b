-- CreditPilot AI owner console setup (development Supabase project only)
-- Run in the Supabase SQL editor after reviewing. Do not run on production.
-- Owner assignment is a privileged manual operation; never grant from browser code.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.owner_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now()
);
revoke all on private.owner_members from public, anon, authenticated;
alter table private.owner_members enable row level security;

create or replace function public.creditpilot_is_owner()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.owner_members o
    join auth.users u on u.id=o.user_id
    where o.user_id = (select auth.uid())
      and u.email_confirmed_at is not null
  );
$$;
revoke all on function public.creditpilot_is_owner() from public, anon;
grant execute on function public.creditpilot_is_owner() to authenticated;

-- Returns only minimal identity fields, never passwords or tokens.
-- The function itself enforces authorization on every call.
create or replace function public.creditpilot_owner_customers()
returns table (
  user_id uuid,
  email text,
  created_at timestamptz,
  email_verified boolean,
  is_owner boolean
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not (select public.creditpilot_is_owner()) then
    raise exception 'Not authorized' using errcode='42501';
  end if;
  return query
    select u.id, u.email::text, u.created_at,
      u.email_confirmed_at is not null,
      o.user_id is not null
    from auth.users u
    left join private.owner_members o on o.user_id=u.id
    order by u.created_at desc
    limit 250;
end;
$$;
revoke all on function public.creditpilot_owner_customers() from public, anon;
grant execute on function public.creditpilot_owner_customers() to authenticated;

-- Assign ONLY verified owner UUIDs after checking auth.users in Supabase dashboard.
-- Do not use an email-based policy or expose the service_role key.
-- Example (replace placeholders with actual verified auth.users IDs):
-- insert into private.owner_members(user_id) values
--   ('YOUR_MARC_AUTH_USER_UUID'), ('YOUR_JENNIFER_AUTH_USER_UUID')
-- on conflict (user_id) do nothing;
