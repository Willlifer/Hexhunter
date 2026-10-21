"""Hexhunt relay: rooms of up to five WebSockets, host-centred routing.

Protocol v1 (guide/02-core-contracts.md "Online co-op through the relay"):

  hello (the client's first frame, text JSON)
      {"op": "host", "v": 1}
      {"op": "join", "v": 1, "room": "KMRTX"}
  replies (text JSON)
      {"op": "hosted", "room": "KMRTX", "id": 1, "max": 5}
      {"op": "joined", "room": "KMRTX", "id": 7}
      to the host only: {"op": "peer_join", "id": 7}, {"op": "peer_leave", "id": 7}
      {"op": "error", "code": "...", "msg": "..."}, then the relay closes
          codes: not_found full rooms_full busy bad_request version host_left
                 idle rate slow kicked
  host -> relay (text JSON): {"op": "kick", "id": 7}
  data (binary): 5-byte header + payload
      [0] 1 = DATA   [1] target (0 = everyone but the sender)
      [2] sender (the relay overwrites it)   [3] channel   [4] transfer mode
      A joiner reaches only the host (its target is forced to 1); the host
      reaches one peer or all of them.

The relay never reads or logs payloads; it logs rooms opening and closing
with their byte counts. A GET without an Upgrade header answers 200 (Render's
health check, and waking a sleeping free instance from a browser).

Run: python relay.py [--port N]   (PORT in the environment binds 0.0.0.0:PORT)
"""

import asyncio
import http
import json
import logging
import os
import secrets
import sys
import time

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

VERSION = 1
DATA = 1
HEADER = 5
ROOM_ALPHABET = "ACDEFHJKMNPRTWXY"
ROOM_LEN = 5

MAX_PEERS = 5                  # host + four joiners (the game caps a party at four)
MAX_FRAME = 256 * 1024
MAX_ROOMS = 200
MAX_CONNECTIONS = 1000
HELLO_TIMEOUT_S = 10
IDLE_TIMEOUT_S = 15 * 60       # a room with no data frame for this long closes
FRAME_RATE, FRAME_BURST = 300.0, 900.0
BYTE_RATE, BYTE_BURST = 256 * 1024.0, 1024 * 1024.0
SEND_QUEUE = 512               # frames queued for one peer; past it the peer is "slow"
ERROR_LINGER_S = 1.0           # after an error, let the client read it and close first

log = logging.getLogger("relay")

rooms = {}                     # code -> Room
connections = 0


class Bucket:
    def __init__(self, rate, burst):
        self.rate, self.burst, self.level, self.at = rate, burst, burst, time.monotonic()

    def take(self, n):
        now = time.monotonic()
        self.level = min(self.burst, self.level + (now - self.at) * self.rate)
        self.at = now
        if self.level < n:
            return False
        self.level -= n
        return True


class Peer:
    def __init__(self, ws):
        self.ws = ws
        self.id = 0
        self.room = None
        self.queue = asyncio.Queue(SEND_QUEUE)
        self.frames = Bucket(FRAME_RATE, FRAME_BURST)
        self.bytes = Bucket(BYTE_RATE, BYTE_BURST)
        self.closing = False
        self.writer = None

    def push(self, msg):
        """Queue a frame (bytes or str). False when the queue is full."""
        if self.closing:
            return True
        try:
            self.queue.put_nowait(msg)
            return True
        except asyncio.QueueFull:
            return False

    async def write_loop(self):
        try:
            while True:
                msg = await self.queue.get()
                if msg is None:
                    return
                await self.ws.send(msg)
        except ConnectionClosed:
            pass


class Room:
    def __init__(self, code, host):
        self.code = code
        self.host = host
        self.peers = {1: host}
        self.next_id = 2
        self.opened = time.monotonic()
        self.active = time.monotonic()
        self.bytes_in = 0
        self.bytes_out = 0
        self.frames = 0

    def free_id(self):
        for _ in range(254):
            i = self.next_id
            self.next_id = 2 if self.next_id >= 255 else self.next_id + 1
            if i not in self.peers:
                return i
        return 0


def text(op, **kw):
    kw["op"] = op
    return json.dumps(kw, separators=(",", ":"))


def new_code():
    for _ in range(1000):
        c = "".join(secrets.choice(ROOM_ALPHABET) for _ in range(ROOM_LEN))
        if c not in rooms:
            return c
    return ""


async def fail(peer, code, msg):
    """Send an error, give the client a moment to read it, then close."""
    if peer.closing:
        return
    peer.closing = True
    try:
        await asyncio.wait_for(peer.ws.send(text("error", code=code, msg=msg)), 2)
        await asyncio.sleep(ERROR_LINGER_S)
    except (ConnectionClosed, asyncio.TimeoutError):
        pass
    await peer.ws.close(1000 if code in ("host_left", "kicked", "idle") else 4000, code)


def drop_later(peer, code, msg):
    asyncio.get_running_loop().create_task(fail(peer, code, msg))


def leave_room(peer):
    room = peer.room
    if room is None or room.peers.get(peer.id) is not peer:
        return
    del room.peers[peer.id]
    peer.room = None
    if peer is room.host:
        for other in list(room.peers.values()):
            other.room = None
            drop_later(other, "host_left", "the host left")
        room.peers.clear()
        rooms.pop(room.code, None)
        secs = max(0.001, time.monotonic() - room.opened)
        log.info("room %s closed after %.0f s: %d frames, in %d B (%.1f KB/s), out %d B (%.1f KB/s); %d rooms open",
                 room.code, secs, room.frames, room.bytes_in, room.bytes_in / secs / 1024,
                 room.bytes_out, room.bytes_out / secs / 1024, len(rooms))
    elif not room.host.push(text("peer_leave", id=peer.id)):
        drop_later(room.host, "slow", "the host fell too far behind")


