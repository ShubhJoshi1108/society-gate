/// <reference path="../pb_data/types.d.ts" />
// Initial schema for Society Gate.
// Collections: flats, users (extended), visits, passes

migrate((app) => {
  // ---------- flats ----------
  const flats = new Collection({
    type: "base",
    name: "flats",
    listRule: "@request.auth.id != ''",
    viewRule: "@request.auth.id != ''",
    createRule: null, // admin (superuser) only, via dashboard
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "text", name: "block", required: false, max: 20 },
      { type: "text", name: "number", required: true, max: 20 },
      { type: "text", name: "label", required: true, max: 60, presentable: true }, // house number, e.g. "245"
      { type: "autodate", name: "created", onCreate: true },
      { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_flats_label ON flats (label)"],
  });
  app.save(flats);

  // ---------- users (built-in auth collection) ----------
  const users = app.findCollectionByNameOrId("users");
  users.fields.add(new SelectField({
    name: "role", required: true, maxSelect: 1,
    values: ["resident", "guard", "admin"],
  }));
  users.fields.add(new RelationField({
    name: "flat", collectionId: flats.id, maxSelect: 1, cascadeDelete: false,
  }));
  users.fields.add(new TextField({ name: "phone", max: 20 }));
  // secret ntfy topic for this user's push notifications (generated server side)
  users.fields.add(new TextField({ name: "ntfy_topic", max: 64, hidden: true }));
  // guards/admins can see everyone (to call a resident); residents see their own flat only
  users.listRule = "@request.auth.role = 'guard' || @request.auth.role = 'admin' || id = @request.auth.id || (flat != '' && flat = @request.auth.flat)";
  users.viewRule = users.listRule;
  users.createRule = null; // accounts are created by the society admin
  users.updateRule = "id = @request.auth.id && @request.body.role:isset = false && @request.body.flat:isset = false && @request.body.ntfy_topic:isset = false";
  users.deleteRule = null;
  app.save(users);

  // ---------- visits ----------
  const visits = new Collection({
    type: "base",
    name: "visits",
    // guards/admins see everything, residents only their own flat
    listRule: "@request.auth.role = 'guard' || @request.auth.role = 'admin' || flat = @request.auth.flat",
    viewRule: "@request.auth.role = 'guard' || @request.auth.role = 'admin' || flat = @request.auth.flat",
    createRule: "@request.auth.role = 'guard' || @request.auth.role = 'admin'",
    updateRule: null, // decisions go through /api/gate/visits/{id}/decide
    deleteRule: null,
    fields: [
      { type: "relation", name: "flat", required: true, collectionId: flats.id, maxSelect: 1 },
      { type: "text", name: "visitor_name", required: true, max: 80 },
      { type: "text", name: "visitor_phone", max: 20 },
      { type: "select", name: "purpose", required: true, maxSelect: 1,
        values: ["guest", "delivery", "cab", "service", "maid", "other"] },
      { type: "text", name: "purpose_note", max: 200 },
      { type: "text", name: "vehicle_no", max: 20 },
      { type: "number", name: "people_count", min: 0, max: 50 },
      { type: "file", name: "photo", maxSelect: 1, maxSize: 3 * 1024 * 1024,
        mimeTypes: ["image/jpeg", "image/png", "image/webp"] },
      { type: "select", name: "status", required: true, maxSelect: 1,
        values: ["pending", "approved", "denied", "leave_at_gate", "expired"] },
      { type: "relation", name: "guard", collectionId: users.id, maxSelect: 1 },
      { type: "relation", name: "decided_by", collectionId: users.id, maxSelect: 1 },
      { type: "date", name: "decided_at" },
      { type: "date", name: "checked_out_at" },
      { type: "text", name: "pass_code", max: 10 },
      // one-time secret used by the Approve/Deny buttons in the push notification
      { type: "text", name: "action_token", max: 64, hidden: true },
      { type: "autodate", name: "created", onCreate: true },
      { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
    ],
    indexes: [
      "CREATE INDEX idx_visits_flat ON visits (flat)",
      "CREATE INDEX idx_visits_status ON visits (status)",
    ],
  });
  app.save(visits);

  // ---------- passes (pre-approved guests) ----------
  const passes = new Collection({
    type: "base",
    name: "passes",
    listRule: "@request.auth.role = 'admin' || (@request.auth.role = 'resident' && flat = @request.auth.flat)",
    viewRule: "@request.auth.role = 'admin' || (@request.auth.role = 'resident' && flat = @request.auth.flat)",
    createRule: "@request.auth.role = 'resident' && @request.body.flat = @request.auth.flat",
    updateRule: null,
    deleteRule: "@request.auth.role = 'resident' && flat = @request.auth.flat",
    fields: [
      { type: "relation", name: "flat", required: true, collectionId: flats.id, maxSelect: 1 },
      { type: "relation", name: "created_by", collectionId: users.id, maxSelect: 1 },
      { type: "text", name: "guest_name", required: true, max: 80 },
      { type: "text", name: "guest_phone", max: 20 },
      { type: "text", name: "code", max: 10 }, // generated server side
      { type: "date", name: "valid_until", required: true },
      { type: "bool", name: "multi_use" },
      { type: "number", name: "used_count", min: 0 },
      { type: "autodate", name: "created", onCreate: true },
      { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE INDEX idx_passes_code ON passes (code)"],
  });
  app.save(passes);
}, (app) => {
  for (const name of ["passes", "visits", "flats"]) {
    try { app.delete(app.findCollectionByNameOrId(name)); } catch (_) {}
  }
  const users = app.findCollectionByNameOrId("users");
  for (const f of ["role", "flat", "phone", "ntfy_topic"]) users.fields.removeByName(f);
  app.save(users);
});
