# NaSCon team infrastructure handoff

Prepared 17 October 2026, Pakistan time. Share this file with Claude, Codex,
Cursor and the human teammates working on their own laptops.

## Purpose and current limits

One Windows laptop hosts a temporary Docker service lab. Other laptops develop
code locally and connect to these services through a shared phone hotspot or
router. The `nascon-lan-*` names were assigned by our setup script; they do not
identify software built by NaSCon.

This document describes the existing readiness lab, not a competition solution.
Do not assume every downloaded service is required by the eventual problem.
The booklet says some images are decoys. Select services after reading the task.

No competition app backend has been deployed. Port 8000 is only Python's built-in
sample HTTP file server. Do not mistake its response for a working application API.

## Network: read this before using any endpoint

- Current server laptop Wi-Fi IPv4 address: **10.27.87.243**.
- Last reported subnet mask: **255.255.255.0** (network 10.27.87.0/24).
- Last reported hotspot gateway: **10.27.87.183**. The gateway is not the server.
- All team laptops and the test phone must join the same hotspot/router.
- The hotspot may have no Internet. Local service access still works if clients
  can communicate with each other. Ping between laptops was reported working.
- Campus Wi-Fi may isolate clients. Some phone hotspots can also isolate clients.
- The server address is DHCP-assigned and can change after reconnection or reboot.
  Confirm it using `ipconfig` on the server. Use its physical Wi-Fi adapter address,
  not 172.18.64.1, 172.21.32.1 or 192.168.56.1 from virtual adapters.
- Published ports are bound specifically to the selected server IPv4 address.
  Use `10.27.87.243` even when checking from the server laptop; do not assume
  `localhost` will reach ports bound to this address.
- A teammate's `localhost` is that teammate's own computer, not this server.
- Container names resolve inside Docker network `nascon-readiness-lan` only.
  Teammate laptops must use the server IP and published host ports.

AI assistants need a local terminal/executor on the teammate laptop to reach
these LAN addresses. A cloud-only agent cannot automatically reach this private
network merely because a person can use it. AI chat/API access and GitHub pushes
still require Internet separately; the offline hotspot supplies only local access.

The Docker control API has NOT been exposed to the network. Do not expose port
2375 or make the Docker socket public. Connecting to a service does not grant
remote shell access or permission to manage its containers. No SSH server or
remote deployment mechanism has been configured; ask the server operator to run
Docker commands when required.

## Credentials: not included in this shared document

The launcher generated credentials in this file on the SERVER laptop:

```text
C:\Users\Wali\Documents\Codex\2026-10-16\referenced-chatgpt-conversation-this-is-an\outputs\service-lab-state.json
```

Fields: `ip`, `username`, `password`, `livekit_api_key`, `livekit_api_secret`,
`tcp_ports`, `udp_ports`, and `containers`.

Ask the server operator to provide the credentials privately. Do not commit that
JSON file, passwords, LiveKit secrets, or a populated `.env` file. This document
contains placeholders only. The generated shared password applies to PostgreSQL,
Redis, MinIO, RabbitMQ, NATS and Grafana, with the username exceptions below.
Credentials change when the launcher recreates the lab.

Example environment variables for a teammate's local application process:

```dotenv
SERVICE_HOST=10.27.87.243
DATABASE_URL=postgresql://team:REPLACE_PASSWORD@10.27.87.243:5432/readiness
REDIS_URL=redis://:REPLACE_PASSWORD@10.27.87.243:6379/0
S3_ENDPOINT=http://10.27.87.243:9000
S3_ACCESS_KEY_ID=team
S3_SECRET_ACCESS_KEY=REPLACE_PASSWORD
S3_REGION=us-east-1
AMQP_URL=amqp://team:REPLACE_PASSWORD@10.27.87.243:5672/%2F
NATS_URL=nats://10.27.87.243:4222
NATS_USER=team
NATS_PASSWORD=REPLACE_PASSWORD
NTFY_BASE_URL=http://10.27.87.243:8080
LIVEKIT_URL=ws://10.27.87.243:7880
LIVEKIT_API_KEY=REPLACE_LIVEKIT_API_KEY
LIVEKIT_API_SECRET=REPLACE_LIVEKIT_API_SECRET
SELENIUM_REMOTE_URL=http://10.27.87.243:4444
```

