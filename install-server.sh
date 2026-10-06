#!/usr/bin/env bash
# =====================================================================
#  Society Gate - one-command LIVE server installer (Ubuntu, e.g. Oracle Cloud free VM)
#
#  Usage (on the server):
#    curl -fsSL https://raw.githubusercontent.com/ShubhJoshi1108/society-gate/main/install-server.sh \
#      | sudo bash -s -- <duckdns-name> <duckdns-token> <admin-email>
#
#  Example:
#    ... | sudo bash -s -- greenvalley 1a2b3c4d-.... secretary@gmail.com
#
#  Needs two DuckDNS names already created:  <name>  and  <name>-push
#  Safe to run again (e.g. to update): it keeps all data.
# =====================================================================
set -euo pipefail

# Everything runs inside main() so that commands reading input can never
# swallow the rest of this script when it is piped from curl.
main() {

NAME="${1:-}"; TOKEN="${2:-}"; ADMIN_EMAIL="${3:-}"
REPO_URL="${REPO_URL:-https://github.com/ShubhJoshi1108/society-gate.git}"
DIR=/opt/society-gate

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || fail "Run with sudo (see usage at the top of this file)."
[ -n "$NAME" ] && [ -n "$TOKEN" ] && [ -n "$ADMIN_EMAIL" ] || fail "Usage: ... | sudo bash -s -- <duckdns-name> <duckdns-token> <admin-email>"
NAME="${NAME%.duckdns.org}"
DOMAIN="$NAME.duckdns.org"
PUSH_DOMAIN="$NAME-push.duckdns.org"

say "1/7  Pointing $DOMAIN and $PUSH_DOMAIN to this server"
apt-get update -qq >/dev/null
apt-get install -y -qq curl git python3 openssl >/dev/null
if [ "${SKIP_DUCKDNS:-0}" = 1 ]; then RESULT=OK; else
  RESULT=$(curl -fsS "https://www.duckdns.org/update?domains=${NAME},${NAME}-push&token=${TOKEN}&ip=" || true)
fi
[ "$RESULT" = "OK" ] || fail "DuckDNS said '$RESULT'. Check the token, and that BOTH names '$NAME' and '$NAME-push' exist in your DuckDNS account."
# keep the address correct even if the server's IP ever changes
[ "${SKIP_DUCKDNS:-0}" = 1 ] || echo "*/5 * * * * root curl -fsS 'https://www.duckdns.org/update?domains=${NAME},${NAME}-push&token=${TOKEN}&ip=' >/dev/null 2>&1" > /etc/cron.d/society-gate-duckdns

# Small free servers (1 GB, e.g. Oracle VM.Standard.E2.1.Micro) need extra swap memory
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [ "$MEM_MB" -lt 2000 ] && ! swapon --show | grep -q /swapfile; then
  echo "Small server ($MEM_MB MB RAM): adding 2 GB of swap memory"
  fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  if chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile; then
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  else
    echo "Could not add swap memory; continuing anyway"
  fi
fi

say "2/7  Installing Docker (first time takes a few minutes)"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh >/dev/null
fi
systemctl enable --now docker >/dev/null 2>&1 || true

say "3/7  Opening web ports 80 and 443 on this server"
for p in 80 443; do
  iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport "$p" -j ACCEPT
done
if command -v netfilter-persistent >/dev/null 2>&1; then netfilter-persistent save >/dev/null 2>&1 || true; fi
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q active; then ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; fi

say "4/7  Downloading Society Gate"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull -q --ff-only
else
  git clone -q --depth 1 "$REPO_URL" "$DIR"
fi
cd "$DIR/backend"
cat > .env <<EOF
DOMAIN=$DOMAIN
PUSH_DOMAIN=$PUSH_DOMAIN
EXPIRE_MINUTES=10
HOUSE_COUNT=${HOUSE_COUNT:-400}
EOF

say "5/7  Starting the server"
docker compose up -d --build --remove-orphans </dev/null
printf 'Waiting for the server to start'
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8090/api/health >/dev/null 2>&1; then break; fi
  printf '.'; sleep 2
done
echo
curl -fsS http://127.0.0.1:8090/api/health >/dev/null 2>&1 || fail "Server did not start. Run: cd $DIR/backend && sudo docker compose logs pocketbase"

say "6/7  Creating logins"
LOGINS=/root/society-gate-logins.txt
gen() { openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 12; }
ADMIN_PASS=$(gen)
docker compose exec -T pocketbase /pb/pocketbase superuser upsert "$ADMIN_EMAIL" "$ADMIN_PASS" --dir=/pb/pb_data </dev/null >/dev/null

GUARD_PASS=$(gen); RES_PASS=$(gen)
DEMO=$(ADMIN_EMAIL="$ADMIN_EMAIL" ADMIN_PASS="$ADMIN_PASS" GUARD_PASS="$GUARD_PASS" RES_PASS="$RES_PASS" python3 - <<'PY'
import json, os, urllib.parse, urllib.request, urllib.error
B = "http://127.0.0.1:8090"
def call(method, path, body=None, token=None):
    req = urllib.request.Request(B + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json", **({"Authorization": token} if token else {})})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or b"{}")
tok = call("POST", "/api/collections/_superusers/auth-with-password",
           {"identity": os.environ["ADMIN_EMAIL"], "password": os.environ["ADMIN_PASS"]})["token"]
house = call("GET", "/api/collections/flats/records?filter=label%3D%27245%27", token=tok)["items"][0]["id"]
out = []
for email, name, role, flat, pw in [
    ("guard@test.com", "Test Guard", "guard", "", os.environ["GUARD_PASS"]),
    ("res245@test.com", "Test Resident", "resident", house, os.environ["RES_PASS"]),
]:
    try:
        call("POST", "/api/collections/users/records", {"email": email, "password": pw, "passwordConfirm": pw,
             "name": name, "role": role, "flat": flat, "verified": True}, tok)
        out.append(f"{email} / {pw}")
    except urllib.error.HTTPError:
        # already there (installer run again): give it a fresh password
        uid = call("GET", "/api/collections/users/records?filter=" + urllib.parse.quote(f"email='{email}'"), token=tok)["items"][0]["id"]
        call("PATCH", f"/api/collections/users/records/{uid}", {"password": pw, "passwordConfirm": pw}, tok)
        out.append(f"{email} / {pw}")
print("\n".join(out))
PY
)

cat > "$LOGINS" <<EOF
Society Gate logins (created $(date))

Server address for the app : $DOMAIN
Admin website              : https://$DOMAIN/_/
Admin login                : $ADMIN_EMAIL / $ADMIN_PASS

Test logins (delete them in the admin website when you go live):
$DEMO
EOF
chmod 600 "$LOGINS"

say "7/7  Getting the free HTTPS certificate (up to 2 minutes)"
for _ in $(seq 1 40); do
  if curl -fsS "https://$DOMAIN/api/health" >/dev/null 2>&1; then OK=1; break; fi
  sleep 3
done

echo
echo "=============================================================="
echo "  SOCIETY GATE IS LIVE"
echo "=============================================================="
echo
echo "  ON EVERY PHONE, TYPE THIS SERVER ADDRESS:   $DOMAIN"
echo
echo "  Admin website:  https://$DOMAIN/_/"
echo "  Admin login:    $ADMIN_EMAIL"
echo "  Admin password: $ADMIN_PASS"
echo
echo "  Test logins:"
echo "$DEMO" | sed 's/^/    /'
echo
if [ "${OK:-0}" != 1 ]; then
  echo "  NOTE: https://$DOMAIN is not answering yet. Usually this means"
  echo "  ports 80/443 are not open in Oracle's Security List (see the guide)."
  echo "  Fix that, then run this same command again."
  echo
fi
echo "  These details are saved in $LOGINS"
echo "  (show them again with:  sudo cat $LOGINS )"
echo "=============================================================="
}

main "$@"
