# Binz Poker - Design Document

An autonomous poker simulation where LLM-driven players with randomized personalities compete for survival at a No Limit Hold'em table.

## Core Concept

A 6-seat No Limit Texas Hold'em table that runs continuously. Each player is powered by a different LLM (via LiteLLM gateway) with a randomly generated personality. Players pay "living costs" (real token expenses) billed periodically, like rent. When they can't pay and can't get a loan, they die permanently and a new character takes their seat. A banker (human or LLM) oversees the economy. The human can drop in to play or take over as banker at any time.

## Key Design Decisions

- **No 4th wall break** - Players don't know they're LLMs. They know the house charges a "thinking tax" (in-fiction framing of token costs).
- **Traits drive behavior via backstory, not math** - The LLM reasons naturally from its character prompt. No probability engine.
- **Token costs billed after each hand** - Chips at the table are sacred during play. After each hand, the accumulated thinking tax is deducted from the player's budget.
- **Permadeath + respawn** - Roguelike model. Dead characters are recorded on a leaderboard. New character spawns immediately.
- **Behaviour-based abstractions** - Every major component is a swappable behaviour. LLM players, human players, and future integrations all use the same interfaces.
- **State lives in the DB, not in processes** - GenServers cache state in memory and write through to SQLite on every mutation. The program can be stopped and resumed at any time.

## Tech Stack

- **Language:** Elixir on BEAM VM
- **Framework:** Phoenix (for PubSub, Ecto, future LiveView/API)
- **Database:** SQLite via Ecto (all persistent state — players, loans, game state, leaderboard)
- **LLM Gateway:** LiteLLM at `http://litellm.lan/v1` (OpenAI-compatible, mix of local + cloud models)
- **HTTP Client:** Finch (ships with Phoenix)
- **UI:** None initially. JSON API for banker controls. React or LiveView later.

## Architecture

The system has two process types with distinct execution models, plus autonomous player agents:

- **Table** (event-driven loop) — The poker engine. Runs hands continuously back-to-back with a configurable delay. Owns its seat list. Broadcasts hand results, player busts, and seat availability via PubSub.
- **Sim** (event-driven reactor) — The world. Has NO tick loop. Subscribes to PubSub and reacts to events: hand results trigger billing cycle checks, player busts trigger loan flows, seat availability triggers seating assignments, loan decisions trigger re-seating or elimination. Manages the broader player pool (entry, waitlist, who takes the next open seat).
- **Player** (reactive) — Responds synchronously when Table asks for a poker decision, and when Sim asks for a buy-in decision. No autonomous tick loop in v1.

Up to 10 players in the room, 6 seats at the table.

```
BinzPoker (Phoenix/OTP Application)
|
+-- BinzPoker.Application (supervision tree root)
|   +-- BinzPoker.Repo (Ecto - SQLite)
|   +-- BinzPokerWeb.Endpoint (Phoenix)
|   +-- Phoenix.PubSub (event broadcasting)
|   +-- {Finch, name: BinzPoker.Finch}
|   |
|   +-- BinzPoker.Table (GenServer)
|   |   Poker engine. Owns its seat list. Runs hands in a loop.
|   |   Manages: seats, deck, community cards, pot, blinds, dealer position.
|   |   Loops hand-over-hand with configurable delay.
|   |   Broadcasts: hand_result, player_busted, seat_available.
|   |   When a player hits 0 chips: removes them, broadcasts bust.
|   |   Knows nothing about budgets, loans, billing, or survival.
|   |
|   +-- BinzPoker.Sim (GenServer)
|   |   World reactor. Purely event-driven — NO tick loop.
|   |   Subscribes to table:events, bank:events.
|   |   Reacts to:
|   |   - hand_result -> count hands, check billing cycle
|   |   - player_busted -> trigger loan flow
|   |   - seat_available -> assign next waiting player
|   |   - loan_decided -> re-seat or eliminate player
|   |   Manages: player pool, waitlist, spawning, eliminations.
|   |   Max 10 players in the room, delegates seating to Table.
|   |
|   +-- BinzPoker.Bank (GenServer)
|   |   Token cost ledger, loan book, billing cycles.
|   |   Caches state in memory, writes through to DB on every mutation.
|   |   DecisionEngine for loan/kick decisions (LLM or Human).
|   |   Broadcasts: loan_decided, billing_settled.
|   |
|   +-- BinzPoker.PlayerSupervisor (DynamicSupervisor)
|   |   Spawns/kills Player processes.
|   |   On elimination: terminate old, spawn new with fresh character.
|   |
|   +-- BinzPoker.Player (GenServer, up to 10)
|   |   Reactive agent. No tick loop in v1.
|   |   Reads state from DB on init, writes through on changes.
|   |   Responds synchronously to Table (poker decision) and Sim (buy-in decision).
|   |   Every LLM call costs tokens (thinking tax, deducted from budget after each hand).
|   |
|   +-- BinzPoker.LLM (module + Finch pool)
|       HTTP client to litellm.lan/v1.
|       Structured output (JSON mode).
|       Token counting from response usage metadata.
```

