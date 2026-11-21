#!/usr/bin/env bash
# A real TLS handshake and TCP upload through two copies of the candidate. Loopback only.
set -euo pipefail
binary=$(realpath "$1")
scratch=$(mktemp -d)
cd "$scratch"
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    wait || true
    rm -rf -- "$scratch"
}
trap cleanup EXIT
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
    -keyout key.pem -out cert.pem -subj /CN=localhost -addext subjectAltName=DNS:localhost 2>/dev/null
cat > server.yaml <<'EOF'
listen: 127.0.0.1:24893
tls: {cert: cert.pem, key: key.pem}
auth: {type: password, password: loopback-test}
connectionAudit: true
EOF
cat > client.yaml <<'EOF'
server: 127.0.0.1:24893
auth: loopback-test
tls: {sni: localhost, ca: cert.pem}
bandwidth: {up: 40 mbps, down: 40 mbps}
tcpForwarding:
  - {listen: '127.0.0.1:24894', remote: '127.0.0.1:24895'}
EOF
python3 -u - <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
from hashlib import sha256
class Sink(BaseHTTPRequestHandler):
    def do_POST(self):
        digest = sha256(self.rfile.read(int(self.headers['Content-Length']))).hexdigest()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(digest.encode())
HTTPServer(('127.0.0.1', 24895), Sink).serve_forever()
PY
pids+=("$!")
"$binary" server -c server.yaml --log-format json --disable-update-check >server.log 2>&1 & pids+=("$!")
for _ in {1..100}; do
    kill -0 "${pids[1]}"
    if grep -q 'server up and running' server.log; then break; fi
    sleep .1
done
"$binary" client -c client.yaml --disable-update-check >client.log 2>&1 & pids+=("$!")
head -c 131072 /dev/urandom > body
actual=$(curl --noproxy '*' --fail --silent --show-error --retry 12 --retry-connrefused \
    --retry-delay 1 --retry-max-time 20 --max-time 5 --data-binary @body http://127.0.0.1:24894/) || {
    cat server.log client.log >&2; exit 1;
}
test "$actual" = "$(sha256sum body | cut -d' ' -f1)"
python3 - <<'PY'
import json, time
from pathlib import Path
for _ in range(50):
    events = [json.loads(line) for line in Path('server.log').read_text().splitlines()]
    events = [e for e in events if e.get('schema') == 'hy2-flow-v1']
    if any(e['event'] == 'close' for e in events):
        break
    time.sleep(.1)
assert len(events) == 2, events
assert [e['event'] for e in events] == ['open', 'close'], events
assert events[0]['flow_id'] == events[1]['flow_id'], events
assert events[0]['remote_addr'] == '127.0.0.1:24895', events
assert events[0]['client_addr'].startswith('127.0.0.1:'), events
assert events[0]['local_addr'].startswith('127.0.0.1:'), events
assert not any('auth' in k or 'password' in k for e in events for k in e), events
PY
echo 'Loopback HY2 handshake and 128 KiB upload passed.'
