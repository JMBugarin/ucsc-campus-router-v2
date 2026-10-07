# Hosting the server

The mobile app (and the web page) talk to one server: Python plus the C routing engine. On your laptop that is `scripts/start-server.ps1`. For a phone away from your Wi-Fi it has to run somewhere with a public address. The repo includes a `Dockerfile`, so any host that runs containers works.

## What runs there, and what it knows

- The server is **stateless**: it stores no schedules, no locations and no accounts. A request carries the schedule and (if the student allows it) their location, the server answers, and nothing is kept.
- The request logs record the method, the path and the status, **never the query string**, which is where a location travels. A test checks this.
- The host's own infrastructure (its load balancer, for example) can still see traffic, as with any hosted service. If that matters, use a host you trust or run it yourself.
- There are no logins. To keep a public copy from being run into the ground it has per-address rate limits (120 requests a minute, 30 for the ones that run the router), a cap of four router processes at a time, a 30-second timeout on stalled connections, and request-size limits.
- **Claude photo reading is switched off on any server that isn't running on localhost**, so strangers can't use your API key. Don't set `ALLOW_PUBLIC_CLAUDE_PHOTO=1` on a public server unless you want exactly that. Reading a photo on the student's own device needs no key and still works.

## Render (the suggested starting point)

`render.yaml` describes the service. **You do these steps** (they involve your account):

1. Make a free account at render.com and connect your GitHub account.
2. Choose New, then Blueprint, pick this repository, and apply. Render builds the `Dockerfile` and starts the server.
3. When the build is green, open the service's URL plus `/healthz`. You should see `{"ok": true}`.
4. Put that URL into the app's settings (the app asks for the server address).

Notes:
- The free plan **sleeps after a period with no traffic**, so the first request after a pause can take up to a minute. The app shows a "waking the server" message for this. A paid plan stays awake.
- Render passes the real client address in `X-Forwarded-For`; `render.yaml` sets `TRUST_PROXY=1` so the rate limits count each student separately. Only set `TRUST_PROXY` behind a proxy you trust, otherwise anyone can pretend to be someone else.
- `render.yaml` was written from Render's documented format but **has not been run**. If the blueprint is rejected, create a "Web Service" by hand instead: runtime Docker, health check path `/healthz`, environment variable `TRUST_PROXY=1`.

## Other hosts

Anything that runs a Dockerfile and sets a `PORT` works: Fly.io (`fly launch`), Google Cloud Run (`gcloud run deploy --source .`), Railway, or a small VM with `docker run -p 80:8000 -e TRUST_PROXY=0 ...`. Some of these need a payment card on file even for free tiers. Set `HOST` and `PORT` only if the host doesn't; the image already binds `0.0.0.0` and reads `PORT`.

## Checking an image locally

```bash
docker build -t ucsc-router .
docker run --rm -p 8000:8000 ucsc-router
```

Then open http://localhost:8000. CI builds the same image on every push and smoke-tests the health check, a real route, the Today endpoint and the log privacy rule, so a broken image fails the build.