### Process Execution Models

| Process | Model | Execution | Purpose |
|---------|-------|-----------|---------|
| Table | Event-driven loop | Runs hands back-to-back with delay | Pure poker: deal, bet, showdown |
| Sim | Event-driven reactor | Reacts to PubSub events, no tick | Economy, player pool, eliminations, seating assignments |
| Player (x10 max) | Reactive | Sync response when asked for decisions | Poker decisions, buy-in decisions |

### Seat Ownership

**Table owns the seats.** It decides who is currently playing. Players request seats from the Table, and the Table accepts or rejects. When a player busts (0 chips mid-hand), the Table removes them and broadcasts `{:player_busted, player_id}` and `{:seat_available, count}`.

**Sim owns the player pool.** It tracks all players in the room (seated + away + waitlist), decides who gets the next open seat, spawns new players, and handles eliminations. When Sim hears `{:seat_available, ...}`, it picks the next eligible player and tells them to request a seat from the Table.

### Communication Model

All processes communicate via PubSub (async) or direct GenServer.call (sync, game-critical only).

**PubSub topics:**

| Topic | Publisher | Subscribers | Events |
|-------|----------|-------------|--------|
| `table:events` | Table | All Players, Sim | hand_result, player_busted, seat_available, action_taken |
| `player:{id}:talk` | Player | All Players, Sim | table_talk (v2: trash_talk, reactions) |
| `bank:events` | Bank | Sim, Players | billing_settled, loan_decided |
| `sim:events` | Sim | Players | player_eliminated, new_player |
| `player:{id}:actions` | Player | Sim, Bank | leave_table (v2: loan_request) |

**Direct GenServer.call (synchronous):**
- Table -> Player: "It's your turn, what do you do?" (only sync call in the system)
- Everything else is async via PubSub

### Player States

```
                    +----------+
         spawn --> |   away   | -- waiting to buy in / waiting for seat
                    +----+-----+
                         |
              seat available + buy-in decision (LLM chooses chip amount)
                         |
                    +----v-----+
                    |  seated  | <-- re-seated after loan approved
                    +----+-----+
                         |
              0 chips (busted) OR budget <= 0 after hand settle
              -> all chips convert to budget
                         |
                    +----v-----+
                    |   away   | -- can request loan, wait for seat
                    +----+-----+
                         |
              budget <= 0 AND chips = 0 AND loan denied
                         |
                    +----v------+
                    |   dead    | -- recorded on leaderboard, slot freed
                    +----------+
```

- **seated**: At the table, playing hands. Table has them in the seat list. Player responds to poker decisions when asked.
- **away**: In the room but not at the table. Waiting for a seat, deciding buy-in, or negotiating a loan. No autonomous behavior in v1.
- **dead**: Eliminated. Process terminated. Recorded on leaderboard. Sim spawns a replacement.

### Table Exit & Entry Flow

