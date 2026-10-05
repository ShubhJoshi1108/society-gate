// Shared helpers for Society Gate hooks.
// Loaded inside each handler with: const u = require(`${__hooks}/utils.js`)

const PURPOSE_LABELS = {
  guest: "Guest", delivery: "Delivery", cab: "Cab", service: "Service / Repair",
  maid: "Daily help", other: "Other",
};

function env(name, fallback) {
  const v = $os.getenv(name);
  return v ? v : fallback;
}

function pbDate(msAgo) {
  // PocketBase datetime format: "2006-01-02 15:04:05.000Z"
  return new Date(Date.now() - (msAgo || 0)).toISOString().replace("T", " ");
}

function randomDigits(n) {
  let s = "";
  for (let i = 0; i < n; i++) s += Math.floor(Math.random() * 10);
  return s;
}

/** Publish one push message to an ntfy topic. Never throws. */
function sendNtfy(topic, msg) {
  if (!topic) return;
  const base = env("NTFY_URL", "");
  if (!base) return;
  const headers = { "Content-Type": "application/json" };
  const token = env("NTFY_TOKEN", "");
  if (token) headers["Authorization"] = "Bearer " + token;
  try {
    const res = $http.send({
      url: base.replace(/\/$/, ""),
      method: "POST",
      headers: headers,
      body: JSON.stringify(Object.assign({ topic: topic }, msg)),
      timeout: 10,
    });
    if (res.statusCode >= 300) {
      console.log("[gate] ntfy publish failed", res.statusCode, toString(res.body));
    }
  } catch (err) {
    console.log("[gate] ntfy publish error", err);
  }
}

function usersByFilter(filter, params) {
  try {
    return $app.findRecordsByFilter("users", filter, "", 200, 0, params);
  } catch (_) {
    return [];
  }
}

function residentsOfFlat(flatId) {
  return usersByFilter("flat = {:flat} && role = 'resident'", { flat: flatId });
}

function flatLabel(flatId) {
  try {
    const label = $app.findRecordById("flats", flatId).getString("label");
    return /^[0-9]+$/.test(label) ? "House " + label : label;
  } catch (_) {
    return "";
  }
}

function describeVisit(visit) {
  const purpose = PURPOSE_LABELS[visit.getString("purpose")] || visit.getString("purpose");
  const lines = [purpose];
  const note = visit.getString("purpose_note");
  if (note) lines[0] += " – " + note;
  const phone = visit.getString("visitor_phone");
  if (phone) lines.push("📞 " + phone);
  const vehicle = visit.getString("vehicle_no");
  if (vehicle) lines.push("🚗 " + vehicle);
  const people = visit.getInt("people_count");
  if (people > 1) lines.push("👥 " + people + " people");
  return lines.join("\n");
}

/** Push "someone is at the gate" with Approve / Deny / Leave at gate buttons. */
function notifyResidentsNewVisit(visit) {
  const flatId = visit.getString("flat");
  const publicUrl = env("PUBLIC_URL", "").replace(/\/$/, "");
  const id = visit.id;
  const token = visit.getString("action_token");
  const act = (decision) =>
    publicUrl + "/api/gate/visits/" + id + "/decide?decision=" + decision + "&token=" + token;

  const actions = [
    { action: "http", label: "✅ Approve", url: act("approved"), method: "POST", clear: true },
    { action: "http", label: "❌ Deny", url: act("denied"), method: "POST", clear: true },
  ];
  if (visit.getString("purpose") === "delivery") {
    actions.push({ action: "http", label: "📦 Leave at gate", url: act("leave_at_gate"), method: "POST", clear: true });
  }

  const title = "🔔 " + visit.getString("visitor_name") + " is at the gate (" + flatLabel(flatId) + ")";
  for (const r of residentsOfFlat(flatId)) {
    sendNtfy(r.getString("ntfy_topic"), {
      title: title,
      message: describeVisit(visit),
      priority: 5,
      tags: ["door"],
      actions: actions,
    });
  }
}

/** FYI push to residents (e.g. pre-approved guest entered). */
function notifyResidentsInfo(visit, title) {
  for (const r of residentsOfFlat(visit.getString("flat"))) {
    sendNtfy(r.getString("ntfy_topic"), {
      title: title,
      message: describeVisit(visit),
      priority: 3,
      tags: ["white_check_mark"],
    });
  }
}

/** Tell the guard who logged the visit what the resident decided. */
function notifyGuard(visit) {
  const guardId = visit.getString("guard");
  if (!guardId) return;
  let guard;
  try { guard = $app.findRecordById("users", guardId); } catch (_) { return; }
  const status = visit.getString("status");
  const icon = { approved: "✅ ALLOW", denied: "❌ DENY", leave_at_gate: "📦 LEAVE AT GATE", expired: "⌛ NO RESPONSE" }[status] || status;
  sendNtfy(guard.getString("ntfy_topic"), {
    title: icon + " – " + visit.getString("visitor_name"),
    message: flatLabel(visit.getString("flat")),
    priority: status === "expired" ? 4 : 3,
    tags: [status === "approved" ? "white_check_mark" : "warning"],
  });
}

/**
 * Apply a decision to a pending visit. Returns the updated record.
 * Throws BadRequestError if the visit is not pending.
 */
function decide(visit, decision, userId) {
  const allowed = ["approved", "denied", "leave_at_gate"];
  if (allowed.indexOf(decision) === -1) throw new BadRequestError("Invalid decision.");
  if (visit.getString("status") !== "pending") {
    throw new BadRequestError("This request was already " + visit.getString("status") + ".");
  }
  visit.set("status", decision);
  visit.set("decided_at", pbDate(0));
  if (userId) visit.set("decided_by", userId);
  visit.set("action_token", ""); // one-time use
  $app.save(visit);
  notifyGuard(visit);
  return visit;
}

module.exports = {
  env, pbDate, randomDigits, sendNtfy, residentsOfFlat, flatLabel,
  notifyResidentsNewVisit, notifyResidentsInfo, notifyGuard, decide,
};
