"""Live Docker stack verification for everything implemented so far."""
import base64
import json
import time
import urllib.error
import urllib.request

BASE = "http://localhost:8080"


def req(method, path, body=None, headers=None, timeout=15):
    if body is None:
        data = None
    elif isinstance(body, (bytes, bytearray)):
        data = body
    else:
        data = json.dumps(body).encode()
    h = {"Content-Type": "application/json"}
    if headers:
        h.update(headers)
    request = urllib.request.Request(BASE + path, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            raw = resp.read()
            return resp.status, {k: v for k, v in resp.headers.items()}, (
                json.loads(raw) if raw else None
            )
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            j = json.loads(raw) if raw else None
        except Exception:
            j = raw.decode("utf-8", "replace")
        return e.code, {k: v for k, v in e.headers.items()}, j


results = []


def check(name, cond, detail=""):
    results.append((bool(cond), name, detail))
    print(("PASS" if cond else "FAIL"), "-", name + (f" | {detail}" if detail and not cond else ""))


# 1) Health
st, _, body = req("GET", "/health")
check("GET /health == 200 {status:ok}", st == 200 and body == {"status": "ok"}, f"{st} {body}")

# 2) Reset twice identical
st1, _, b1 = req("POST", "/audit/v1/reset", {})
st2, _, b2 = req("POST", "/audit/v1/reset", {})
check(
    "POST /reset twice identical",
    st1 == 200 and b1 == b2 and b1.get("status") == "reset_complete",
    str(b1),
)

# 3) Ping
st, _, body = req("GET", "/api/v1/ping")
check("GET /api/v1/ping", st == 200 and body == {"pong": True}, f"{st} {body}")

# 4) Login all 5 demo accounts
for email, role in [
    ("admin@nascon.test", "super_admin"),
    ("organizer@nascon.test", "league_organizer"),
    ("manager@nascon.test", "club_manager"),
    ("player@nascon.test", "player"),
    ("viewer@nascon.test", "viewer"),
]:
    st, _, body = req("POST", "/api/v1/auth/login", {"email": email, "password": "Nascon@26"})
    ok = st == 200 and body and body.get("user", {}).get("role") == role and body.get("access_token")
    check(f"login {email}", ok, f"{st} {body}")

st, _, body = req("POST", "/api/v1/auth/login", {"email": "admin@nascon.test", "password": "wrong"})
check(
    "login bad password -> 401 UNAUTHENTICATED",
    st == 401 and body["error"]["code"] == "UNAUTHENTICATED",
)

# 5) rbac-matrix
st, _, matrix = req("POST", "/audit/v1/rbac-matrix", {})
check(
    "rbac-matrix 200 with 5 tokens",
    st == 200
    and set(matrix["tokens"])
    == {"super_admin", "league_organizer", "club_manager", "player", "viewer"},
    f"{st}",
)
tokens = matrix["tokens"]
ctx = matrix["context"]

# 6) Full P1-P7 matrix
EXPECTED = {
    ("P1", None): {"super_admin": 200},
    ("P2", "own_league_id"): {"super_admin": 200, "league_organizer": 200},
    ("P2", "other_league_id"): {"super_admin": 200},
    ("P2", "foreign_league_id"): {"super_admin": 200},
    ("P3", "own_club_id"): {"super_admin": 200, "club_manager": 200},
    ("P3", "other_club_id"): {"super_admin": 200},
    ("P3", "foreign_club_id"): {"super_admin": 200},
    ("P4", "own_club_id"): {"super_admin": 200, "club_manager": 200},
    ("P4", "other_club_id"): {"super_admin": 200},
    ("P4", "foreign_club_id"): {"super_admin": 200},
    ("P5", "own_player_id"): {"super_admin": 200, "club_manager": 200, "player": 200},
    ("P5", "other_player_id"): {"super_admin": 200},
    ("P5", "foreign_player_id"): {"super_admin": 200},
    ("P6", "own_club_id"): {r: 200 for r in tokens},
    ("P6", "other_club_id"): {r: 200 for r in tokens},
    ("P6", "foreign_club_id"): {"super_admin": 200},
    ("P7", None): {"super_admin": 200},
}


def path_for(probe, key):
    if probe == "P1":
        return "POST", "/audit/v1/rbac/tenants"
    if probe == "P2":
        return "POST", f"/audit/v1/rbac/leagues/{ctx[key]}/fixtures"
    if probe == "P3":
        return "POST", f"/audit/v1/rbac/clubs/{ctx[key]}/roster"
    if probe == "P4":
        return "POST", f"/audit/v1/rbac/clubs/{ctx[key]}/products"
    if probe == "P5":
        return "PATCH", f"/audit/v1/rbac/players/{ctx[key]}"
    if probe == "P6":
        return "GET", f"/audit/v1/rbac/clubs/{ctx[key]}"
    if probe == "P7":
        return "GET", "/audit/v1/rbac/platform/config"
    raise ValueError(probe)


matrix_fail = 0
for (probe, key), allowed in EXPECTED.items():
    method, path = path_for(probe, key)
    for role, token in tokens.items():
        expect = allowed.get(role, 403)
        st, _, body = req(
            method,
            path,
            {} if method in ("POST", "PATCH") else None,
            headers={"Authorization": f"Bearer {token}"},
        )
        if st != expect:
            matrix_fail += 1
            print(f"FAIL - {probe} {key} {role}: got {st} want {expect} body={body}")
check(f"P1-P7 full matrix ({len(EXPECTED) * 5} cells)", matrix_fail == 0, f"failures={matrix_fail}")

# 7) Security probes
st, _, body = req("GET", "/audit/v1/rbac/platform/config")
check("P7 no auth -> 401", st == 401 and body["error"]["code"] == "UNAUTHENTICATED")

hdr = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b"=").decode()
pld = (
    base64.urlsafe_b64encode(
        json.dumps({"sub": "x", "role": "super_admin", "exp": int(time.time()) + 3600}).encode()
    )
    .rstrip(b"=")
    .decode()
)
st, _, body = req(
    "GET",
    "/audit/v1/rbac/platform/config",
    headers={"Authorization": f"Bearer {hdr}.{pld}."},
)
check("P7 alg:none -> 401", st == 401 and body["error"]["code"] == "UNAUTHENTICATED")

