# Binz Poker - Claude Code Guide

## Project Overview

Autonomous poker simulation — LLM players compete at No Limit Hold'em, managed by Elixir/Phoenix OTP.

## Quick Commands

```bash
mix setup                  # Install deps, create DB, migrate
mix test                   # Run tests
mix format                 # Format code
mix precommit              # Compile (warnings-as-errors), format, test
iex -S mix phx.server      # Start server with IEx
```

## Architecture

### Core Processes (lib/binz_poker/)

- `table.ex` — Poker engine GenServer. Runs hand loop, manages seats, calculates side pots. ~500 lines. This is the most complex module.
- `sim.ex` — World reactor. Subscribes to PubSub events, handles economy (billing, loans, eliminations, respawns).
- `player.ex` — Player GenServer. Holds character state, delegates decisions to a DecisionEngine.
- `bank.ex` — Budget tracking, token cost billing, loan management.
- `room.ex` — Convenience module for starting/stopping/resuming simulations from IEx.
- `player_supervisor.ex` — DynamicSupervisor for player processes.
- `application.ex` — OTP supervision tree. Game processes only start when `start_game: true`.

### Decision Engines (lib/binz_poker/decision_engine/)

- `random.ex` — Random actions from available options. Simulates token usage.
- `llm.ex` — Real LLM calls via LiteLLM. Returns actual token usage.

### Schemas (lib/binz_poker/schemas/)

- `player_record.ex` — Player state persistence (chips, budget, stats, personality)
- `sim_record.ex` — Simulation tracking (hand count, status)
- `loan_record.ex` — Loan lifecycle (requested, granted, denied)
- `leaderboard_entry.ex` — Hall of fame for dead players
- `hand_history.ex` — Full hand audit trail (cards, actions, pots, showdown)

### Web (lib/binz_poker_web/)

- `router.ex` — All routes under `/api`, JSON only
- `table_controller.ex` — Read endpoints (state, players, hands, leaderboard)
- `banker_controller.ex` — Write endpoints (loan management, table controls)

## Key Patterns

- **Two currencies**: Budget (real $) and Chips (table, 1 chip = $0.01)
- **Event-driven**: Table broadcasts via PubSub, Sim reacts. No polling.
- **State persistence**: GenServers write-through to SQLite. Can stop/resume.
- **Behaviour-based**: DecisionEngine, CharacterGen, HandEvaluator are all swappable behaviours.
- **Lazy sim_id**: Table resolves sim_id at hand time (not init) since Sim starts after Table.

## Database

SQLite via ecto_sqlite3. DB file at `binz_poker_dev.db` (dev) or `binz_poker_test.db` (test).

Migrations in `priv/repo/migrations/`.

## Testing

Tests in `test/`. Integration test (`game_integration_test.exs`) runs a full game loop with spawn, play, and billing verification. Test support modules in `test/support/`.

## Config

- `config/dev.exs` — Dev settings including delays (`action_delay_ms`, `hand_delay_ms`) and logger level
- `config/test.exs` — Test config with `start_game: false`
- `config/runtime.exs` — Runtime config (DATABASE_PATH, SECRET_KEY_BASE)

## Common Gotchas

- Card suits use ASCII (h/d/c/s) not Unicode symbols — avoids terminal alignment issues
- `min_buy_in_budget` is $0.01 — prevents 1-chip ghost buy-ins from rounding
- Side pots: a weaker hand CAN win a pot if it's the best hand among that pot's eligible players
- When `raise_to <= current_bet`, the engine falls back to a call (not a false raise)
