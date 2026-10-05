/// <reference path="../pb_data/types.d.ts" />
// Creates houses 1..HOUSE_COUNT (default 400) so the admin doesn't have to add them by hand.
// Safe to run on an existing database: houses that already exist are skipped.

migrate((app) => {
  const count = parseInt($os.getenv("HOUSE_COUNT") || "400", 10) || 400;
  const flats = app.findCollectionByNameOrId("flats");

  for (let n = 1; n <= count; n++) {
    const label = String(n);
    try {
      app.findFirstRecordByFilter("flats", "label = {:l}", { l: label });
      continue; // already exists
    } catch (_) {}
    const rec = new Record(flats);
    rec.set("label", label);
    rec.set("number", label);
    app.save(rec);
  }
}, (app) => {
  // no-op: never delete houses on rollback (they may have residents and visits)
});
