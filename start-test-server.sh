#!/bin/sh
# Society Gate - one-click TEST server for Mac / Linux.
# Run:  sh start-test-server.sh
set -e
PB_VERSION=0.40.3
ROOT=$(cd "$(dirname "$0")" && pwd)
PB_DIR="$ROOT/backend/pocketbase"
PB="$PB_DIR/pocketbase"

echo ""
echo "============================================="
echo "   SOCIETY GATE - TEST SERVER"
echo "============================================="

if [ ! -x "$PB" ]; then
  echo "First time: downloading the server program..."
  case "$(uname -s)" in Darwin) OS=darwin ;; *) OS=linux ;; esac
  case "$(uname -m)" in arm64|aarch64) ARCH=arm64 ;; *) ARCH=amd64 ;; esac
  URL="https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_${OS}_${ARCH}.zip"
  TMP="${TMPDIR:-/tmp}/pocketbase-download.zip"
  curl -fsSL "$URL" -o "$TMP"
  unzip -o -q "$TMP" pocketbase -d "$PB_DIR"
  rm -f "$TMP"
  chmod +x "$PB"
  [ "$OS" = darwin ] && xattr -d com.apple.quarantine "$PB" 2>/dev/null || true
fi

IP=""
if [ "$(uname -s)" = Darwin ]; then
  IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
else
  IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
[ -z "$IP" ] && IP="YOUR-LAPTOP-IP"
SERVER="http://$IP:8090"

export TEST_MODE=1 NTFY_URL=https://ntfy.sh NTFY_PUBLIC_URL=https://ntfy.sh PUBLIC_URL="$SERVER" EXPIRE_MINUTES=2

echo ""
echo "---------------------------------------------"
echo " ON YOUR PHONE, TYPE THIS SERVER ADDRESS:"
echo ""
echo "     $SERVER"
echo ""
echo " Test logins (password for all: Test12345)"
echo "     Resident of house 245 : res245@test.com"
echo "     Guard                 : guard@test.com"
echo ""
echo " Admin website on this computer:"
echo "     http://localhost:8090/_/   (admin@test.com)"
echo "---------------------------------------------"
echo "KEEP THIS WINDOW OPEN while testing. Press Ctrl+C to stop."
echo ""

cd "$PB_DIR"
exec "$PB" serve --http "0.0.0.0:8090"
