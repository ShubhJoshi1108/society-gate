/// <reference path="../pb_data/types.d.ts" />
// Society Gate – server logic (PocketBase JSVM hooks)

// ---------------------------------------------------------------
// Users: every account gets a secret ntfy topic for push messages
// ---------------------------------------------------------------
onRecordCreate((e) => {
  if (!e.record.getString("ntfy_topic")) {
    e.record.set("ntfy_topic", "gate-" + $security.randomStringWithAlphabet(24, "abcdefghijklmnopqrstuvwxyz0123456789"));
  }
  e.next();
}, "users");

// ---------------------------------------------------------------
// Visits: guard logs a visitor
// ---------------------------------------------------------------
onRecordCreateRequest((e) => {
  const u = require(`${__hooks}/utils.js`);
  const rec = e.record;

  rec.set("guard", e.auth ? e.auth.id : "");
  rec.set("status", "pending");
  rec.set("decided_by", "");
  rec.set("decided_at", "");
  rec.set("checked_out_at", "");
  rec.set("action_token", $security.randomString(40));

  // Pre-approved pass?
  const code = (rec.getString("pass_code") || "").trim();
  if (code) {
    let pass;
    try {
      pass = $app.findFirstRecordByFilter(
        "passes",
        "code = {:code} && valid_until >= {:now}",
        { code: code, now: u.pbDate(0) },
      );
    } catch (_) {
      throw new BadRequestError("Pass code is invalid or expired.");
    }
    if (!pass.getBool("multi_use") && pass.getInt("used_count") > 0) {
      throw new BadRequestError("This pass code was already used.");
    }
    rec.set("flat", pass.getString("flat"));
    if (!rec.getString("visitor_name")) rec.set("visitor_name", pass.getString("guest_name"));
    if (!rec.getString("visitor_phone")) rec.set("visitor_phone", pass.getString("guest_phone"));
    if (!rec.getString("purpose")) rec.set("purpose", "guest");
    rec.set("status", "approved");
    rec.set("decided_by", pass.getString("created_by"));
    rec.set("decided_at", u.pbDate(0));
    rec.set("action_token", "");
    pass.set("used_count", pass.getInt("used_count") + 1);
    $app.save(pass);
  }

  e.next();
}, "visits");

onRecordAfterCreateSuccess((e) => {
  const u = require(`${__hooks}/utils.js`);
  const status = e.record.getString("status");
  if (status === "pending") {
    u.notifyResidentsNewVisit(e.record);
  } else if (status === "approved") {
    u.notifyResidentsInfo(e.record, "✅ " + e.record.getString("visitor_name") + " entered with your pass");
  }
  e.next();
}, "visits");

// ---------------------------------------------------------------
// Passes: resident pre-approves a guest, server generates the code
// ---------------------------------------------------------------
onRecordCreateRequest((e) => {
  const u = require(`${__hooks}/utils.js`);
  e.record.set("created_by", e.auth ? e.auth.id : "");
  e.record.set("used_count", 0);
  let code = "";
  for (let i = 0; i < 20; i++) {
    code = u.randomDigits(6);
    try {
      $app.findFirstRecordByFilter("passes", "code = {:c} && valid_until >= {:now}", { c: code, now: u.pbDate(0) });
    } catch (_) {
      break; // not found => unique among active passes
    }
  }
  e.record.set("code", code);
  e.next();
}, "passes");

// ---------------------------------------------------------------
// API: approve / deny / leave at gate
//   - from the app:   POST /api/gate/visits/{id}/decide  {decision}  (auth: resident of that flat)
//   - from the push notification buttons:  ...?decision=approved&token=XXXX (no login)
// ---------------------------------------------------------------
routerAdd("POST", "/api/gate/visits/{id}/decide", (e) => {
  const u = require(`${__hooks}/utils.js`);
  const info = e.requestInfo();
  const id = e.request.pathValue("id");
  const decision = (info.body && info.body.decision) || info.query.decision || "";
  const token = info.query.token || (info.body && info.body.token) || "";

  let visit;
  try { visit = $app.findRecordById("visits", id); } catch (_) { throw new NotFoundError("Visit not found."); }

  let userId = "";
  if (token) {
    if (!visit.getString("action_token") || token !== visit.getString("action_token")) {
      throw new ForbiddenError("This link is no longer valid.");
    }
  } else {
    const auth = e.auth;
    if (!auth) throw new UnauthorizedError("Login required.");
    const isAdmin = auth.getString("role") === "admin";
    const ownsFlat = auth.getString("role") === "resident" && auth.getString("flat") === visit.getString("flat");
    if (!isAdmin && !ownsFlat) throw new ForbiddenError("Not your flat.");
    userId = auth.id;
  }

  u.decide(visit, decision, userId);
  return e.json(200, { id: visit.id, status: visit.getString("status") });
});

// Guard marks visitor as exited
routerAdd("POST", "/api/gate/visits/{id}/checkout", (e) => {
  const u = require(`${__hooks}/utils.js`);
  const role = e.auth.getString("role");
  if (role !== "guard" && role !== "admin") throw new ForbiddenError("Guards only.");
  const visit = $app.findRecordById("visits", e.request.pathValue("id"));
  if (visit.getString("checked_out_at")) throw new BadRequestError("Already checked out.");
  visit.set("checked_out_at", u.pbDate(0));
  $app.save(visit);
  return e.json(200, { id: visit.id, checked_out_at: visit.getString("checked_out_at") });
}, $apis.requireAuth("users"));

// The logged-in user's push subscription details (topic is hidden from normal reads)
routerAdd("GET", "/api/gate/me/push", (e) => {
  const u = require(`${__hooks}/utils.js`);
  const me = $app.findRecordById("users", e.auth.id);
  return e.json(200, {
    server: u.env("NTFY_PUBLIC_URL", "https://ntfy.sh"),
    topic: me.getString("ntfy_topic"),
  });
}, $apis.requireAuth("users"));

// Send a test notification to yourself
routerAdd("POST", "/api/gate/me/push-test", (e) => {
  const u = require(`${__hooks}/utils.js`);
  const me = $app.findRecordById("users", e.auth.id);
  u.sendNtfy(me.getString("ntfy_topic"), {
    title: "🔔 Society Gate test",
    message: "Notifications are working, " + (me.getString("name") || "neighbour") + "!",
    priority: 4,
  });
  return e.json(200, { ok: true });
}, $apis.requireAuth("users"));

// ---------------------------------------------------------------
// Cron: auto-expire unanswered requests so the guard isn't stuck
// ---------------------------------------------------------------
cronAdd("gate_expire_pending", "* * * * *", () => {
  const u = require(`${__hooks}/utils.js`);
  const parsed = parseFloat(u.env("EXPIRE_MINUTES", "10"));
  const minutes = isNaN(parsed) ? 10 : parsed;
  let stale = [];
  try {
    stale = $app.findRecordsByFilter(
      "visits", "status = 'pending' && created < {:t}", "", 200, 0,
      { t: u.pbDate(minutes * 60 * 1000) },
    );
  } catch (_) { return; }
  for (const v of stale) {
    v.set("status", "expired");
    v.set("action_token", "");
    $app.save(v);
    u.notifyGuard(v);
  }
});