**Leaving the table** (bust or kicked for budget=0):
1. All remaining chips convert to budget automatically (1 chip = $0.01)
2. Player status set to `away`
3. If budget > 0: player can re-enter when a seat is available
4. If budget <= 0: loan flow triggered

**Entering the table:**
1. Sim notifies player that a seat is available
2. Player makes a **buy-in decision** (LLM call): how many chips to buy from their budget
   - Must leave enough budget in reserve for thinking tax
   - A greedy player might go all-in, a cautious one keeps reserves
   - Traits drive this decision naturally through the character prompt
3. Budget reduced by buy-in amount, chips set to buy-in amount
4. Player seated at table

### Player Behavior (v1)

In v1, players are purely reactive — no autonomous tick loop.

**When seated:**
- Respond to poker decisions when Table asks (sync GenServer.call)
- Each decision is an LLM call that costs tokens (added to thinking tax)

**When entering table:**
- Respond to buy-in decision when Sim asks (sync GenServer.call)
- LLM decides how much budget to convert to chips

**Cost of thinking:**
- Every LLM call (poker decision, buy-in decision) costs tokens
- An expensive model (Opus) plays smart but has a massive thinking bill
- A cheap model (Haiku/local) plays simpler but survives on less
- Thinking tax is deducted from budget after each hand

### Future: Private Communication

Players can DM each other privately via `player:{id}:dm:{target_id}` topics. Content is not broadcast to the room -- other players can't see it. The banker/god-view can see all DMs. Enables collusion, alliances, and betrayal. Out of scope for v1.

## Behaviours (Interfaces)

```elixir
# Decision-making - LLM, Human, or Random (testing)
defmodule BinzPoker.DecisionEngine do
  @callback decide(game_state :: map(), character :: map())
    :: {:ok, %{action: atom(), amount: integer(), reasoning: String.t(), talk: String.t()}}
end

# LLM provider - LiteLLM, direct API, or mock
defmodule BinzPoker.LLM do
  @callback chat(model :: String.t(), messages :: list(), opts :: keyword())
    :: {:ok, %{content: String.t(), usage: %{input: integer(), output: integer()}}}
     | {:error, term()}
end

# Character generation - LLM-based, hardcoded, or file-based
defmodule BinzPoker.CharacterGen do
  @callback generate(opts :: keyword())
    :: {:ok, %BinzPoker.Character{}}
end

# Hand evaluation - native Elixir, Rust NIF, or external
defmodule BinzPoker.HandEvaluator do
  @callback evaluate(cards :: list()) :: {:ok, %{rank: atom(), kickers: [integer()]}}
  @callback compare(hand_a, hand_b) :: :gt | :lt | :eq
end

# Game logging - file, Ecto, stdout, PubSub
defmodule BinzPoker.GameLog do
  @callback log_event(event_type :: atom(), payload :: map()) :: :ok
end
```

All implementations are config-driven:

```elixir
# config/config.exs
config :binz_poker,
  decision_engine: BinzPoker.DecisionEngine.LLM,
  llm_provider: BinzPoker.LLM.LiteLLM,
  character_gen: BinzPoker.CharacterGen.LLMBased,
  hand_evaluator: BinzPoker.HandEvaluator.Native,
  game_log: BinzPoker.GameLog.PubSubLogger

# config/test.exs
config :binz_poker,
  decision_engine: BinzPoker.DecisionEngine.Random,
  llm_provider: BinzPoker.LLM.Mock,
  character_gen: BinzPoker.CharacterGen.Hardcoded
```

## State Ownership

**Player state is NOT tied to GenServer lifecycle.** The GenServer is the "brain" (decision-making process), not the identity. Player state (character, chips, status, budget, observations) lives in **SQLite via Ecto**. GenServers cache state in memory and write through to DB on every mutation.

**The program can be stopped and resumed.** All living players, their chips, budgets, traits, backstories, and game state persist in SQLite. On restart, the Sim loads all players from the DB, spins up their GenServer brains, and resumes the game.

