# 🚪 Society Gate

Free, 100% open-source visitor approval system for housing societies.
Guard logs a visitor → residents of that flat get a **loud push notification with Approve / Deny buttons** → guard sees the answer instantly.

No subscription, no ads, no per-flat fees, no Google/Firebase dependency. Your society owns the data.

---

## Features

| Guard app | Resident app |
|---|---|
| Step 1: type **house number** on a big keypad (shows who lives there) · Step 2: visitor name, mobile, purpose, vehicle, people count, photo | Push alert even when phone is locked/app closed |
| Live status: **ALLOW / DENY / LEAVE AT GATE / NO RESPONSE** | Approve / Deny / Leave-at-gate **from the notification itself** |
| One-tap call to residents of the flat | Full visitor history with photos & times |
| Verify **6-digit pre-approved pass** (no call needed) | Create guest passes (4h / 1 day / 3 days / 1 week, single or multi-entry), share on WhatsApp |
| "Inside" list + mark exit | Call the visitor directly |
| Auto-alert if resident doesn't answer in 10 min | Multiple residents per flat all get the alert; first answer wins |

Security built in: residents only see their own flat; approve links in notifications are one-time tokens; push channels are private random IDs; only the admin creates accounts.

## Architecture (all open source)

```
 Guard phone ──┐                       ┌── Resident phone (Society Gate app)
 (Flutter app) │   HTTPS + realtime    │
               ▼                       │
        ┌─────────────┐  publish   ┌───────┐  push   ┌── Resident phone (ntfy app:
        │ PocketBase  │──────────▶│ ntfy  │────────▶│   notification with
        │ DB+API+auth │◀──────────┴───────┘         │   Approve/Deny buttons)
        └─────────────┘  button tap calls API        
           Caddy (free HTTPS via Let's Encrypt)
```

- **App:** Flutter (Android) – `app/`
- **Backend:** PocketBase (SQLite, auth, realtime, file storage, admin dashboard) – `backend/pocketbase/`
- **Push:** ntfy, self-hosted – works without Google services
- **HTTPS:** Caddy

## Total cost: ₹0

| Need | Free option |
|---|---|
| Server | Oracle Cloud "Always Free" VM (ARM, 24 GB RAM) **or** any old PC/Raspberry Pi in the society office |
| Domain | DuckDNS (`yoursociety.duckdns.org`) |
| APK builds | GitHub Actions (free for public repos) |

A 500-flat society uses well under 1 GB of disk per year (photos compressed to ~100 KB).

---

## Setup (≈30 minutes, one time)

### 1. Get a server and two free names
1. Create a free VM (Oracle Cloud Always Free, Ubuntu). Open ports **80** and **443** in its security list and in `sudo iptables`/`ufw`.
2. At **duckdns.org** create two names pointing to the VM's public IP, e.g.
   `mysociety.duckdns.org` and `mysociety-push.duckdns.org`.

### 2. Start the backend
```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2 git
git clone https://github.com/<you>/society-gate.git && cd society-gate/backend
cp .env.example .env && nano .env        # set DOMAIN and PUSH_DOMAIN
sudo docker compose up -d --build
```
Create the admin login for the dashboard:
```bash
sudo docker compose exec pocketbase /pb/pocketbase superuser upsert secretary@email.com 'StrongPassword' --dir=/pb/pb_data
```
Dashboard: `https://mysociety.duckdns.org/_/`

### 3. Add members
Houses **1 to 400** are created automatically on first start (change `HOUSE_COUNT` in `.env` for a different count).

**Easiest – bulk import from Excel/Google Sheet:** fill `backend/tools/members_template.csv` (column `flat` = house number), then:
```bash
python3 tools/import_members.py https://mysociety.duckdns.org secretary@email.com 'StrongPassword' members.csv
```
It writes everyone's login to `members_credentials.csv`.
Logins can be fake emails like `h245@mysociety.local` – no email server needed.

**Or manually:** Dashboard → `users` → New record (role, flat = house number, phone, password).

