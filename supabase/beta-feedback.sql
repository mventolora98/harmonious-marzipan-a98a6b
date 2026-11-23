-- CreditPilot AI beta feedback (development only).
-- Run once in the Supabase project used by the development site.
-- Requires the existing public.creditpilot_is_owner() RPC.
begin;
create table if not exists public.creditpilot_beta_feedback (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 category text not null check (category in ('Bug report','Suggestion','Usability feedback')),
 area text not null check (area in ('Registration / Login','Overview','Credit Reports','Dispute Center','Document Center','Mailing Center','Credit Education','Account Settings','Other')),
 description text not null check (char_length(description) between 10 and 2000),
 created_at timestamptz not null default now()
);
create index if not exists creditpilot_beta_feedback_created_idx on public.creditpilot_beta_feedback(created_at desc);
alter table public.creditpilot_beta_feedback enable row level security;
revoke all on public.creditpilot_beta_feedback from anon, authenticated;
create or replace function public.creditpilot_submit_beta_feedback(p_category text,p_area text,p_description text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then
  raise exception 'Verified sign-in required';
 end if;
 insert into public.creditpilot_beta_feedback(user_id,category,area,description)
 values(auth.uid(),p_category,p_area,btrim(p_description)) returning id into v_id;
 return v_id;
end; $$;
create or replace function public.creditpilot_owner_beta_feedback()
returns table(id uuid,customer_email text,category text,area text,description text,created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or coalesce(public.creditpilot_is_owner(),false) is not true then
  raise exception 'Owner access required';
 end if;
 return query select f.id,u.email::text,f.category,f.area,f.description,f.created_at
 from public.creditpilot_beta_feedback f join auth.users u on u.id=f.user_id
 order by f.created_at desc limit 200;
end; $$;
revoke all on function public.creditpilot_submit_beta_feedback(text,text,text) from public,anon;
revoke all on function public.creditpilot_owner_beta_feedback() from public,anon;
grant execute on function public.creditpilot_submit_beta_feedback(text,text,text) to authenticated;
grant execute on function public.creditpilot_owner_beta_feedback() to authenticated;
commit;