These variable names are a suggested client convention, not variables the lab
automatically loads. Map them to the chosen framework's configuration. URL-encode
credentials if changing them to values containing reserved URL characters.
Use path-style S3 addressing with MinIO. `us-east-1` is a client-side default;
no custom MinIO region was set. Create required buckets explicitly.
Keep database/admin credentials and LiveKit signing secrets in the backend;
do not embed them in a Flutter app or public frontend. LiveKit clients need
server-generated access tokens, not the API secret.

## All 16 image entries and their configuration

The selected backend image is **python:3.12-slim**. The proposed switch to
node:20-alpine did NOT happen. Node.js is installed on the host for Appium, but
that is separate from having a Node backend Docker image.

### 1. PostgreSQL
- Image: `postgres:16-alpine`
- Container: `nascon-lan-postgres`
- Remote endpoint: `10.27.87.243:5432` TCP; container port 5432.
- Docker-network endpoint: `nascon-lan-postgres:5432`.
- User: `team`; database: `readiness`; password: shared generated password.
- Purpose: relational database. No competition schema has been prepared.
- SQL query in the earlier disposable check passed.
- A sample table named `connection_test` was suggested, but creation was not
  confirmed. Query its existence before assuming it contains sample rows.
- Remote client command (requires `psql` on the teammate laptop):

```powershell
psql -h 10.27.87.243 -p 5432 -U team -d readiness -W -c "SELECT 1;"
```

### 2. Redis
- Image: `redis:7-alpine`; container: `nascon-lan-redis`.
- Remote TCP 6379 -> container 6379; internal `nascon-lan-redis:6379`.
- Password authentication enabled with `--requirepass`.
- Use password-only AUTH or ACL username **default**, NOT `team`.
- Earlier disposable Redis PING returned PONG.
- If `redis-cli` is installed remotely: `redis-cli -h 10.27.87.243 -p 6379 --askpass PING`.

### 3. MinIO
- Required local image name: `minio/minio:RELEASE.2024-09-22T00-33-43Z`.
- Container: `nascon-lan-minio`.
- S3 API: TCP 9000 -> 9000, `http://10.27.87.243:9000`.
- Browser console: TCP 9001 -> 9001, `http://10.27.87.243:9001`.
- Internal S3 endpoint: `http://nascon-lan-minio:9000`.
- Root/access user: `team`; secret/password: shared generated password.
- Launcher explicitly uses `/usr/bin/minio` as its entrypoint and starts
  `server /data --console-address :9001`.
- Official Docker Hub pull failed. The image was downloaded from this mirror,
  then given the required local tag; this did not rebuild it:

```text
swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/minio/minio:RELEASE.2024-09-22T00-33-43Z
```

- Mirror manifest digest observed:
  `sha256:3c770f9cf8c98df2f828ff6078ee539af497fe92ccd6ea332fffb0e36080279a`.
- Mirror catalog config digest:
  `sha256:683daefd75a4b2ef32b0b8b513582c930162e1e23098d5ed3e27b6e2fee3f35e`.
- These are different digest types; do not compare them as if interchangeable.
- Version and source commit checked:
  `RELEASE.2024-09-22T00-33-43Z`, `03e996320ebb887112fb2a15c6f27936e5f124a0`.
- Corrected identity/version/startup check and `/minio/health/live` passed.
- An independent match against the original official upstream image digest has
  NOT been established. Do not claim it has.

### 4. RabbitMQ
- Image: `rabbitmq:3.13-management-alpine`; container: `nascon-lan-rabbitmq`.
- AMQP: TCP 5672 -> 5672; internal `nascon-lan-rabbitmq:5672`.
- Management UI/API: TCP 15672 -> 15672, `http://10.27.87.243:15672`.
- User `team`, shared generated password, default virtual host `/`.
- Earlier tests failed with `.erlang.cookie: eacces`. Our early root-user CLI
  probes could trigger a documented cookie-creation race during startup.
