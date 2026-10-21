# Hexhunt relay

`relay.py` is the small public server that lets players hunt together over
the internet: browsers (which cannot accept connections) and desktops behind
home routers (no port forwarding). Every player opens one WebSocket to the
relay; the host gets a five-letter room code, friends join with it, and the
relay passes the game's packets between them. It never reads, stores or logs
what is inside them. The protocol is in `relay.py`'s header and in
`guide/02-core-contracts.md` ("Online co-op through the relay").

Limits: 5 connections per room (a party is 4; the fifth hears "party full"
from the host), 200 rooms, 1000 connections, 256 KB per frame, 300 frames/s
and 256 KB/s per connection (bursts of 900 frames / 1 MB), 512 queued frames
per receiver, 10 s to say hello, rooms close after 15 minutes without play.

## Run it locally

```
python -m venv venv
venv\Scripts\pip install -r relay\requirements.txt
venv\Scripts\python relay\relay.py --port 8765
```

Then play with `--relay ws://127.0.0.1:8765` (desktop) or `?relay=ws://127.0.0.1:8765`
on a locally served web build. `tools/net_two_process.md` has the two-process smoke.

## Put it on Render (free), click by click

Nothing to install; everything happens in the browser. `render.yaml` at the
repo root (a Render "Blueprint") describes the service.

1. Push the branch that has `render.yaml` and `relay/` to GitHub (`main` once
   this is merged).
2. Go to https://dashboard.render.com and sign in (GitHub sign-in is easiest).
3. Click **New +** (top right) -> **Blueprint**.
4. Connect GitHub if asked, and pick the **Hexhunter** repository. Choose the
   branch (`main`).
5. Render reads `render.yaml` and shows one service, **hexhunt-relay**, a free
   Python web service. Give the Blueprint any name and click **Apply** (or
   **Deploy Blueprint**).
6. Wait for the first deploy to say **Live** (a minute or two). The service's
   page shows its address, e.g. `https://hexhunt-relay.onrender.com` (if the
   name is taken Render adds a suffix, e.g. `hexhunt-relay-x1y2.onrender.com`).
7. Open that address in a browser: it should say `hexhunt relay v1: 0 rooms`.
8. If the address is not exactly `hexhunt-relay.onrender.com`, put it in
   `src/net/relay_config.gd` as `URL := "wss://<your-address>"` (wss, not
   https), then rebuild the web build (`build_web.sh`) and the desktop exe.

Pushes to that branch redeploy the relay automatically (`autoDeploy`).

**The free tier sleeps.** After about 15 minutes without traffic Render stops
the service; the next player to connect wakes it, which takes about a minute.
The game keeps retrying for 90 s and says "relay asleep, retrying…" meanwhile.
Opening the address in a browser tab first also wakes it. A paid Render
instance type never sleeps.

## Notes

- All game traffic goes over TCP, so every channel is reliable: a lost packet
  arrives late instead of never. On a bad connection a hunter may stutter
  rather than skip.
- Measured locally: 13 KB/s down per client and about 34 KB/s up for a host
  with four hunters (Swampfang, pond).