- If a Player GenServer crashes -> restart it, pick up the same state from DB
- If the entire program stops -> restart, load all players, resume
- If the Table asks a player for a decision and the brain is unresponsive -> graceful timeout -> auto-fold -> game continues
- Banker can inspect/modify player state directly in the DB

**Ecto schemas:**
- `sims` -- each incarnation of the simulation: hand_count, status, config columns (max_players, table_size, billing_cycle_hands, etc.), started_at, stopped_at
- `players` -- living players: sim_id (FK), player_id, character, chips, status, budget, traits, backstory, model, observations, opponent_notes, hands_played, etc.
- `leaderboard_entries` -- dead players: sim_id (FK), cause of death, hands survived, stats
- `loans` -- active/pending loans: sim_id (FK), player_id, terms, status

**On startup:** `Sim.init/1` loads all players from `players` table, starts GenServer brains for each, resumes game loop.
**On shutdown:** Nothing special -- state is already persisted. Just stop.
**During runtime:** State changes (chip updates, status changes, billing) write through to SQLite. 10 players -- no performance concern.

## Component Dependency Rules

- **Table** depends on: HandEvaluator, Player (for decisions). Owns seats. Pure poker engine.
- **Sim** depends on: Bank, PlayerSupervisor, GameLog. Reacts to Table and Bank events via PubSub. Manages player pool.
- **Player** depends on: DecisionEngine (which may use LLM), PubSub (observes world). Autonomous agent.
- **Bank** depends on: DecisionEngine (for AI banker), GameLog. Writes through to DB.
- **CharacterGen** depends on: LLM
- **Table never talks to LLM or Bank directly** - it asks Player for decisions, broadcasts results via PubSub
- **Sim never tells Table to play hands** - Table runs its own loop. Sim reacts to results.
- **Players observe each other via PubSub** - they hear table talk, see actions, form opinions
- **Bank is the single source of truth for money**
- **PubSub for everything async, GenServer.call only for Table -> Player turn decisions**

## Game Loops

### Table Loop (pure poker)

The Table runs hands continuously in a loop with a configurable delay between hands. It owns the seat list and manages the full hand lifecycle.

```
loop:
  if seats.count >= 2:
    play_hand(seats)
      -> post blinds (deduct from chip stacks)
      -> deal hole cards (2 per player)
      -> for each round [preflop, flop, turn, river]:
          -> for each active player (unlimited re-raises):
              -> send game state to Player GenServer (sync call)
              -> Player calls DecisionEngine -> gets {action, amount, talk}
              -> Table applies action to pot/stacks
              -> broadcast action_taken via PubSub
          -> deal community cards (if applicable)
      -> showdown -> evaluate hands -> award pot
      -> check for busted players (0 chips):
          -> remove from seats immediately (Table owns seats)
          -> set player status to away
          -> broadcast {:player_busted, player_id}
          -> broadcast {:seat_available, empty_count}
      -> broadcast {:hand_result, result}
      Note: busted players are removed from the seat list before the next hand.
      The player process continues running in away state with its own tick loop,
      where it can decide to request a loan, observe the table, etc.
    sleep(hand_delay_ms)
  else:
    sleep(hand_delay_ms)  # wait for more players
```

The Table knows nothing about budgets, loans, or survival. It plays poker, removes busted players, and broadcasts what happened.

**Poker engine scope:** Unlimited re-raises per betting round. Side pot calculation for all-in scenarios.

### Sim Reactor (the world)

The Sim has NO tick loop. It subscribes to PubSub and reacts to events:

