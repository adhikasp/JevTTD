# JevTTD

An OpenTTD company AI that optimizes for **a good story with the human player**, not for the highest possible balance sheet.

Every AI shipped on BaNaNaS today (AdmiralAI, trAIns, SimpleAI, ...) is some flavor of greedy profit-maximizer: rank cargo by income, rank industries by unmet demand, pick the best-scoring option, repeat. That makes a perfectly competent opponent and a genuinely boring one to actually play against — it never surprises you, never reacts to *you* specifically, and never takes a risk it doesn't have to. JevTTD scores candidate actions on a "is this fun to play against" rubric instead of a profit rubric, and picks *among* the good options with weighted randomness instead of always taking the argmax.

## Project context

This repo grew out of a conversation exploring how OpenTTD's AI system actually works end to end:

1. Mapped where the engine's AI plumbing lives (`src/ai`, `src/game`, `src/script`) and confirmed OpenTTD ships **no built-in strategy** — every real opponent (AdmiralAI, SimpleAI, trAIns, ...) is a community Squirrel script loaded through that plumbing.
2. Pulled the real source of AdmiralAI and trAIns (SimpleAI has no public mirror) and read their actual route-selection code: both are greedy scorers — AdmiralAI ranks by `production + random jitter` and picks the nearest valid destination; trAIns ranks by a denser `unmet_demand / crowding × cargo_value` formula and targets an ideal route length instead of "nearest."
3. Decided to build something different: a decision brain modeled on [TypeSafe.ai's decision patterns](https://docs.typesafe.ai/patterns) (Speculative Fan-Out, Confidence-Gated Routing, Composite Scoring, Intent Routing, and its typed `Choice` / `Score` / `Noul` primitives) — but pointed at a "what makes this fun to play against" rubric instead of a profit rubric.
4. Hit a hard constraint: **OpenTTD's AI/GS Squirrel sandbox has no network access at all** (no `ScriptHTTP` class anywhere in `src/script/api`; the engine's own HTTP code is never exposed to scripts). This is deliberate — AI companies must be deterministic and lockstep-safe for multiplayer, and the per-tick opcode-budget scheduler can't tolerate a script blocking on a network round-trip. A live call to an external decision service from inside a running game isn't possible in vanilla OpenTTD.
5. Split the work into two repos accordingly (see below): this one ships a fully local, playable-today AI; a companion engine fork explores whether an optional, sandboxed, MP-safe remote-decision API is worth adding on top of it later.

## Two-repo architecture

