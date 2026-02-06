# ClawDaddy

Audio-first agent harness prototype (macOS SwiftUI + direct OpenClaw gateway).

## macOS App

```bash
open ClawDaddy/ClawDaddy.xcodeproj
```

Run the `ClawDaddy` scheme in Xcode. The app talks directly to the OpenClaw gateway.

Gateway discovery order:
1. `OPENCLAW_*` environment variables
2. `~/.openclaw/openclaw.json` and `~/.openclaw/identity/device.json`
3. `openclaw config get gateway.*` CLI lookups

Optional overrides (environment variables, not `.env`):

```
OPENCLAW_WS_URL=ws://127.0.0.1:18789
OPENCLAW_API_KEY=token_here
OPENCLAW_AUTH_MODE=token  # or "password"
OPENCLAW_CHAT_METHOD=chat.send
OPENCLAW_IDLE_DELAY=1.5
OPENCLAW_DEBUG_EVENTS=0
```

Notes:
- The push-to-talk key monitor is local, so the window needs focus.
- On startup, gateway discovery diagnostics are logged in Console under subsystem `com.teej.ClawDaddy`.

## Release Packaging

```bash
just archive
just export-app
just package-dmg
NOTARY_PROFILE="your-notary-profile" just notarize-dmg
just staple
```

`just export-app` requires `ClawDaddy/ExportOptions.plist` with your Apple team ID.
