#!/bin/bash
# dev-up reuse path: a server already running for this checkout is probed before
# dev-up reports success (broken one -> exit 1, never auto-restarted), and a failing
# `portless list` is a loud error, not "nothing running". Stubbed portless/tailscale,
# a real local HTTP server whose cwd is the temp checkout.
set -eu

dev_up="$(cd "$(dirname "$0")/.." && pwd)/dev-up"
tmp="$(mktemp -d)"
pids=""
cleanup() { for p in $pids; do kill "$p" 2>/dev/null || true; done; rm -rf "$tmp"; }
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

repo="$tmp/repo"; mkdir -p "$repo" "$tmp/bin"
git -C "$repo" init -q
printf '#!/bin/sh\n' > "$repo/start_dev.sh"; chmod +x "$repo/start_dev.sh"
cat > "$tmp/server.py" <<'PY'
import http.server, sys
status, portfile = int(sys.argv[1]), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(status); self.end_headers()
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
open(portfile, "w").write("%s %s" % (srv.server_port, __import__("os").getpid()))
srv.serve_forever()
PY
# tailscale/dev-url are only checked for existence; portless list is driven by files.
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/tailscale"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/dev-url"
cat > "$tmp/bin/portless" <<'STUB'
#!/bin/sh
[ "$1" = list ] || exit 0
[ -e "$PORTLESS_FAIL" ] && { echo "portless: proxy unreachable" >&2; exit 1; }
[ -r "$PORTLESS_ROUTE" ] && cat "$PORTLESS_ROUTE"
exit 0
STUB
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" DEV_LEASE_DIR="$tmp/leases" DEV_UP_REUSE_TIMEOUT=2
export PORTLESS_FAIL="$tmp/portless-fail" PORTLESS_ROUTE="$tmp/route"

serve() {  # serve <status>: server with cwd = repo, writes route file for portless list
  rm -f "$tmp/port"
  (cd "$repo" && exec python3 "$tmp/server.py" "$1" "$tmp/port") >/dev/null 2>&1 &
  i=0; while [ ! -s "$tmp/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  read -r port pid < "$tmp/port" || true; pids="$pids $pid"
  printf 'app (pid %s)\n  tailscale: http://127.0.0.1:%s\n' "$pid" "$port" > "$PORTLESS_ROUTE"
}
run() { out="$(cd "$repo" && "$dev_up" 2>&1)" && rc=0 || rc=$?; }

serve 200
run
[ "$rc" -eq 0 ] || fail "healthy reuse: exit $rc ($out)"
case "$out" in *reused*) ;; *) fail "healthy reuse: no 'reused' ($out)" ;; esac
kill "$pid"

serve 500
run
[ "$rc" -eq 1 ] || fail "HTTP 500 reuse: exit $rc, want 1 ($out)"
case "$out" in *"answers HTTP 500"*"Not restarting"*) ;; *) fail "HTTP 500 reuse: unclear message ($out)" ;; esac
case "$out" in *reused*) fail "HTTP 500 reuse reported success ($out)" ;; esac
kill "$pid"

: > "$PORTLESS_FAIL"
run
[ "$rc" -eq 2 ] || fail "portless list failure: exit $rc, want 2 ($out)"
case "$out" in *"portless list failed"*) ;; *) fail "portless list failure: unclear message ($out)" ;; esac

echo "dev-up tests: ok"