### 4. Build the APK (free, on GitHub)
1. Push this folder to a GitHub repo.
2. *(Recommended, once)* create a permanent signing key so updates install over old versions:
   ```bash
   keytool -genkeypair -v -keystore gate.keystore -alias androiddebugkey -storepass android -keypass android \
     -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Society Gate"
   base64 -w0 gate.keystore      # copy output
   ```
   Repo → Settings → Secrets → Actions → New secret `SIGNING_KEYSTORE_BASE64` = that output. Keep `gate.keystore` safe.
3. Actions tab → **Build APK** runs automatically. Download `society-gate.apk` from the run,
   or push a tag (`git tag v1.0.0 && git push --tags`) to get a permanent download link on the Releases page.
4. Share the APK link in the society WhatsApp group. (Android will ask to "allow install from this source" once.)

Build locally instead: install Flutter, then in `app/`:
`flutter create --platforms=android --org org.societygate --project-name society_gate . && python3 tool/patch_android.py && flutter build apk --release`

### 5. Each person on their phone (2 minutes)
1. Install **Society Gate** APK → log in with server `mysociety.duckdns.org` + their login.
2. Settings → **Install ntfy** (free, open-source, on Play Store & F-Droid) → **Subscribe** → **Test**.
3. In ntfy, long-press the channel → set **Max priority** and allow it to bypass Do Not Disturb.
4. Android Settings → Apps → ntfy → Battery → **Unrestricted** (important on Xiaomi/Oppo/Vivo/Realme).

Guards: put the gate phone on charge, keep the app open on the Gate screen.

---

## Daily flow
1. Visitor arrives → guard taps **New visitor** → types the house number (e.g. 245) on the keypad and checks the resident name shown → **Next** → enters name/mobile/purpose (photo optional) → **Send for approval**.
2. All residents of that house get an alert: *"🔔 Ramesh is at the gate (House 245) – Delivery · Amazon"* with **✅ Approve / ❌ Deny / 📦 Leave at gate**.
3. Guard's screen turns green **ALLOW ENTRY** or red **DENIED** instantly. No answer in 10 min → **NO RESPONSE** + alert to guard (guard can tap to call resident).
4. Expected guest? Resident creates a pass → shares the 6-digit code → guard taps 🔢 and types the code → entry approved, resident gets an FYI.

## Configuration (`backend/.env`)
| Variable | Default | Meaning |
|---|---|---|
| `DOMAIN` | – | Address of the API/dashboard |
| `PUSH_DOMAIN` | – | Address of the ntfy push server |
| `EXPIRE_MINUTES` | 10 | Mark unanswered requests as "No response" after this |
| `HOUSE_COUNT` | 400 | Houses 1..N are created automatically |

## Maintenance
- **Backups:** Dashboard → Settings → Backups (schedule daily, optionally to free S3-compatible storage), or copy `backend/data/`.
- **Update:** `git pull && sudo docker compose up -d --build`.
- **Remove a member who moved out:** Dashboard → users → delete. Their app logs out on next refresh.

## Project layout
```
backend/
  docker-compose.yml        PocketBase + ntfy + Caddy
  pocketbase/pb_migrations/ database schema & access rules
  pocketbase/pb_hooks/      approval logic, push, passes, auto-expiry
  tools/import_members.py   bulk onboarding from CSV
app/
  lib/                      Flutter app (guard + resident in one APK, by role)
  tool/patch_android.py     Android permissions/labels
.github/workflows/build-apk.yml   free cloud APK builds
```

## API (for anyone extending it)
| Method & path | Who | Purpose |
|---|---|---|
| `POST /api/collections/visits/records` | guard | create visit (`flat`, `visitor_name`, `visitor_phone`, `purpose`, … or `pass_code`) |
| `POST /api/gate/visits/{id}/decide` `{decision}` | resident of flat / one-time token | `approved` · `denied` · `leave_at_gate` |
| `POST /api/gate/visits/{id}/checkout` | guard | mark exit |
| `POST /api/collections/passes/records` | resident | create pass (code generated by server) |
| `GET /api/gate/me/push` · `POST /api/gate/me/push-test` | any user | push channel info / test alert |

## Ideas for next versions
Daily-help (maid/driver) attendance, society notice board, multi-gate support, parcel log, iOS build (Flutter code already supports it; ntfy has an iOS app).

## License
MIT – free to use, modify and share. Built on PocketBase (MIT), ntfy (Apache-2.0/GPL-2.0), Caddy (Apache-2.0), Flutter (BSD).