- Corrected test waits for management HTTP first, then executes diagnostics as
  user `rabbitmq`. Never start diagnostics as root while the broker is booting.
- A later Docker Desktop screenshot shows the lab RabbitMQ container running;
  a final successful result from the corrected diagnostic was not supplied.
- Host operator diagnostic, after startup:

```powershell
docker exec --user rabbitmq nascon-lan-rabbitmq rabbitmq-diagnostics -q ping
```

### 5. NATS
- Image: `nats:2.10-alpine`; container: `nascon-lan-nats`.
- Client TCP 4222 -> 4222; internal `nascon-lan-nats:4222`.
- Monitoring TCP 8222 -> 8222, `http://10.27.87.243:8222`.
- Client username `team`, shared generated password.
- Monitoring is unauthenticated in this temporary setup.
- Started with monitoring enabled. **JetStream has not been enabled.**
- Earlier `/healthz` check passed.

### 6. MediaMTX
- Image: `bluenviron/mediamtx:1.9.1`; container: `nascon-lan-mediamtx`.
- TCP host/container ports: 8554 RTSP, 1935 RTMP, 8888 HLS, 8889 WebRTC HTTP signaling.
- UDP host/container ports: 8189 WebRTC media, 8890 SRT.
- Example stream address: `rtsp://10.27.87.243:8554/STREAM_NAME`.
- Lab explicitly sets `MTX_PROTOCOLS=tcp` for RTSP and
  `MTX_WEBRTCADDITIONALHOSTS=10.27.87.243` for WebRTC candidate advertisement.
- No stream has been published or preconfigured by our setup. A publisher must
  provide media before a playback URL can be expected to work.
- Earlier RTSP OPTIONS check returned 200; actual media playback is unverified.
- No authentication configured for media publication/read in this lab.

### 7. LiveKit
- Image: `livekit/livekit-server:v1.7.2`; container: `nascon-lan-livekit`.
- API/WebSocket TCP 7880 -> 7880: `http://10.27.87.243:7880`, `ws://10.27.87.243:7880`.
- RTC TCP 7881 -> 7881; RTC UDP mux 7882 -> 7882.
- Started in development mode, binding 0.0.0.0 inside the container, advertising
  the selected host IP with `--node-ip`, and selecting UDP port 7882.
- API key and secret come from the local state JSON; no placeholder dev secret
  should be assumed.
- Earlier HTTP startup check passed. No real room, call, token flow or media
  transfer has been validated. Browser media capture may require HTTPS or another
  appropriate secure-context setup. TURN/TLS/public hosting is not configured.

### 8. ntfy
- Image: `binwiederhier/ntfy:v2.11.0`; container: `nascon-lan-ntfy`.
- TCP host **8080** -> container **80**.
- Remote base `http://10.27.87.243:8080`; internal `http://nascon-lan-ntfy:80`.
- No authentication configured. Topics chosen by clients; no competition topic exists.
- Earlier `/v1/health` check passed. Use this local instance, not ntfy.sh, offline.

### 9. Prometheus
- Image: `prom/prometheus:v2.54.1`; container: `nascon-lan-prometheus`.
- TCP 9090 -> 9090; remote `http://10.27.87.243:9090`.
- Earlier `/-/ready` passed. No application scrape targets configured.
- It is not automatically monitoring every service just because it is running.
- No authentication configured in the lab.

### 10. Grafana
- Image: `grafana/grafana:11.2.0`; container: `nascon-lan-grafana`.
- TCP 3000 -> 3000; remote `http://10.27.87.243:3000`.
- Admin username `team`, shared generated password (not admin/admin).
- Earlier `/api/health` reported database OK.
- No dashboards/data sources provisioned. To connect this instance to the lab's
  Prometheus, use `http://nascon-lan-prometheus:9090` as the data-source URL because
  Grafana makes that connection from inside Docker.

### 11. k6
- Image: `grafana/k6:0.54.0`; container/job: `nascon-lan-k6`.
- No incoming port or permanent API. It is a load-test client, not a server.
- The launcher ran a one-iteration generic HTTP check against
  `http://nascon-lan-python:8000/`, then exited. An exited k6 container is expected
  when the job succeeds. Inspect exit status/logs; do not assume every exit is success.