tok = tokens["super_admin"]
parts = tok.split(".")
bad = ".".join([parts[0], parts[1], parts[2][:-1] + ("A" if not parts[2].endswith("A") else "B")])
st, _, body = req(
    "GET",
    "/audit/v1/rbac/platform/config",
    headers={"Authorization": f"Bearer {bad}"},
)
check("P7 tampered -> 401", st == 401 and body["error"]["code"] == "UNAUTHENTICATED")

cross_ok = True
for role in ("league_organizer", "club_manager", "player", "viewer"):
    st, _, body = req(
        "GET",
        f"/audit/v1/rbac/clubs/{ctx['foreign_club_id']}",
        headers={"Authorization": f"Bearer {tokens[role]}"},
    )
    if st != 403 or body["error"]["code"] != "FORBIDDEN":
        cross_ok = False
        print(f"FAIL cross-tenant {role}: {st} {body}")
check("cross-tenant foreign club always 403", cross_ok)

# 8) 413 payload — reject on Content-Length without uploading 1MB+
st, _, body = req(
    "POST",
    "/audit/v1/reset",
    body=b"{}",
    headers={"Content-Type": "application/json", "Content-Length": str(1024 * 1024 + 1)},
)
check("body >1MB -> 413", st == 413 and body["error"]["code"] == "PAYLOAD_TOO_LARGE", f"{st} {body}")

# 9) Rate limit burst (unique X-Forwarded-For so workers share one bucket)
ip = f"198.51.100.{int(time.time()) % 200}"
codes = []
retry_ok = False
for i in range(150):
    st, hdrs, body = req("GET", "/api/v1/ping", headers={"X-Forwarded-For": ip})
    codes.append(st)
    if st == 429 and not retry_ok:
        retry_ok = any(k.lower() == "retry-after" for k in hdrs)
ok200 = codes.count(200)
ok429 = codes.count(429)
check("101st+ has Retry-After", retry_ok)
check(
    f"rate limit 150 req: 200s={ok200} 429s={ok429} (want 100 / >=40)",
    ok200 == 100 and ok429 >= 40,
    f"codes200={ok200} codes429={ok429}",
)

st, _, _ = req("POST", "/audit/v1/rbac-matrix", {}, headers={"X-Forwarded-For": ip})
check("audit exempt while /api limited", st == 200)

st, _, _ = req("GET", "/health", headers={"X-Forwarded-For": ip})
check("health exempt while /api limited", st == 200)

# 10) unknown route error body
st, _, body = req("GET", "/does-not-exist")
check(
    "unknown route error shape",
    st == 404 and set(body["error"]) == {"code", "message", "details"},
)

passed = sum(1 for ok, _, _ in results if ok)
failed = sum(1 for ok, _, _ in results if not ok)
print("\n=== LIVE DOCKER SUMMARY ===")
print(f"passed={passed} failed={failed} total={len(results)}")
for ok, name, detail in results:
    if not ok:
        print("FAIL:", name, detail)
raise SystemExit(0 if failed == 0 else 1)
