# Binz Poker — Task Index

Execution order. Each entry links to a task file. The order here is the canonical build sequence.

For overall architecture, principles, and tech stack, see [task-header.md](task-header.md).

| # | Task File | Description | Status |
|---|-----------|-------------|--------|
| 1 | [task-scaffolding.md](task-scaffolding.md) | Phoenix project setup with SQLite | |
| 2 | [task-card-deck.md](task-card-deck.md) | Card and Deck data structures | |
| 3 | [task-hand-evaluator.md](task-hand-evaluator.md) | Hand evaluator behaviour + native impl | |
| 4 | [task-character-traits.md](task-character-traits.md) | Character struct with random traits | |
| 5 | [task-behaviours.md](task-behaviours.md) | LLM, DecisionEngine, CharacterGen, GameLog behaviours | |
| 6 | [task-mock-implementations.md](task-mock-implementations.md) | Mock/test implementations for all behaviours | |
| 7 | [task-ecto-schemas.md](task-ecto-schemas.md) | Ecto schemas & migrations (players, loans, game_state, leaderboard) | |
| 8 | [task-bank-genserver.md](task-bank-genserver.md) | Bank GenServer — ledger, billing, loans (DB-backed) | |
| 9 | [task-player-genserver.md](task-player-genserver.md) | Player GenServer — autonomous agent with tick loop (DB-backed) | |
| 10 | [task-player-supervisor.md](task-player-supervisor.md) | Player Supervisor — spawn, eliminate, respawn | |
| 11 | [task-table-engine.md](task-table-engine.md) | Table GenServer — complete poker engine with side pots | |
| 12 | [task-sim-reactor.md](task-sim-reactor.md) | Sim — event-driven world reactor (economy, seating, eliminations) | |
| 13 | [task-litellm-client.md](task-litellm-client.md) | LiteLLM HTTP client via Finch | |
| 14 | [task-llm-decision-engine.md](task-llm-decision-engine.md) | LLM-based decision engine + prompt builder | |
| 15 | [task-llm-character-gen.md](task-llm-character-gen.md) | LLM-based character generator | |
| 16 | [task-gamelog-pubsub.md](task-gamelog-pubsub.md) | PubSub game event logger | |
| 17 | [task-json-api.md](task-json-api.md) | Phoenix JSON API — banker controls, table state | |
| 18 | [task-supervision-tree.md](task-supervision-tree.md) | Application supervision tree wiring | |
| 19 | [task-integration-test.md](task-integration-test.md) | Integration test — full game loop | |
| 20 | [task-room-module.md](task-room-module.md) | Room module — convenient start/stop/status | |