- **[adhikasp/OpenTTD](https://github.com/adhikasp/OpenTTD), branch `feature/ai-decision-http`** — engine fork. Adds an opt-in `ScriptDecision` Script API class (`AIDecision`/`GSDecision` from Squirrel) so a script *can* delegate a decision to an external service, without breaking determinism for anyone who hasn't turned it on. It's a deliberately dumb, vendor-agnostic relay — `AIDecision.Ask(request_json)` POSTs an opaque JSON string to a single player-configured endpoint and returns the raw response string (or `null`); the engine has no idea what TypeSafe.ai (or anything else) actually wants to see in that JSON, on purpose, to keep the engine-side surface small and reviewable. It reuses the same suspend/resume machinery `DoCommand` already uses for networked-game commands, and is **unconditionally disabled in any networked game** regardless of settings — this sidesteps the multiplayer-determinism problem entirely rather than trying to solve it. Gated behind two new client-only (never-synced, never-saved) settings: `script.allow_decision_calls` (off by default) and `script.decision_service_url` (empty by default, set via the console `setting` command). Status: **implemented on that branch, compiles and links clean; not upstreamed, not required for this repo to work.**
- **This repo (JevTTD)** — the actual AI script. Runs today, unmodified, on stock OpenTTD; the engine fork above is a strictly optional enhancement. Its decision brain (`ai/funbrain.nut`) is a pure-local reimplementation of TypeSafe.ai's `Choice` / `Score` / `Noul` vocabulary using Squirrel's own RNG — no network dependency, and that stays the permanent baseline. `ai/systemone.nut` speaks the real Jev protocol (`POST /v1/systemone`, schema captured from a live [laya-serve](https://huggingface.co/convaiinnovations/laya) response — a small, self-hostable, Jev-compatible model, used here as a free stand-in for a real TypeSafe.ai account) over `FunBrain.RemoteAsk()`; `MoodEngine.Evaluate()` uses it to ask the remote service to pick a mood, falling back to the local weighted-random choice on any failure. Verified working end to end against a live laya-serve instance in a real headless game.

## The decision brain

Four ideas borrowed from TypeSafe.ai's pattern docs, reimplemented as local Squirrel:

| TypeSafe.ai pattern | JevTTD's local version |
|---|---|
| Intent Routing | `MoodEngine` (`ai/mood.nut`) — classifies the game state into a mode (`Underdog`, `Rival`, `Showman`, `Copycat`, `Recovery`, `Settler`) relative to *the human player*, not just the AI's own P&L, and dispatches behavior accordingly. |
| Composite Scoring | `FunBrain.Score()` — candidates are ranked on a blended rubric: `novelty` (don't repeat yourself), `visibility` (build where the player will actually notice), `drama` (contest the same industries/towns as the player), `spectacle` (bridges, tunnels, showy engines over the cheapest option), `safety` (floor guardrail so "fun" never means "bankrupt by turn 20"). |
| Confidence-Gated Routing | Each risky/flashy candidate gets a cheap local `confidence` score (cash reserve, loan headroom, payback horizon); only clears the gate to attempt a big swing when confidence is high enough to fail *interestingly* rather than fatally. |
| Speculative Fan-Out | Generate several candidate actions, score them all, then `FunBrain.Choice()` samples **proportional to score** instead of always taking the top result — the single biggest lever for "not hard-calculating optimized play." |

### Current scaffolding

```
ai/
  info.nut               - AIInfo registration, settings (incl. a "showmanship" slider)
  main.nut               - main loop: event pump -> mood evaluation -> aircraft manager -> finance log
  mood.nut                - MoodEngine state machine; asks the remote service first, falls back to local FunBrain.Choice()
  funbrain.nut            - Choice / Score / Noul primitives (local); RemoteAvailable/RemoteAsk passthroughs to AIDecision
  systemone.nut           - the real Jev protocol (POST /v1/systemone) on top of RemoteAsk()
  json.nut                - hand-rolled JSON encode/decode (OpenTTD's Script API has none built in)
  air/aircraftmanager.nut - WORKING: builds small airports + planes between two FunBrain-picked towns
```

Verified by actually running headless simulations (not just "it compiles"): solo, JevTTD grows a bank balance from ~25k to 700k+ and company value to 850k+ over roughly 10 simulated years, building 8 real air routes, zero script errors. Two real bugs were found and fixed this way — see the git log for `air/aircraftmanager.nut` for specifics (a too-small tile search budget that missed flat land near towns, and a route that could get half-built before discovering it couldn't afford the planes).

Not yet built: rail and road managers (aircraft was deliberately first — no pathfinding/junction/signal logic needed, just two patches of flat ground), and `FunBrain.Score()`'s full composite rubric (novelty/visibility/drama/spectacle/safety) isn't wired into route *selection* yet — town choice today is population-weighted-random via `FunBrain.Choice()` alone, not yet scored against the player-awareness rubric described below. The plan for rail/road is still to lift the working parts of AdmiralAI/trAIns' route-finding mechanics (pathfinding, station placement, vehicle selection) verbatim — that part isn't where "fun vs. optimal" lives — and swap only the *scoring and selection* step for `FunBrain.Score()` + `FunBrain.Choice()`, the same pattern `air/aircraftmanager.nut` already established.

## Non-goals

- Not trying to beat AdmiralAI/trAIns on profit or network efficiency — that's an explicitly different design goal.
- Not going to require the engine fork to function. Local mode is the baseline forever; remote mode (if it ever ships) is a strictly optional enhancement gated behind a setting, off by default, and disabled outright whenever `AIController` detects a networked game.

## License

GPL v2, matching the rest of the OpenTTD AI ecosystem it plugs into.
