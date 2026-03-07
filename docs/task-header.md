# Binz Poker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an autonomous poker simulation where LLM-driven players with randomized personalities compete for survival at a No Limit Hold'em table, managed by an Elixir/Phoenix OTP application.

**Architecture:** Two event-driven processes (Table, Sim) and up to 10 reactive Player agents. Table is the poker engine — it manages seats, runs hands continuously, and broadcasts results. Sim is the world reactor — it listens for events (player busts, hand results, seat availability) and manages economy, seating assignments, eliminations, and respawns. Players respond synchronously when asked for poker decisions or buy-in decisions. All components are behaviour-based for swappability. LLM calls go through LiteLLM gateway.

**Event model:**
- **Table** (event-driven loop): Runs hands in a loop with whoever is seated. Owns its seat list. Self-removes busted players (0 chips) and sets them to away before broadcasting. Broadcasts hand results, player busts, seat availability. Loops hand-over-hand with a configurable delay.
- **Sim** (event-driven reactor): No tick loop. Subscribes to PubSub and reacts — hand results (per-hand billing), player busts (chip-to-budget conversion + loan flow), seat availability (buy-in decision + seat player), loan decisions (re-seat or eliminate).
- **Player** (reactive): No tick loop in v1. Responds synchronously when Table asks for a poker decision or Sim asks for a buy-in decision.

**Critical principle: State is NOT tied to GenServer lifecycle.** All persistent state lives in **SQLite via Ecto**: simulation config and hand count in the `sims` table, player state in `players`, loans in `loans`, dead players in `leaderboard_entries`. GenServers cache state in memory and write through to DB on every change. The program can be stopped and resumed. On startup, Sim loads the current sim and all living players from DB and restarts their brains.

**Economy:** Two currencies — **budget** (real money, pays thinking tax) and **chips** (table currency, won/lost at poker). 1 chip = $0.01. Starting budget $5.00, 0 starting chips. Players buy in (budget → chips) when entering the table, choosing how much to convert. When leaving the table, all chips auto-convert back to budget. Thinking tax (token costs) is deducted from budget after every hand. Death = budget 0 + chips 0 + loan denied.

**Poker engine:** Complete No Limit Texas Hold'em with proper betting rounds (unlimited re-raises), side pot calculation with split pots for ties, and 0-chip bust handling (player leaves table, chips convert to budget, can re-buy-in or request loan).

**Banker:** v1 auto-approves all loans (no LLM banker). v2 adds LLM banker with personality.

**Tech Stack:** Elixir, Phoenix, Ecto + SQLite (ecto_sqlite3), Finch (HTTP), Jason (JSON), ExUnit (testing)

**Design doc:** `docs/plans/2026-03-07-binz-poker-design.md`

**Task index:** [`docs/task-index.md`](task-index.md) — canonical execution order