- Result file on host: `outputs\service-lab-k6.txt`.
- Earlier executable version check passed; sample lab job result needs inspection.
- Teammates can run k6 locally and target the host's published application URL,
  or ask the host operator to execute it in Docker. No k6 installation is required
  on a client laptop merely to use the other services.

### 12. Selenium hub
- Image: `selenium/hub:4.24.0`; container: `nascon-lan-hub`.
- TCP 4444 -> 4444; remote WebDriver/Grid URL `http://10.27.87.243:4444`.
- Docker-network event bus TCP 4442/4443 stays internal; no remote host mappings.
- No authentication configured. Use the hub to create browser sessions.
- Earlier real headless WebDriver page/title tests passed for all three browsers.

### 13. Selenium Chrome node
- Image: `selenium/node-chrome:4.24.0`; container: `nascon-lan-chrome`.
- Host TCP 5555 -> container TCP 5555. Status `http://10.27.87.243:5555/status`.
- Session capability browserName `chrome`; use hub 4444 for sessions.

### 14. Selenium Firefox node
- Image: `selenium/node-firefox:4.24.0`; container: `nascon-lan-firefox`.
- Host TCP **5556** -> container TCP **5555**. Status `http://10.27.87.243:5556/status`.
- Session capability browserName `firefox`; use hub 4444 for sessions.

### 15. Selenium Edge node
- Image: `selenium/node-edge:4.24.0`; container: `nascon-lan-edge`.
- Host TCP **5557** -> container TCP **5555**. Status `http://10.27.87.243:5557/status`.
- Session capability browserName `MicrosoftEdge`; use hub 4444 for sessions.

All three nodes share the internal event bus with `nascon-lan-hub`, have 1 GiB
shared memory each and one maximum session each. VNC/noVNC are configured off;
no 5900/7900 ports are published. They run browsers on the server, so URLs used
in a browser session must be reachable FROM THE SERVER CONTAINER. A web app
running on a teammate laptop must listen beyond localhost and allow inbound
connections on that teammate laptop. Use its LAN IP, not localhost.

### 16. Python backend runtime / sample HTTP server
- Image: `python:3.12-slim`; container: `nascon-lan-python`.
- TCP 8000 -> 8000; remote `http://10.27.87.243:8000`.
- Current command is `python -m http.server 8000 --bind 0.0.0.0 --directory /tmp`.
- This serves a disposable empty/sample directory. It is NOT Flask, FastAPI,
  Django or the team's API. Those packages/app sources have not been installed
  into this container.
- Earlier runtime check reported Python 3.12.15 and passed.
- The port is occupied by this demo; do not deploy another service on host 8000
  without coordinating with the host operator. Do not casually stop/delete data
  while another teammate is using the lab.

## What each teammate needs locally

Choose tools for the assigned role; every laptop need not install all tools.

- Backend developer: editor/agent and chosen runtime, required SDK clients for
  PostgreSQL/Redis/S3/AMQP/NATS etc. Only add clients for services the task needs.
- Flutter developer: Flutter SDK, Android SDK/JDK as required, cached Pub/Gradle
  dependencies, physical Android phone and USB data cable or an emulator.
- QA developer: Selenium bindings plus a testing framework, Appium client/server
  and Android driver where the phone is connected, and a performance-test client.
- PostgreSQL manual access: `psql` or a database GUI such as an already installed
  client. The full PostgreSQL server is NOT needed on every laptop.
- Docker on each laptop is optional if they only consume this server's services.
  Backend code still needs a local runtime or a coordinated deployment process.
- Cache required client packages before losing Internet. Existing container
  images do not automatically supply dependencies to another laptop's editor.

These tools were installed/verified on the SERVER laptop, not automatically on
the other machines:
- Flutter stable 3.47.7 at `C:\Users\Wali\develop\flutter`; Dart 3.13.5.
- Android Studio at `C:\Program Files\Android\Android Studio`.
- Android SDK at `C:\Users\Wali\AppData\Local\Android\Sdk`; platform/build tools
  36.1 available; licenses accepted; latest user-run Flutter doctor found no issues.