async def hello(peer):
    try:
        raw = await asyncio.wait_for(peer.ws.recv(), HELLO_TIMEOUT_S)
    except asyncio.TimeoutError:
        await fail(peer, "bad_request", "no hello within %d s" % HELLO_TIMEOUT_S)
        return False
    try:
        msg = json.loads(raw) if isinstance(raw, str) else None
    except ValueError:
        msg = None
    if not isinstance(msg, dict) or msg.get("op") not in ("host", "join"):
        await fail(peer, "bad_request", "the first frame must be a host or join hello")
        return False
    if msg.get("v") != VERSION:
        await fail(peer, "version", "this relay speaks protocol %d" % VERSION)
        return False
    if msg["op"] == "host":
        if len(rooms) >= MAX_ROOMS:
            await fail(peer, "rooms_full", "the relay has no free rooms")
            return False
        code = new_code()
        if not code:
            await fail(peer, "rooms_full", "no free room code")
            return False
        room = Room(code, peer)
        rooms[code] = room
        peer.id, peer.room = 1, room
        peer.push(text("hosted", room=code, id=1, max=MAX_PEERS))
        log.info("room %s opened; %d rooms open", code, len(rooms))
        return True
    code = str(msg.get("room", "")).strip().upper()
    room = rooms.get(code)
    if room is None:
        await fail(peer, "not_found", "no room %s" % code[:8])
        return False
    if len(room.peers) >= MAX_PEERS:
        await fail(peer, "full", "room %s is full" % code)
        return False
    pid = room.free_id()
    peer.id, peer.room = pid, room
    room.peers[pid] = peer
    peer.push(text("joined", room=code, id=pid))
    if not room.host.push(text("peer_join", id=pid)):
        drop_later(room.host, "slow", "the host fell too far behind")
    return True


def on_text(peer, raw):
    room = peer.room
    try:
        msg = json.loads(raw)
    except ValueError:
        msg = None
    if not isinstance(msg, dict):
        return "bad_request"
    if msg.get("op") == "kick" and room is not None and peer is room.host:
        target = room.peers.get(msg.get("id"))
        if target is not None and target is not room.host:
            leave_room(target)
            drop_later(target, "kicked", "the host removed you from the room")
        return ""
    return "bad_request"


def on_data(peer, frame):
    room = peer.room
    if room is None:
        return ""
    if len(frame) < HEADER or frame[0] != DATA:
        return "bad_request"
    room.active = time.monotonic()
    room.frames += 1
    room.bytes_in += len(frame)
    out = bytearray(frame)
    out[2] = peer.id
    if peer is room.host:
        target = frame[1]
        dests = [p for i, p in room.peers.items() if i != 1] if target == 0 else (
            [room.peers[target]] if target in room.peers and target != 1 else [])
    else:
        out[1] = 1
        dests = [room.host]
    out = bytes(out)
    for d in dests:
        if d.push(out):
            room.bytes_out += len(out)
        elif d is room.host:
            leave_room(d)
            drop_later(d, "slow", "the host fell too far behind")
        else:
            leave_room(d)
            drop_later(d, "slow", "your connection fell too far behind")
    return ""


async def handler(ws):
    global connections
    connections += 1
    peer = Peer(ws)
    peer.writer = asyncio.get_running_loop().create_task(peer.write_loop())
    try:
        if connections > MAX_CONNECTIONS:
            await fail(peer, "busy", "the relay is busy")
            return
        if not await hello(peer):
            return
        async for raw in ws:
            if peer.closing:
                break
            n = len(raw)
            if not peer.frames.take(1) or not peer.bytes.take(n):
                leave_room(peer)
                await fail(peer, "rate", "too many frames or bytes per second")
                break
            why = on_text(peer, raw) if isinstance(raw, str) else on_data(peer, raw)
            if why:
                leave_room(peer)
                await fail(peer, why, "malformed frame")
                break
    except ConnectionClosed:
        pass
    finally:
        leave_room(peer)
        peer.closing = True
        try:
            peer.queue.put_nowait(None)
        except asyncio.QueueFull:
            peer.writer.cancel()
        connections -= 1


async def sweep():
    """Close rooms with no data frame for IDLE_TIMEOUT_S."""
    while True:
        await asyncio.sleep(30)
        now = time.monotonic()
        for room in list(rooms.values()):
            if now - room.active > IDLE_TIMEOUT_S:
                log.info("room %s idle for %d s", room.code, now - room.active)
                for p in list(room.peers.values()):
                    drop_later(p, "idle", "the room was idle for 15 minutes")
                leave_room(room.host)


def health(connection, request):
    if "upgrade" not in request.headers.get("Connection", "").lower() and not request.headers.get("Upgrade"):
        return connection.respond(http.HTTPStatus.OK, "hexhunt relay v%d: %d rooms\n" % (VERSION, len(rooms)))
    return None


async def main():
    port_env = os.environ.get("PORT")
    host, port = ("0.0.0.0", int(port_env)) if port_env else ("127.0.0.1", 8765)
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
    asyncio.get_running_loop().create_task(sweep())
    async with serve(handler, host, port, process_request=health, compression=None,
                     max_size=MAX_FRAME, max_queue=64, ping_interval=20, ping_timeout=30) as server:
        log.info("hexhunt relay v%d on %s:%d", VERSION, host, port)
        await server.serve_forever()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", stream=sys.stdout)
    logging.getLogger("websockets").setLevel(logging.WARNING)
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
