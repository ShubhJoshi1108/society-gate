/// <reference path="../pb_data/types.d.ts" />
// TEST MODE only (START-TEST-SERVER sets TEST_MODE=1): ready-made logins.
//   admin website: admin@test.com / Test12345
//   guard:         guard@test.com / Test12345
//   resident 245:  res245@test.com / Test12345
// On the real society server TEST_MODE is not set, so this does nothing.

migrate((app) => {
  if ($os.getenv("TEST_MODE") !== "1") return;
  const PASS = "Test12345";

  try {
    app.findAuthRecordByEmail("_superusers", "admin@test.com");
  } catch (_) {
    const su = new Record(app.findCollectionByNameOrId("_superusers"));
    su.setEmail("admin@test.com");
    su.setPassword(PASS);
    app.save(su);
  }

  const house = app.findFirstRecordByFilter("flats", "label = '245'").id;
  const users = app.findCollectionByNameOrId("users");
  const people = [
    { email: "guard@test.com", name: "Test Guard", role: "guard", flat: "" },
    { email: "res245@test.com", name: "Test Resident", role: "resident", flat: house },
  ];
  for (const p of people) {
    try {
      app.findAuthRecordByEmail("users", p.email);
      continue;
    } catch (_) {}
    const r = new Record(users);
    r.setEmail(p.email);
    r.setPassword(PASS);
    r.setVerified(true);
    r.set("name", p.name);
    r.set("role", p.role);
    r.set("flat", p.flat);
    r.set("ntfy_topic", "gate-" + $security.randomStringWithAlphabet(24, "abcdefghijklmnopqrstuvwxyz0123456789"));
    app.save(r);
  }
}, (app) => {});