```
on {:hand_result, result} from "table:events":
  -> increment hand counter
  -> Bank.settle_hand() -- deduct thinking tax from all players' budgets
  -> check for budget-broke players (budget <= 0):
      -> kick from table
      -> convert all chips to budget
      -> if budget > 0 now: player goes to away, eligible for re-seating
      -> if budget <= 0 still: trigger loan flow

on {:player_busted, player_id} from "table:events":
  -> player already removed from table by Table, status set to away
  -> chips were 0, so 0 converts to budget
  -> if budget > 0: eligible for re-seating (will do buy-in)
  -> if budget <= 0: trigger loan flow

on {:seat_available, count} from "table:events":
  -> find eligible away players (have budget > 0)
  -> for each: trigger buy-in decision (LLM call), then seat at Table

on {:loan_decided, loan_id, player_id, :approved, amount} from "bank:events":
  -> budget increased, player eligible for re-seating

on {:loan_decided, loan_id, player_id, :denied, 0} from "bank:events":
  -> if budget <= 0 AND chips = 0: eliminate player
      -> record on leaderboard
      -> spawn replacement
```

The Sim owns the player pool. The Table is just one thing happening in the room.

## Economy

### Two Currencies

| Currency | What it is | Where it lives | Visible to player? |
|----------|-----------|---------------|-------------------|
| Budget | Real money (dollars). Pays for thinking tax. | Player's account with the house | Yes (framed as "your account") |
| Chips | Table currency. Won/lost at poker. | On the table in front of you | Yes |

### Conversion Rules

| Event | What happens |
|-------|-------------|
| **Enter table** (buy-in) | Player chooses how much budget to convert to chips (LLM decision). Must leave reserve for thinking tax. |
| **Leave table** (bust or kicked) | All remaining chips automatically convert to budget. 1 chip = $0.01. |
| **Thinking tax** | After each hand, accumulated token costs deducted from budget. |

### How It Works

- 1 chip = $0.01
- Player starts with a budget of $5.00, 0 chips (buys in when seated)
- Every LLM call costs tokens, accumulated during the hand
- After each hand: thinking tax deducted from budget
- Winning chips at poker = building a reserve that converts to budget when you leave
- An expensive model (Opus) plays smart but has a massive thinking bill
- A cheap model (Haiku/local) plays simpler but survives on less

### Per-Hand Billing Flow

```
After each hand completes:
  1. Bank calculates token cost for each player's LLM calls this hand
  2. Deduct accumulated cost from each player's budget
  3. Reset each player's hand bill to 0
  4. Check for budget-broke players:
     -> if budget <= 0:
        -> kick from table after this hand
        -> all chips convert to budget
        -> if budget > 0 now: player goes to away, can re-buy-in
        -> if budget <= 0 still: trigger loan flow
```

### In-Fiction Framing

Players are told via system prompt:
> "The house charges a thinking tax. The longer you deliberate, the more it costs. Quick decisions are cheap. Your current bill: $X.XX"

They don't know about tokens. They just know thinking costs money in this world.

### Buy-In Decision

When a player is about to sit down, they receive a prompt:
> "You have ${budget} in your account. How much do you want to bring to the table?
> Remember: the house charges a thinking tax every hand. Keep enough in reserve."

The LLM responds with a buy-in amount. Traits drive this naturally:
- A greedy/reckless player might buy in with 90% of their budget
- A cautious/disciplined player might keep 40% in reserve
- A desperate player might go all-in

### Loans

- v1: Auto-approve all loans (no LLM banker yet)
- Triggered when player is broke (budget <= 0, chips = 0)
- If granted: amount added to budget
- v2: LLM banker with personality decides, interest rates, repayment deadlines

### Elimination

```
budget <= 0 AND chips = 0 AND loan denied -> permadeath
```

In v1 with auto-approve loans, players effectively don't die (infinite credit). This is intentional for testing. v2 adds real loan decisions and actual permadeath.

Cause of death recorded: bankrupt, kicked, loan_default.

## Character System

### Trait Dimensions

