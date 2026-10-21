# Two real processes: host and client over ENet (Lane N)

Proof that the co-op stream works between two separate Godot processes, not
only between two branches of one SceneTree. Run from the repo root, two
terminals, host first. Both are headless; the fight is paced at 30 Hz.

```
set GODOT=<godot>

rem terminal 1: the host (pond, Swampfang, seed 1; p1 is a bot)
"%GODOT%" --headless --path . --script res://tools/net_loopback.gd -- --role host --port 24661

rem terminal 2: the client (joins, picks daggers, drives p2 from its mirror)
"%GODOT%" --headless --path . --script res://tools/net_loopback.gd -- --role client --port 24661
```

Options for both: `--address A` (client, default 127.0.0.1), `--seconds S`
(30), `--arena`, `--monster`, `--seed`. To try two machines, run the host on
one and pass `--address <host's LAN IP>` to the client (UDP 24661 open).

What each side checks: the host, that p2 (which only the client's orders
drive) moved and that orders arrived; the client, that every packet hash it
was sent matched its mirror (`verified`, `mismatches`). The `full t=` lines
are the state_hash at every full snapshot: the host's from its own sim, the
client's from its mirror after applying. Diffing them is the cross-process
proof.

## Output, 2026-10-20 (this machine, both processes on 127.0.0.1)

Host:
```
[host] listening on 24661: OK
[host] peer 32093683 joined (ClientBot)
[host] all ready: ["HostBot/lance", "ClientBot/daggers"]
[host] fight: pond / swampfang seed 1, players ["p1=HostBot(lance)", "p2=ClientBot(daggers)"]
[host]   full t=30 hash=2328479459
[host]   full t=60 hash=3050636537
[host]   full t=90 hash=1194055519
[host]   full t=120 hash=1091919647
[host]   full t=150 hash=3360832531
[host]   full t=180 hash=2756655977
[host]   full t=210 hash=3422130811
[host]   full t=240 hash=2398631695
[host]   full t=270 hash=1644912660
[host]   full t=300 hash=3744557112
[host]   full t=330 hash=3388973596
[host]   full t=360 hash=1821450264
[host]   full t=390 hash=1934755435
[host]   full t=420 hash=823203773
[host]   full t=450 hash=965687024
[host]   full t=480 hash=1681647326
[host]   full t=510 hash=1325832406
[host]   full t=540 hash=3504181785
[host]   full t=570 hash=763849593
[host]   full t=600 hash=846842952
[host]   full t=630 hash=595752679
[host]   full t=660 hash=2705289494
[host]   full t=690 hash=296187316
[host]   full t=720 hash=2975084597
[host]   full t=750 hash=1021822117
[host]   full t=780 hash=942495817
[host]   full t=810 hash=3903335742
[host]   full t=840 hash=2499049451
[host]   full t=870 hash=119402416
[host]   full t=900 hash=4240488758
[host] 900 ticks in 31.4 s wall; monster hp 114563 / 160000; over ''
[host] p2 (remote) moved up to 30.6 m from spawn; 48 orders received
[host] sent to peer 32093683: 331633 B = 10.3 KB/s
[host] received from peer 32093683: 3953 B = 0.12 KB/s
NET_LOOPBACK OK (host)
```

Client:
```
[client] joining 127.0.0.1:24661: OK
[client] welcomed by HostBot; my peer id 32093683
[client] fight starts, I am p2
[client] full t=30 hash=2328479459
[client] full t=60 hash=3050636537
[client] full t=90 hash=1194055519
[client] full t=120 hash=1091919647
[client] full t=150 hash=3360832531
[client] full t=180 hash=2756655977
[client] full t=210 hash=3422130811
[client] full t=240 hash=2398631695
[client] full t=270 hash=1644912660
[client] full t=300 hash=3744557112
[client] full t=330 hash=3388973596
[client] full t=360 hash=1821450264
[client] full t=390 hash=1934755435
[client] full t=420 hash=823203773
[client] full t=450 hash=965687024
[client] full t=480 hash=1681647326
[client] full t=510 hash=1325832406
[client] full t=540 hash=3504181785
[client] full t=570 hash=763849593
[client] full t=600 hash=846842952
[client] full t=630 hash=595752679
[client] full t=660 hash=2705289494
[client] full t=690 hash=296187316
[client] full t=720 hash=2975084597
[client] full t=750 hash=1021822117
[client] full t=780 hash=942495817
[client] full t=810 hash=3903335742
[client] full t=840 hash=2499049451
[client] full t=870 hash=119402416
[client] full t=900 hash=4240488758
[client] host left at mirror tick 900
[client] mirror tick 900; stats { "fulls": 31, "deltas": 869, "stale": 0, "skipped_ticks": 0, "requests": 1, "mismatches": 0, "bad_base": 0, "orders": 48, "max_catchup": 3, "verified": 181 }
[client] events: ["arrive 2", "blocked 85", "cast 19", "cast_refused 2", "daggerleap 3", "detonate 50", "douse 9", "eruption 2", "flourish 3", "guard 1", "guard_block 1", "heal 7", "hurt 79", "knifedance 12", "land 5", "leap 5", "monster_anim 15", "monster_state 1", "move 12", "overfreeze 24", "paint 119", "pierce 4", "potion 2", "projectile 61", "reaction 16", "regen_end 2", "stagger 44", "status 15", "status_end 3", "strike 39", "swap 5", "telegraph 9", "telegraph_end 8", "upgrade 3", "windup 38", "windup_broken 3"]
[client] own-move click -> the mirror shows p2 routed there: median 62 ms, max 78 ms (9 samples)
NET_LOOPBACK OK (client)
```

