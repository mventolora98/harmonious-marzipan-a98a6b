-- Run in the same Supabase project as the existing referral functions.
-- Only authenticated owners may change inquiry statuses.
create or replace function public.creditpilot_owner_update_referral_status(
 p_id uuid, p_status text
) returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
 if auth.uid() is null or public.creditpilot_is_owner() is distinct from true then
  raise exception 'Owner access required';
 end if;
 if p_status is null or p_status not in ('new','contacted','closed') then
  raise exception 'Invalid status';
 end if;
 update public.creditpilot_referral_inquiries
 set status=p_status where id=p_id;
 return found;
end $$;
revoke all on function public.creditpilot_owner_update_referral_status(uuid,text) from public;
grant execute on function public.creditpilot_owner_update_referral_status(uuid,text) to authenticated;
notify pgrst, 'reload schema';
