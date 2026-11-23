-- Development only: run in Supabase SQL editor after reviewing.
-- Stores voluntary, low-sensitivity referral inquiries. No credit reports or SSNs.
create table if not exists public.creditpilot_referral_inquiries (
 id uuid primary key default gen_random_uuid(),
 created_at timestamptz not null default now(),
 referral_code text not null,
 contact_name text not null,
 contact_email text not null,
 message text,
 consent boolean not null default false,
 status text not null default 'new' check (status in ('new','contacted','closed')),
 constraint referral_code_format check (referral_code ~ '^[a-z0-9_-]{1,40}$'),
 constraint contact_name_length check (char_length(contact_name) between 2 and 100),
 constraint contact_email_length check (char_length(contact_email) between 5 and 254),
 constraint message_length check (message is null or char_length(message) <= 500),
 constraint consent_required check (consent = true)
);
alter table public.creditpilot_referral_inquiries enable row level security;
revoke all on public.creditpilot_referral_inquiries from anon, authenticated;
-- No direct client table access; only narrow RPCs.
create or replace function public.creditpilot_submit_referral(
 p_referral_code text, p_contact_name text, p_contact_email text, p_message text, p_consent boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
 if p_consent is distinct from true then raise exception 'Consent is required'; end if;
 if p_referral_code is null or lower(p_referral_code) !~ '^[a-z0-9_-]{1,40}$' then raise exception 'Invalid referral code'; end if;
 if length(trim(coalesce(p_contact_name,''))) not between 2 and 100 then raise exception 'Invalid name'; end if;
 if length(trim(coalesce(p_contact_email,''))) not between 5 and 254
 or trim(p_contact_email) !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email'; end if;
 if length(coalesce(p_message,'')) > 500 then raise exception 'Message too long'; end if;
 insert into public.creditpilot_referral_inquiries(referral_code,contact_name,contact_email,message,consent)
 values(lower(p_referral_code),trim(p_contact_name),lower(trim(p_contact_email)),nullif(trim(coalesce(p_message,'')),''),true)
 returning id into new_id;
 return new_id;
end $$;
revoke all on function public.creditpilot_submit_referral(text,text,text,text,boolean) from public;
grant execute on function public.creditpilot_submit_referral(text,text,text,text,boolean) to anon,authenticated;
create or replace function public.creditpilot_owner_referrals()
returns table(id uuid,created_at timestamptz,referral_code text,contact_name text,contact_email text,message text,status text)
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or public.creditpilot_is_owner() is distinct from true then
  raise exception 'Owner access required';
 end if;
 return query select r.id,r.created_at,r.referral_code,r.contact_name,r.contact_email,r.message,r.status
 from public.creditpilot_referral_inquiries r order by r.created_at desc limit 250;
end $$;
revoke all on function public.creditpilot_owner_referrals() from public;
grant execute on function public.creditpilot_owner_referrals() to authenticated;
-- Operational note: enable Supabase CAPTCHA/rate limiting or an abuse-protected server endpoint
-- before sharing this public form widely; this function alone is not bot-resistant.
