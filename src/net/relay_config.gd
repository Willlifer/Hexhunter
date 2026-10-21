class_name HHRelayConfig
extends RefCounted
## Where online co-op connects (H110). The relay is relay/relay.py, hosted as
## a Render free web service (render.yaml, relay/README.md). Change URL when
## the service gets its real address. For one run, `--relay <url>` overrides
## it on desktop (the two-process smoke points it at a local relay:
## `--relay ws://127.0.0.1:8765`) and `?relay=<url>` on the page does in a
## browser (a page served over https may only open wss:// URLs).

const URL := "wss://hexhunt-relay.onrender.com"


## The relay URL for this run: `--relay <url>` or `?relay=<url>` beats URL.
static func url() -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--relay")
	if i >= 0 and i + 1 < args.size() and str(args[i + 1]).begins_with("ws"):
		return str(args[i + 1])
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('relay') || ''", true)
		if q is String and (q as String).begins_with("ws"):
			return q
	return URL
