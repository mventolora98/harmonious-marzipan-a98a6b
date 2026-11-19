// CreditPilot AI — Lob test-only mailing endpoint.
// This endpoint accepts no customer documents or recipient addresses.
const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
const reply = (statusCode, data) => ({ statusCode, headers, body: JSON.stringify(data) });
const sample = {
  description: "CreditPilot AI fictional dispute letter — TEST ONLY",
  use_type: "operational",
  to: { name: "Example Credit Bureau", address_line1: "210 King Street", address_city: "San Francisco", address_state: "CA", address_zip: "94107", address_country: "US" },
  from: { name: "CreditPilot AI Demo", address_line1: "210 King Street", address_city: "San Francisco", address_state: "CA", address_zip: "94107", address_country: "US" },
  file: "<html><body style='font-family:Arial;padding:40px'><h1>FICTIONAL DEMO — NOT A REAL DISPUTE</h1><p>Example Customer</p><p>Dear Example Credit Bureau,</p><p>This is a fictional test of the CreditPilot AI mailing integration. No consumer account or dispute information is included.</p><p>Sincerely,<br>Example Customer</p></body></html>",
  color: false,
  double_sided: false
};
exports.handler = async (event) => {
  if (event.httpMethod !== "POST") return reply(405, { error: "Method not allowed" });
  // Netlify build-time CONTEXT/BRANCH may be unavailable in function runtime.
  // Restrict sandbox testing to the exact development branch hostname.
  const host = String(event.headers.host || event.headers.Host || "").toLowerCase().split(":")[0];
  const developmentHost = "development--harmonious-marzipan-a98a6b.netlify.app";
  if (host !== developmentHost)
    return reply(403, { error: "Open the development branch URL (not a deploy permalink) to run this sandbox test.", diagnostic: { host: host || "unset" } });
  const key = process.env.LOB_TEST_API_KEY;
  if (!key || !key.startsWith("test_")) return reply(503, { error: "Valid Lob test credentials are not configured." });
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY)
    return reply(503, { error: "Owner authorization is not configured on the server." });
  const token = (event.headers.authorization || event.headers.Authorization || "").match(/^Bearer (.+)$/i)?.[1];
  if (!token || token.length > 4096) return reply(401, { error: "Sign in required." });
  try {
    const authHeaders = { apikey: process.env.SUPABASE_ANON_KEY, Authorization: "Bearer " + token };
    const userRes = await fetch(process.env.SUPABASE_URL + "/auth/v1/user", { headers: authHeaders });
    if (!userRes.ok) return reply(401, { error: "Session is not valid." });
    const user = await userRes.json();
    if (!user.id || !user.email_confirmed_at) return reply(403, { error: "Verified account required." });
    const ownerRes = await fetch(process.env.SUPABASE_URL + "/rest/v1/rpc/creditpilot_is_owner", {
      method: "POST", headers: { ...authHeaders, "Content-Type": "application/json" }, body: "{}"
    });
    if (!ownerRes.ok || (await ownerRes.json()) !== true)
      return reply(403, { error: "Owner-only testing is not enabled for this account." });
    const body = JSON.parse(event.body || "{}");
    if (body.confirm !== "FICTIONAL_TEST_ONLY")
      return reply(400, { error: "Invalid fictional test request." });
    if (body.action === "status") {
      if (typeof body.id !== "string" || !/^ltr_[a-zA-Z0-9]{8,64}$/.test(body.id))
        return reply(400, { error: "Invalid test letter ID." });
      const statusRes = await fetch("https://api.lob.com/v1/letters/" + encodeURIComponent(body.id), {
        headers: { Authorization: "Basic " + Buffer.from(key + ":").toString("base64") },
        signal: AbortSignal.timeout(12000)
      });
      const statusData = await statusRes.json().catch(() => ({}));
      if (!statusRes.ok)
        return reply(502, { error: "Unable to retrieve Lob sandbox status.", detail: statusData.error?.message || "Check test letter ID." });
      return reply(200, { mode: "test", id: statusData.id, status: statusData.status || "unknown",
        created_at: statusData.date_created || null, send_date: statusData.send_date || null,
        mail_type: statusData.mail_type || null, tracking_events: Array.isArray(statusData.tracking_events)
          ? statusData.tracking_events.slice(0,10).map(x => ({ type: x.type || null, time: x.time || null })) : [],
        message: "Sandbox status only. No physical mail sent." });
    }
    if (!["standard","certified"].includes(body.mailType))
      return reply(400, { error: "Invalid fictional test request." });
    const payload = new URLSearchParams();
    const letter = { ...sample, ...(body.mailType === "certified" ? { mail_type: "usps_first_class", extra_service: "certified" } : { mail_type: "usps_first_class" }) };
    const add = (prefix, obj) => Object.entries(obj).forEach(([k,v]) => payload.set(prefix ? prefix + "[" + k + "]" : k, String(v)));
    for (const [k,v] of Object.entries(letter)) {
      if (k === "to" || k === "from") add(k,v); else payload.set(k,String(v));
    }
    const lob = await fetch("https://api.lob.com/v1/letters", {
      method: "POST", headers: { Authorization: "Basic " + Buffer.from(key + ":").toString("base64"), "Content-Type": "application/x-www-form-urlencoded" },
      body: payload.toString(), signal: AbortSignal.timeout(12000)
    });
    const data = await lob.json().catch(() => ({}));
    if (!lob.ok) return reply(502, { error: "Lob rejected the test request.", detail: data.error?.message || "Check Lob test configuration." });
    return reply(200, { mode: "test", id: data.id, status: data.send_date ? "Test created" : "Test accepted", mailType: body.mailType, message: "Lob test response received. No physical mail was sent." });
  } catch (e) {
    return reply(502, { error: "Test request could not be completed. Check server logs and configuration." });
  }
};