The 30 `full t=` lines of host and client diff IDENTICAL. The client applied
every one of the 900 ticks (869 deltas + 31 fulls, the extra one is the full it
asks for on start), skipped none, and verified 181 packet hashes with 0
mismatches. `requests: 1` is that start-up request (H858).

The hashes after t=90 differ from run to run: p2 is driven by the client's
real-time orders, so when an order lands on the host depends on wall-clock
timing. Within one run, host and client always agree.

An earlier run showed `skipped_ticks: 62, stale: 44, requests: 6` on the same
machine: deltas went missing and the client fell back to requested fulls.
Two fixes went in together and the next run above showed 0 skipped: ENet's
packet throttle switched off (it drops unreliable packets when it thinks the
link is congested; H853) and a full requested as soon as the client's
replicator exists (START and the first full travel on different channels;
H857). I did not separate which of the two caused how much. Hash agreement
held in the bad run too (0 mismatches); only smoothness suffered.

# Relay variant: two real processes through a local relay (Lane R, H110-H119)

The same proof for online play: both processes connect out to a relay
(`relay/relay.py`) on this machine instead of to each other, so it exercises
HHRelayPeer, the relay's routing and the lobby's `--host --online` /
`--join-code` path end to end. Three terminals from the repo root.

```
rem terminal 1: the relay (a venv with relay/requirements.txt installed)
venv\Scripts\python relay\relay.py --port 8799

rem terminal 2: the host; its lobby prints "[lobby] Room XXXXX is open"
"%GODOT%" --headless --path . -- --host --online --relay ws://127.0.0.1:8799 --name HostBot --peers 2 --arena pond --fight swampfang --autoplay --seconds 20

rem terminal 3: the client, with the code the host printed
"%GODOT%" --headless --path . -- --join-code XXXXX --relay ws://127.0.0.1:8799 --name ClientBot --weapon daggers --autoplay --seconds 20
```

Pass: the client takes 0 sim steps, both summaries agree on every hunter's HP,
and the client's fight log is the host's, line for line, once the lines only
one side prints are set aside (`you -N (...)` and `staggered N` are about the
local hunter, p1 on the host). The client's run ends a second earlier (its
20 s start when its fight starts), so its log is a prefix of the host's.

## Output, 2026-10-21 (this machine, relay on 127.0.0.1:8799)

Host:
```
[lobby] Opening a room on the relay ...
[lobby] Connecting to the relay ...
[lobby] Connected to the relay, opening a room ...
[lobby] Room CPJFK is open: tell your friends the code
[lobby] The party could not start (error 2): everyone must be ready
HHFight autoplay done: tick 600, player hp 2520 at (-3, -4), hash 1436036372, log 139 lines
  party: host as p1, 2 hunter(s), 600 steps taken here
  p1 HostBot (lance): hp 2520 / 3000, downed 0 time(s)
  p2 ClientBot (daggers): hp 3000 / 3000, downed 0 time(s)
  net: relay room CPJFK; sent 222096 B = 8.9 KB/s, received 1723 B = 0.1 KB/s over 24 s; relay frames out 583 (225594 B), in 23 (1861 B)
  swampfang hp 24447 / 32000
```

Client:
```
[lobby] Joining room CPJFK ...
[lobby] Connecting to the relay ...
[lobby] Connected to the relay, joining room CPJFK ...
[lobby] Joined the party at room CPJFK: pick your weapon and elements, then Ready
HHFight autoplay done: tick 571, player hp 3000 at (-5, -10), hash 1920334799, log 131 lines
  party: client as p2, 2 hunter(s), 0 steps taken here
  p1 HostBot (lance): hp 2520 / 3000, downed 0 time(s)
  p2 ClientBot (daggers): hp 3000 / 3000, downed 0 time(s)
  net: relay room CPJFK; sent 1723 B = 0.1 KB/s, received 220292 B = 10.2 KB/s over 21 s; relay frames out 23 (1861 B), in 577 (223754 B)
  swampfang hp 24987 / 32000
```

Relay:
```
room CPJFK opened; 1 rooms open
room CPJFK closed after 25 s: 606 frames, in 227455 B (9.0 KB/s), out 227455 B (9.0 KB/s); 0 rooms open
```

The client's 130 log lines (after the filter) are identical to the host's
first 130; the host has 4 more from the ticks after the client quit, plus 3
`you` / `staggered` lines of its own.
The monster HP differs only because the client stopped at tick 571.
"The party could not start (error 2)" is the autoplay host trying FIGHT one
refresh before the guest's ready row arrived; the ENet smoke prints it too and
the next refresh starts the fight.

Four hunters (host + three `--join-code` clients, lance / daggers / bow /
lance): every client 0 steps, 319 / 319 / 315 shared lines identical to the
host's; 13.1-13.2 KB/s down per client, 33.7 KB/s up from the host at about
65 frames/s (relay: 1819 frames, 935 KB in 27 s).

Also tried by hand against the real relay: a wrong code ("Could not join room
ACDEF: room not found: ..."), killing the host while a guest waits ("Host
left: back to solo" within a second), hosting with no relay running ("Relay
asleep, retrying… (12 s)" ... "(84 s)", then "Could not host online: could
not reach the relay (no answer in 90 s)"), and starting the relay 16 s after
the host began trying (one retry line, then "Room JKXNT is open").
