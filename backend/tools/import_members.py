#!/usr/bin/env python3
"""
Bulk-create flats and accounts from a CSV (export from Excel / Google Sheets).

CSV columns (header row required):
    flat,name,email,phone,role,password
    1,Rahul Sharma,h1.rahul@example.com,9876543210,resident,
    245,Neha Sharma,h245@example.com,9876500000,resident,
    ,Gate Guard 1,guard1@example.com,9000000001,guard,Guard@1234

- flat:     house number, e.g. 245 (houses 1-400 already exist). Leave empty for guards.
- role:     resident | guard | admin
- password: optional. If empty, a random one is generated and printed.
            Email can be a fake one like h245@mysociety.local – it's just a login id.

Usage:
    python3 import_members.py https://mysociety.duckdns.org admin@email.com 'superuser-password' members.csv
Writes credentials to members_credentials.csv – share each person's login with them.
"""
import csv, json, secrets, string, sys, urllib.error, urllib.request

if len(sys.argv) != 5:
    sys.exit(__doc__)
BASE, ADMIN, ADMIN_PW, CSV_FILE = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3], sys.argv[4]


def call(method, path, body=None, token=None):
    req = urllib.request.Request(
        BASE + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json", **({"Authorization": token} if token else {})},
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code}: {e.read().decode()}") from None


token = call("POST", "/api/collections/_superusers/auth-with-password",
             {"identity": ADMIN, "password": ADMIN_PW})["token"]

flats = {f["label"]: f["id"] for f in call("GET", "/api/collections/flats/records?perPage=1000", token=token)["items"]}

out = []
with open(CSV_FILE, newline="", encoding="utf-8-sig") as fh:
    for row in csv.DictReader(fh):
        row = {k.strip().lower(): (v or "").strip() for k, v in row.items()}
        flat_id = ""
        label = row.get("flat", "")
        if label:
            if label not in flats:
                block, _, number = label.partition("-")
                rec = call("POST", "/api/collections/flats/records",
                           {"label": label, "block": block if number else "", "number": number or label}, token)
                flats[label] = rec["id"]
                print(f"+ flat {label}")
            flat_id = flats[label]
        pw = row.get("password") or "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(10))
        try:
            call("POST", "/api/collections/users/records", {
                "email": row["email"], "emailVisibility": False, "name": row.get("name", ""),
                "phone": row.get("phone", ""), "role": row.get("role", "resident") or "resident",
                "flat": flat_id, "password": pw, "passwordConfirm": pw, "verified": True,
            }, token)
            print(f"+ user {row['email']} ({row.get('role') or 'resident'} {label})")
            out.append({"name": row.get("name", ""), "flat": label, "login": row["email"], "password": pw})
        except RuntimeError as e:
            print(f"! skipped {row.get('email')}: {e}")

with open("members_credentials.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["name", "flat", "login", "password"])
    w.writeheader()
    w.writerows(out)
print(f"\nDone. {len(out)} accounts created → members_credentials.csv (keep it private)")