| Trait | Scale | Affects |
|-------|-------|---------|
| aggression | passive <-> aggressive | Bet sizing, bluff frequency, pot commitment |
| risk_tolerance | cautious <-> reckless | Hand selection, call-down tendency, bankroll management |
| discipline | impulsive <-> disciplined | Position awareness, hand selection, loss response |
| greed | content <-> greedy | Pot commitment, loan behavior, win response |
| pride | humble <-> prideful | Call-down (can't be bluffed), loss response (tilts), table talk |
| desperation | secure <-> desperate | Risk tolerance when low, loan behavior, hand selection when behind |
| deceptiveness | honest <-> deceptive | Bluff frequency, table talk, bet sizing variety |
| sociability | withdrawn <-> loud | Table talk volume, social pressure, information leakage |

Each trait randomly assigned: low / medium / high.

### Character Generation Flow

1. Roll 8 traits randomly
2. Assign a random LLM model from LiteLLM pool
3. Feed traits to an LLM to generate backstory (name, background, motivation for playing)
4. Assemble system prompt: backstory + poker rules + financial situation + house rules + response format

### System Prompt Updates Per Hand

The system prompt includes dynamic state each hand:
- Current chip stack
- Current budget and accumulated bill
- Outstanding loans and repayment status
- Recent hand history (last few hands)
- Other players' visible info (stack sizes, recent actions, table talk)

## Banker

### v1: Auto-Approve

In v1, all loan requests are automatically approved. No LLM banker, no human review. This means players effectively have infinite credit and won't die — intentional for getting the core poker loop working.

### v2: Two Modes

| Mode | Who decides | How to switch |
|------|------------|---------------|
| Auto | LLM banker with its own personality and prompt | Default / `POST /banker/auto` |
| Manual | Human (you) via API | `POST /banker/manual` |

Banker mode controls who makes **loan decisions**, NOT whether the game runs. The Table always runs independently.

### Banker API (JSON)

| Endpoint | Description |
|----------|-------------|
| `POST /banker/auto` | LLM banker takes over |
| `POST /banker/manual` | Human takes control |
| `POST /banker/loan/:id/approve` | Approve loan (manual mode) |
| `POST /banker/loan/:id/deny` | Deny loan (manual mode) |
| `POST /banker/kick/:player_id` | Kick a player |
| `POST /banker/sit` | Take a seat as a player |
| `POST /banker/leave` | Leave table, seat opens for bot |
| `POST /banker/config` | Change billing interval, loan rates, blinds |
| `POST /banker/pause` | Pause game loop |
| `POST /banker/resume` | Resume game loop |
| `GET /table/state` | Current hand, stacks, cards |
| `GET /table/log` | Recent hand history |
| `GET /players` | All players with backstories, stats |
| `GET /leaderboard` | All-time survival rankings |

## Leaderboard (SQLite)

| Field | Description |
|-------|-------------|
| character_name | "Marco Russo" |
| model | "claude-haiku-4.5" |
| traits | JSON blob of 8 traits |
| backstory | Full generated backstory |
| hands_survived | 347 |
| peak_budget | $8.42 |
| total_winnings | $12.30 |
| total_token_cost | $0.89 |
| cause_of_death | bankrupt / kicked / loan_default |
| loans_taken | 3 |
| loans_repaid | 1 |
| created_at | when they sat down |
| died_at | when they were eliminated |

## Configuration

All tunable at runtime via banker API:

```elixir
%{
  # Room
  max_players: 10,
  table_size: 6,

  # Economy
  starting_budget: 5.00,      # dollars, pays for thinking tax + chip buy-in
  small_blind: 1,
  big_blind: 2,

  # Timing
  hand_delay_ms: 5000,

  # Banker
  auto_banker: true            # v1: auto-approve all loans
}
```

## Prompt Design & Roleplay Rules

Immersion is critical. Every prompt must maintain the fiction. Players and banker are characters in a world, not AIs playing a game.

### Player System Prompt Structure

```
[IDENTITY]
You ARE {character_name}. You are not an AI. You are not roleplaying.
You are a poker player sitting at a high-stakes table in the Binz Poker Room.

[BACKSTORY]
{generated backstory - 2-3 paragraphs}

[YOUR SITUATION]
You have {chips} chips in front of you.
Your account with the house: ${budget} remaining.
The house charges a thinking tax every hand - the longer you deliberate, the more it costs.
Your bill so far this hand: ${accumulated_bill}.
When you leave the table, your chips convert back to cash in your account.

[THE ROOM]
The Binz Poker Room has rules:
- The house takes a thinking tax. Be decisive.
- You can request a loan from the banker if you're running low.
- If you can't pay your bills, you're out. Permanently.
- {N} other players at the table: {brief descriptions of opponents
  based on what this player has observed - stack sizes, play style,
  recent table talk}

[THIS HAND]
{game state: your hole cards, community cards, pot, actions so far}

[RESPOND AS YOUR CHARACTER]
Think through your decision in character. Stay true to who you are.
Respond in JSON:
{
  "inner_thought": "your private reasoning (1-2 sentences, in character)",
  "action": "fold|call|raise|all_in",
  "amount": <number if raising>,
  "table_talk": "what you say out loud to the table (optional, in character)"
}
```

### Prompt Rules

- **Never say "as an AI"** - The system prompt establishes identity. If the LLM breaks character, that's a prompt engineering bug to fix.
- **Inner thought is in-character** - Not analytical. "I can't lose this hand, Maria needs the surgery money" not "The pot odds are 3:1".
- **Table talk is optional** - A withdrawn character might say nothing for 10 hands. A loud one talks every hand. Driven by sociability trait.
- **Financial awareness is diegetic** - They know they owe money, they know thinking costs money, but framed as the world they live in, not as API costs.
- **Memory across hands** - The player receives a brief history of recent hands (last 5-10) so they can reference past events: "You just lost a big pot to the guy in seat 3 who bluffed you."
- **Opponents are described, not named by model** - "The quiet woman in seat 2 who hasn't raised in 8 hands" not "Claude Haiku in seat 2."

### Banker System Prompt (AI Mode)

```
[IDENTITY]
You are the banker of the Binz Poker Room. You've run this room for years.
You decide who gets credit and who gets shown the door.

[YOUR PHILOSOPHY]
{generated banker personality - e.g. "You're fair but firm. You've seen
too many gamblers destroy themselves. You give second chances, but not thirds."}

[LOAN REQUEST]
{player_name} is asking for a ${amount} loan.
Here's what you know about them:
- Background: {short backstory summary}
- Been at the table for {N} hands
- Current chips: {chips}, Budget: ${budget}
- Win rate: {percentage} over last {N} hands
- Existing loans: {details or "clean record"}
- Their message to you: "{player's loan request in their own words}"

[DECIDE]
Approve or deny. Set terms if approving. Speak to them directly.
{
  "decision": "approve|deny",
  "amount": <if approving, may differ from requested>,
  "interest_rate": <if approving>,
  "message": "what you say to the player (in character)"
}
```

### Loan Request Prompt (Player Side)

When a player's budget drops below a threshold, they get an additional prompt:

```
[FINANCIAL CRISIS]
Your account is running dangerously low. You have ${budget} left.
At this rate, you won't survive the next billing cycle.

You can request a loan from the house banker.
What do you say to them? Be persuasive. Or don't - it's your call.
{
  "request_loan": true|false,
  "amount": <how much>,
  "message": "what you say to the banker (in character)"
}
```

A prideful character might refuse to ask. A desperate one might beg. A deceptive one might lie about why they need it.

## v2 Scope (Not in v1)

- **Player autonomous tick loop** — Inner monologue, observations, trash-talk between hands. Each tick costs tokens. Chatty players burn money, quiet ones conserve. Tick rate varies by personality (anxious = faster = more expensive).
- **LLM Banker** — The banker becomes an LLM-driven character with personality. Decides loans based on player history, traits, and persuasiveness. Interest rates, repayment deadlines, and actual permadeath.
- **Private DMs** between players (collusion, alliances, betrayal)
- **Human player mode** (take a seat and play)
- **LiveView UI** for real-time observation
- **Voluntary chip-to-budget conversion** — Players can cash out chips mid-session without leaving the table (LLM decision during tick loop)

## Project Location

Repository: `~/repo/binz-poker`
