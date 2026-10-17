# Hardened Docker Container Runtime

A Docker Compose setup that runs a container with tighter runtime security than Docker's defaults.

Scanning your image is only part of the job. Most of the risk comes from how the container runs. By default, your app runs as root, can write anywhere in its filesystem, and keeps 14 Linux capabilities. This setup closes those gaps with a few settings.

From the reel by @deepakms.speaks.

## What's in this folder

| File | Purpose |
|---|---|
| `docker-compose.yml` | Runs the container with every hardening setting turned on |
| `Dockerfile` | Builds the image with a fixed non-root user (UID 1000) |
| `README.md` | This file |

## What each setting does

| Setting | Default Docker | This setup | Why it matters |
|---|---|---|---|
| `user: "1000:1000"` | root (UID 0) | UID 1000 | An attacker who breaks into your app is not root inside the container |
| `read_only: true` | Writable filesystem | Read-only | Nobody can drop new scripts or binaries into the container |
| `tmpfs: /tmp` | n/a | Small in-memory `/tmp` with `noexec` | Your app keeps a scratch space, and files written there can't be executed |
| `cap_drop: ALL` | 14 capabilities | 0 capabilities | Removes kernel privileges like CHOWN, SETUID and NET_RAW |
| `no-new-privileges:true` | Off | On | setuid binaries can't raise privileges |
| `pids_limit`, `mem_limit`, `cpus` | Unlimited | Capped | A fork bomb or memory leak can't take down the host |
| `init: true` | Off | On | Reaps zombie processes and forwards signals properly |

## Requirements

- Docker Engine 20.10 or later
- Docker Compose v2 (`docker compose`, not `docker-compose`)

## Quick start

1. Put your app code in this folder. For a quick test, use this minimal FastAPI app.

   `main.py`:

   ```python
   from fastapi import FastAPI

   app = FastAPI()

   @app.get("/health")
   def health():
       return {"status": "ok"}

   @app.get("/")
   def root():
       return {"message": "running hardened"}
   ```

   `requirements.txt`:

   ```
   fastapi
   uvicorn
   ```

2. Build and start it.

   ```bash
   docker compose up -d --build
   ```

3. Open http://localhost:8080 in your browser.

## Verify the hardening

Run each check. The comment says what you should see.

```bash
# Non-root user: expect uid=1000(app) gid=1000(app)
docker exec myapp id

# Read-only filesystem: expect "Read-only file system"
docker exec myapp touch /app/x.sh

# /tmp still works: expect "tmp writable"
docker exec myapp touch /tmp/ok && echo "tmp writable"

# Capabilities dropped: CapEff should be 0000000000000000
docker exec myapp grep Cap /proc/1/status

# No new privileges: expect NoNewPrivs: 1
docker exec myapp grep NoNewPrivs /proc/1/status

# Health status: expect "healthy" after about 10 seconds
docker inspect --format '{{.State.Health.Status}}' myapp
```

## Using it with your own app

Change these to fit your app:

- `image` and `container_name` in `docker-compose.yml`
- `CMD` in the `Dockerfile`
- `ports`, if your app listens somewhere other than 8080
- The healthcheck URL, if your app has no `/health` endpoint
- `mem_limit`, `cpus` and `pids_limit`, based on what your app actually uses

### Your app needs to write files

With `read_only: true`, any write outside `/tmp` fails. If your app writes uploads, a cache or a SQLite file, mount a volume at that exact path:

```yaml
    volumes:
      - app-data:/app/data

volumes:
  app-data:
```

Then make sure UID 1000 owns that path. Add this to the Dockerfile before `USER 1000:1000`:

```dockerfile
RUN mkdir -p /app/data && chown 1000:1000 /app/data
```

### Adding a capability back

The `cap_add` block is commented out on purpose. Add back a capability only when something breaks without it, and only that one.

A note on `NET_BIND_SERVICE`, which the reel uses as its example: you don't need it for this setup.

- The app listens on 8080. NET_BIND_SERVICE only matters for ports below 1024.
- Docker 20.10 and later already let containers bind low ports without it.
- A non-root process without file capabilities doesn't get added capabilities anyway.

If you want your app on port 80 or 443, publish it from the host instead (`"80:8080"`) and keep the app on 8080 inside the container.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Read-only file system` when your app starts | Your app writes outside `/tmp` | Mount a volume or tmpfs at that path (see above) |
| `Permission denied` on a mounted volume | The volume is owned by root | `chown 1000:1000` the path in the Dockerfile |
| `Operation not permitted` | Your app needs a capability you dropped | Find the one it needs and add only that one back |
| Container shows `unhealthy` | No `/health` endpoint, or the app is slow to start | Fix the healthcheck URL or raise `start_period` |
| `exec format error` | Image built for a different CPU architecture | Rebuild with `--platform linux/amd64` or `linux/arm64` |

## What this doesn't cover

Runtime hardening is one layer. You still need:

- Image scanning (Trivy, Grype or Docker Scout)
- Minimal base images and pinned versions
- Secrets kept out of environment variables and images
- Network policies between services
- A seccomp or AppArmor profile beyond Docker's default, for high-risk workloads

## Further reading

- Docker security docs: https://docs.docker.com/engine/security/
- Linux capabilities man page: https://man7.org/linux/man-pages/man7/capabilities.7.html
- OWASP Docker Security Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
