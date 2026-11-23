-- Run only after the Netlify function and Turnstile are configured and tested.
-- Disable the old direct-from-browser RPC, which bypasses CAPTCHA and rate limits.
revoke execute on function public.creditpilot_submit_referral(text,text,text,text,boolean) from anon, authenticated;
notify pgrst, 'reload schema';