- Appium 2.19.0 with UiAutomator2 driver 4.2.9. Do not blindly update the driver:
  UiAutomator2 major 5+ requires Appium 3, while this booklet requests Appium 2.
- Python QA environment at `C:\Users\Wali\Documents\Codex\tools\nascon-qa`:
  Selenium 4.51.0, pytest 9.1.1, pytest-html 4.2.0, Appium-Python-Client 6.0.7,
  Locust 2.46.7. Imports and dependency check passed.
- Android emulator definition `Medium_Phone` exists. No physical phone appeared
  in the last supplied ADB output; end-to-end Appium phone automation is untested.
- Appium doctor had zero required fixes; missing bundletool/GStreamer were optional.

No Appium server port was published by the Docker lab. Do not assume port 4723
is available. Appium normally belongs on the laptop connected to the test phone.

## Remote checks from another Windows laptop

Use PowerShell; these checks need no Internet. Change `$server` if DHCP changes.

```powershell
$server = '10.27.87.243'
Test-NetConnection $server -Port 5432
Test-NetConnection $server -Port 6379
Test-NetConnection $server -Port 9000
curl.exe -f "http://${server}:9000/minio/health/live"
curl.exe -f "http://${server}:8222/healthz"
curl.exe -f "http://${server}:8080/v1/health"
curl.exe -f "http://${server}:9090/-/ready"
curl.exe -f "http://${server}:3000/api/health"
curl.exe -f "http://${server}:4444/status"
curl.exe -f "http://${server}:8000/"
```

TCP success checks connectivity, not database login or app correctness. Ping is
ICMP and may fail even when service connections succeed. `Test-NetConnection`
does not verify UDP media; real media clients/publishers are needed for that.
An HTTP 401/403 proves a server responded but means authentication/authorization
must be supplied. Browser CORS errors differ from a failed network connection.

## Firewall and safe network operation

Keep Windows Firewall enabled. Two dedicated rules were configured:
`NaSCon-Readiness-TCP` and `NaSCon-Readiness-UDP`, restricted to the selected local
server IP and remote `LocalSubnet`, on any Windows network profile.

Allowed TCP host ports:
`5432,6379,9000,9001,5672,15672,4222,8222,8554,1935,8888,8889,7880,7881,8080,9090,3000,4444,5555,5556,5557,8000`.

Allowed UDP host ports: `7882,8189,8890`.

The user temporarily disabled firewalls during diagnosis; re-enabling them was
recommended. Current enabled/disabled profile status has not been independently
confirmed. Do not disable all firewalls to solve a specific port issue. No router
port-forwarding/public Internet exposure is required for the local team network.

## Server operator: startup, inspection, migration and cleanup

All commands in this section run on the Windows SERVER, not client machines.
Scripts are local to the server under:

```powershell
$folder = 'C:\Users\Wali\Documents\Codex\2026-10-16\referenced-chatgpt-conversation-this-is-an\outputs'
```

Start Docker Desktop first. Existing lab containers already run; do NOT rerun
the launcher just because an agent joined the team. Inspect them:

```powershell
docker ps -a --filter label=codex.nascon.readiness=lan
docker logs --tail 80 nascon-lan-rabbitmq
docker logs nascon-lan-k6
docker stats --no-stream
```

The Docker Desktop screenshot showed running service containers. Container
"running" alone does not establish service readiness or client accessibility.

Only if the lab does not exist, start it with the current network address:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$folder\Start-Service-Lab.ps1" -LaptopIP 10.27.87.243
```

Then, in Administrator PowerShell, apply scoped firewall rules:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$folder\Allow-Team-Ports.ps1"
```

Verify the printed address matches the hotspot/router address. The old campus
Wi-Fi address `172.15.85.129` is stale and must not be reused.

If the host IP changes, ports and advertised media addresses need updating.
Do not automatically run the stop/start scripts: first coordinate with teammates
and back up any useful data. **Stopping this lab deletes its disposable data.**

