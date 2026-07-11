# Gains MCP server

A **personal MCP server** for Gains: talk to your *own* health
record (food log, calories, weight, steps, Whoop) from an MCP client (web, mobile, or
a local MCP bridge).

## How it works

```
iPhone (Gains)                  Hosted server (this)              MCP client
┌──────────────────┐            ┌──────────────────────┐
│ encrypted record │  POST /sync│  slice held in RAM    │  /mcp
│   └ egress gate ─┼───────────►│  (never on disk)      │◄──── web / mobile
│   (opt-in)       │  minimized │  gains_* read tools   │◄──── desktop bridge
└──────────────────┘  read-only └──────────────────────┘◄──── (bearer / OAuth)
```

- The phone builds a **minimized, read-only slice** of the on-device record and
  `POST`s it to `/sync` (authenticated with `MCP_AUTH_TOKEN`).
- The server keeps that slice **in RAM only**: no database, no disk. The phone
  is the source of truth and re-pushes on app open / on change / hourly, so a
  restart just means "empty until the next push". **No durable PHI on the host.**
- The MCP client reads it through read-only `gains_*` tools.

## Auth

Two paths, both accepted on `/mcp`:

1. **Static bearer** (`MCP_AUTH_TOKEN`): for local bridges (a CLI `--header`, or a
   desktop `mcp-remote` bridge). Also the only credential allowed on `POST /sync`.
2. **OAuth 2.1 + PKCE**: for hosted MCP clients (web + mobile) added as custom
   connectors. The `/authorize` step shows a password page gated by `AUTH_PASSWORD`.

## Tools

| Tool | What it returns |
|---|---|
| `gains_status` | Sync freshness: whether a slice is loaded, when it was built, and how many days of each domain are present (call first if "no data") |
| `gains_profile` | Profile basics (name, sex, age, height, current weight) and the user's self-set daily goals (calories, macros, steps) |
| `gains_today` | Composite snapshot for the latest synced day: calories + macros vs goals, Whoop if connected, and any workouts |
| `gains_nutrition` | Daily food totals (calories, protein, carbs, fat, sugar, fiber, sodium, water) over a range, with goals and a per-day average |
| `gains_food_journal` | The food-journal lines for a date/range: what the user typed, resolved items with macros, and each item's assumptions |
| `gains_workouts` | Logged workout sessions over a range (title, raw text, parsed exercises) |
| `gains_whoop` | Whoop daily metrics: recovery %, HRV, RHR, sleep hours + performance, day strain, calories burned, steps |
| `gains_weight` | Body-weight history (lb) over a range, plus body-fat % when logged and the net change |
| `gains_streaks` | Goal streaks: current run, longest run, and the last 7 days' hit rate against goals |
| `gains_trend` | A single metric as a date→value series, for plotting or cross-domain correlation |

## Local dev

```bash
npm install
cp .env.example .env          # set MCP_AUTH_TOKEN=$(openssl rand -hex 32)
npm run dev                   # MCP_TRANSPORT=http, hot reload on :3000

# feed it a slice:
curl -s localhost:3000/sync -H "authorization: Bearer $MCP_AUTH_TOKEN" \
  -H 'content-type: application/json' --data @sample-slice.json | jq
# inspect:
curl -s localhost:3000/health | jq
```

## Deploy (Fly)

```bash
fly launch --no-deploy            # generates fly.toml (set internal_port=3000)
fly secrets set \
  MCP_AUTH_TOKEN=$(openssl rand -hex 32) \
  AUTH_PASSWORD='a-password-you-type-once' \
  PUBLIC_URL=https://<your-app>.fly.dev
fly deploy
```

In `fly.toml`, keep one machine warm so the connector never cold-starts:

```toml
[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = "suspend"
  auto_start_machines = true
  min_machines_running = 1
```

Then in **your MCP client → Settings → Connectors → Add custom connector**, use
`https://<your-app>.fly.dev/mcp` and enter your `AUTH_PASSWORD` when prompted.

> Free alternative: Hugging Face Spaces (Docker SDK, set `PORT=7860`). Requires a
> public Space + a paid plan for the connector.
