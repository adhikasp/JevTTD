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

- **[adhikasp/OpenTTD](https://github.com/adhikasp/OpenTTD), branch `feature/ai-decision-http`** — exploratory engine fork. Goal: add an opt-in `ScriptHTTP`-style API so a script *can* delegate a decision to an external typed-decision service (TypeSafe.ai or similar) when the player has explicitly enabled it, without breaking determinism for anyone who hasn't. Open design questions, tracked there: async event model (scripts can't block on I/O — needs a suspend/resume + event callback like `DoCommand` already uses), a host allowlist (a downloaded AI script silently phoning an arbitrary server is a real security concern), and forcing it off entirely in networked multiplayer (every client must compute the same result — an external call breaks that unless *all* clients agree not to use it, or it's restricted to single-player only). Status: **design phase, not merged into anything, not required for this repo to work.**
- **This repo (JevTTD)** — the actual AI script. Runs today, unmodified, on stock OpenTTD. Its decision brain (`ai/funbrain.nut`) is a pure-local reimplementation of TypeSafe.ai's `Choice` / `Score` / `Noul` vocabulary using Squirrel's own RNG — no network dependency. If/when the engine fork above ever lands and is enabled, `funbrain.nut` is the one place that would grow a remote-first path with local fallback; nothing else in this repo needs to change or know about it.

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
  info.nut      - AIInfo registration, settings (incl. a "showmanship" slider)
  main.nut      - main loop: event pump -> mood evaluation -> (TODO) route managers
  mood.nut      - MoodEngine state machine (stubbed heuristics, real triggers TODO)
  funbrain.nut  - Choice / Score / Noul primitives (implemented, local-only)
```

Not yet built: the actual rail/road/air route managers that *use* FunBrain to decide what to build (today's `main.nut` just evaluates mood and logs it). The plan is to lift the working parts of AdmiralAI/trAIns' route-finding mechanics (pathfinding, station placement, vehicle selection) verbatim — that part isn't where "fun vs. optimal" lives — and swap only the *scoring and selection* step for `FunBrain.Score()` + `FunBrain.Choice()`.

## Non-goals

- Not trying to beat AdmiralAI/trAIns on profit or network efficiency — that's an explicitly different design goal.
- Not going to require the engine fork to function. Local mode is the baseline forever; remote mode (if it ever ships) is a strictly optional enhancement gated behind a setting, off by default, and disabled outright whenever `AIController` detects a networked game.

## License

GPL v2, matching the rest of the OpenTTD AI ecosystem it plugs into.