```powershell
# DESTRUCTIVE TO THIS LAB'S DATA: only after coordination/backup.
# Use Administrator PowerShell when removing its firewall rules.
powershell -NoProfile -ExecutionPolicy Bypass -File "$folder\Stop-Service-Lab.ps1"
# Then start again using the NEW IP and reapply firewall rules.
```

The stop script removes only containers carrying label
`codex.nascon.readiness=lan`, their anonymous volumes, the lab network, and its two
firewall rules. Downloaded images remain. Python demo files and container-layer
data are also lost when those containers are removed. Redis persistence has not
been configured for durable storage. This is a disposable lab, not a production
database deployment. Do not use it for irreplaceable competition data without
designing persistence/backups during the allowed sprint.

No bind-mounted application source or auto-reload/deployment workflow has been
configured. Editing files on a teammate laptop does not update host containers.

## Testing status and known boundaries

- Confirmed: all 16 required local image entries, Docker Engine/Compose, Flutter
  and Android readiness, QA imports, PostgreSQL query, Redis PING, NATS/ntfy/
  Prometheus/Grafana health, MediaMTX RTSP response, LiveKit HTTP startup,
  Python/k6 executable checks, and real Selenium Chrome/Firefox/Edge sessions.
- Confirmed separately: corrected MinIO version/fingerprint/startup health check.
- RabbitMQ: startup-race test corrected; lab container observed running; final
  corrected diagnostic result not supplied.
- Cross-laptop ping reported working. Final TCP, login and HTTP tests from each
  teammate laptop have not all been supplied. Agents must verify their own path.
- Not verified: application integration, complete offline package availability,
  durable persistence, sustained load, Appium phone session, media stream/call,
  HTTPS/TURN, or public Internet accessibility.
- Do not mark the whole stack production-ready on the basis of these checks.

## Competition constraints from the supplied booklet

Times are Pakistan time (PKT). Respect organizer updates if the official rules change.
- Day 1, 17 October: repository must have zero commits at 10:40 AM; sprint starts
  10:45 AM and ends 3:00 PM; eligible pushes close 3:05 PM.
- Day 2, 18 October: sprint starts 10:15 AM and ends 2:00 PM; eligible pushes
  close 2:05 PM. No overnight pushes between Day 1 3:05 PM and Day 2 10:15 AM.
- Do not create competition scaffolding/source before the allowed start.
- Push at least hourly during the sprints. The lead's private repository must
  invite `nascon-eval-26` as required by the booklet.
- AI tools allowed; pre-built repositories and managed BaaS such as Firebase
  and Supabase prohibited.
- Local distributed testing is allowed. Final grading runs the submitted
  `docker-compose.yml` on the official GitHub cloud runner, not this laptop.
  Therefore submitted deployment must be self-contained and must not depend on
  this laptop's IP, local credentials or pre-existing LAN containers.
- Large images should already be cached. The form says 14 images, whereas the
  supplied booklet enumerates 15 Windows service/QA images plus one runtime.
- Last user-generated image-list hash: `c552c41f9789658b`. It is 16 hex characters,
  a 64-bit prefix of SHA-256, and includes all locally listed image tags including
  the MinIO mirror alias. It can change when images/tags are added or removed.
  It is not an integrity signature of all image contents. Recompute rather than
  reusing blindly after changes. Starting containers alone does not change it.

## Instructions for an agent receiving this handoff

1. Establish which laptop you run on, its role, current server address, and whether
   you have a local executor. Never assume this server's Windows paths exist on
   your own laptop.
2. Test TCP and the required protocol before debugging application code. Ask for
   secrets privately; do not print them in logs, commits or a shared document.
3. Use host IPs for laptop clients, Docker service names only inside the shared
   Docker network, and the correct container-internal port for internal clients.
4. Coordinate service/data ownership with other agents and teammates. Do not
   delete/recreate the lab, rotate passwords, migrate shared schemas, change
   published ports, update image tags or remove images without explicit human
   direction and coordination with users of those services.
5. Stay within the allowed competition start time. This handoff grants context,
   not authorization to start competition coding early or submit external changes.
6. Report observed test output and unresolved limits honestly. Do not claim a
   service is reachable merely because a port or container is listed here.
