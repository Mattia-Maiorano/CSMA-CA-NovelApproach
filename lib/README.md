# Daemon – CSMA/CA-style protocol + MDP methodology (report-focused)

This README is written for a **university report**. It focuses on:

1) the **CSMA/CA-like MAC implementation** (timers, backoff, NAV, collision detection, and message exchange), and
2) how **MDP/Q-learning** is integrated and evaluated,

while keeping Flutter/repo overview minimal and oriented to **exporting and analyzing results**.

Primary “what to cite” files:
- Protocol state machine: [lib/domain/entities/entity.dart](lib/domain/entities/entity.dart)
- Classic CSMA logic: [lib/domain/entities/classic_car.dart](lib/domain/entities/classic_car.dart), [lib/domain/entities/classic_rsu.dart](lib/domain/entities/classic_rsu.dart)
- Medium/collision model: [lib/domain/network/medium.dart](lib/domain/network/medium.dart), [lib/domain/network/signal.dart](lib/domain/network/signal.dart)
- Simulation scheduling: [lib/application/loop.dart](lib/application/loop.dart)
- MDP wrappers + rewards: [lib/domain/entities/mdp_car.dart](lib/domain/entities/mdp_car.dart), [lib/domain/entities/mdp_rsu.dart](lib/domain/entities/mdp_rsu.dart)
- Q-learning agent: [lib/domain/ai/q_agent.dart](lib/domain/ai/q_agent.dart)
- Metrics/export + epsilon adaptation: [lib/utils/analyzer.dart](lib/utils/analyzer.dart), [lib/utils/config.dart](lib/utils/config.dart)
- Results viewer (plots): [lib/utils/resumer.dart](lib/utils/resumer.dart)

---

## 1) Minimal repo + Flutter overview (only what you need for analysis)

Daemon is a Flutter app that runs an **agent-based communication simulation** and exports logs/JSON suitable for analysis.

- App entrypoint: [lib/main.dart](lib/main.dart)
- Experiment UI (config/start/stop/export): [lib/presentation/home.dart](lib/presentation/home.dart)

**How results are produced and consumed**

- During simulation, an `Analyzer` collects metrics.
- On STOP / export, the Analyzer writes:
  - a human-readable log summary and
  - a machine-readable JSON (often zipped with the log).
- You can inspect plots and series via the “Resumer” UI.

Export + plotting:
- Export logic: [lib/utils/analyzer.dart](lib/utils/analyzer.dart)
- ZIP writers (desktop/web): [lib/utils/analyzer_writer_io.dart](lib/utils/analyzer_writer_io.dart), [lib/utils/analyzer_writer_web.dart](lib/utils/analyzer_writer_web.dart)
- Plotting/inspection tool: [lib/utils/resumer.dart](lib/utils/resumer.dart)

---

## 2) Simulation time model (important for methodology)

Time is discrete and hierarchical:

- The UI runs “frames” at `FPS`.
- Each frame contains `SUBFRAMES` **ticks**.
- Each tick is a single scheduling quantum for all nodes.

Per tick, the simulation does:
1. step all Cars
2. step all RSUs
3. update car repository snapshot
4. advance the Medium (`Medium.step()`)

Implementation: [lib/application/loop.dart](lib/application/loop.dart)

Why this matters:
- The design allows you to treat each `SUBFRAMES` block as one **episode/interval** for learning and for end-of-interval metrics.
- It also makes protocol timers (DIFS/SIFS, NAV, backoff slots) naturally expressible as “tick counters”.

---

## 3) CSMA/CA-style protocol implementation

This project implements a **CSMA/CA-inspired** channel access mechanism with:

- carrier sensing (“Medium sensing”) + collision indication,
- DIFS/SIFS inter-frame spaces,
- RTS/CTS handshake,
- NAV-based virtual carrier sense,
- randomized backoff with exponential growth,
- timeouts and reset behavior.

It is not a full IEEE 802.11 implementation; it is a **research/teaching model** that isolates the key algorithmic mechanisms.

### 3.1 Core state machine and stages

All nodes inherit from the same base machine: [lib/domain/entities/entity.dart](lib/domain/entities/entity.dart)

**States**
- `idle`: not actively transmitting/receiving; may count down until a new attempt.
- `querying`: actively attempting to transmit (subject to DIFS/SIFS/backoff).
- `waiting`: expecting the next message (e.g., CTS after RTS).
- `collision`: recovery mode after failed progression.
- `sleeping`: passive state used when NAV virtual carrier-sense defers access.

**Stages** (protocol phases)
- `idle → rts → cts → query → response → ack`

Practical interpretation:
- “state” decides whether you are sending vs waiting vs deferring.
- “stage” defines which message is expected next.

### 3.2 Signals and timing (DIFS/SIFS, NAV)

Signals: [lib/domain/network/signal.dart](lib/domain/network/signal.dart)

Types: `rts`, `cts`, `query`, `response`, `ack`, plus synthetic `broken`.

Durations are fixed constants:
- `RTSDURATION`, `CTSDURATION`, `QUERYDURATION`, `RESPONSEDURATION`, `ACKDURATION`

Inter-frame spaces:
- `DIFS`: used before starting contention and RTS.
- `SIFS`: used between handshake messages.

Virtual carrier sense (NAV):
- Nodes maintain a `nav` timer.
- When a node observes an ongoing exchange (`communicationOngoing` on a visible signal), it updates `nav` and resets local contention without clearing NAV.
- NAV times are derived from the remaining handshake timeline:
  - `NAVTIME`, `NAVTIMECTS`, `NAVTIMEQUERY`, `NAVTIMERESPONSE`, `NAVTIMEACK`

These parameters are centralized in: [lib/utils/config.dart](lib/utils/config.dart)

**Design choice**: NAV is computed based on message type (a coarse “how long the medium will remain busy”).

Pros:
- Captures the essence of virtual carrier-sense without simulating PHY-level headers.
- Makes hidden-terminal style effects possible at the abstraction level.

Cons:
- NAV is idealized (no header decoding errors, no partial reception effects).
- Timing is quantized in ticks, which can distort real-time ratios unless carefully calibrated.

### 3.3 Carrier sense and collision model (“broken” signal)

Medium: [lib/domain/network/medium.dart](lib/domain/network/medium.dart)

The Medium stores “in-flight” signals and provides `sense()`:
- If exactly one signal is in range, it is returned.
- If **more than one** signal is in range, `sense()` returns a synthetic `SignalType.broken`.

Interpretation:
- `broken` acts as a **collision indicator** for nodes that are in reception range.

Important simplification:
- Collisions are detected by receiver-side ambiguity (multiple signals simultaneously visible).
- There is no capture effect, SINR, propagation delay, or partial overlap modeling.

Pros (for a university simulation):
- Collision logic is deterministic and easy to reason about.
- Keeps the model focused on MAC behavior (contention/backoff/NAV) rather than PHY.

Cons (limitations to mention):
- Real wireless collisions can be asymmetric (one receiver sees collision while another successfully decodes).
- This model tends to make collisions “all-or-nothing” within a local neighborhood.

### 3.4 Backoff and exponential contention window growth

Backoff is implemented in the entities’ timers (see classic Car/RSU):
- Car: [lib/domain/entities/classic_car.dart](lib/domain/entities/classic_car.dart)
- RSU: [lib/domain/entities/classic_rsu.dart](lib/domain/entities/classic_rsu.dart)

Mechanism:
- After DIFS (or after certain SIFS boundaries), a node requests a send.
- It samples a random backoff from a contention window that grows with `consecutiveCollisions`.
- When backoff reaches 0, the node is allowed to transmit.

Key design parameters:
- `STARTING_EXPONENT`, `MAX_BACKOFF_EXPONENT`
- `BACKOFF_SLOT_TIME` (note: slot-time is represented as tick counting logic)

Pros:
- Captures the core stability mechanism of CSMA/CA under load.

Cons:
- The contention window formula is simplified and discrete; it may not match a specific standard’s CWmin/CWmax.

### 3.5 Handshake structure (RTS/CTS/QUERY/RESPONSE/ACK)

Handshake semantics in this project:

- **Car initiates**:
  - At certain intervals (driven by `broadcastTimer`) a Car enters `querying` and contends.
  - It sends `RTS` (destination broadcast / unspecified).
- **RSU responds**:
  - Receives RTS → replies with `CTS`.
  - Receives `QUERY` → replies with `RESPONSE` (with `SignalData.stop` or `SignalData.free`).
- **Car completes**:
  - Receives `RESPONSE` → sends `ACK`.

Classic implementations:
- Car: [lib/domain/entities/classic_car.dart](lib/domain/entities/classic_car.dart)
- RSU: [lib/domain/entities/classic_rsu.dart](lib/domain/entities/classic_rsu.dart)

Design choice: a richer-than-802.11 message sequence (`QUERY/RESPONSE`) is used to model “application-level” interaction (road assistance decision), while still running over a CSMA/CA-like access method.

---

## 4) MDP / Q-learning integration (design choices + methodology)

In MDP mode, the protocol is not replaced; instead, learning agents **choose discrete control actions** that influence when/if nodes contend.

Key idea:
- Keep the **protocol mechanics** (CSMA, NAV, timers, handshake validation) intact.
- Let the agent decide *when to trigger attempts* or *when to defer*.

### 4.1 Where learning is injected

- MDP car wrapper: [lib/domain/entities/mdp_car.dart](lib/domain/entities/mdp_car.dart)
- MDP RSU wrapper: [lib/domain/entities/mdp_rsu.dart](lib/domain/entities/mdp_rsu.dart)

The MDP wrappers override `handleState()` to:
1) build a compact state,
2) choose an action via `Agent.chooseAction(state)`,
3) apply the action by manipulating existing timers/flags,
4) fall back to the base protocol logic (`super.handleState()`).

This is an important research design choice:
- It constrains the policy class to “timing/control” decisions, which improves interpretability.
- It prevents the agent from violating protocol correctness (e.g., sending CTS in the wrong stage).

### 4.2 Action space (and why it is small)

Car actions (MDPCar):
- `noop`: do nothing.
- `startQuery`: force a query attempt by setting `broadcastTimer = 0`.
- `defer`: add a small extra backoff (random 1..3 ticks).

RSU actions (MDPRSU):
- `noop`
- `defer`

Pros:
- Low-dimensional control makes learning feasible with tabular Q-learning.
- Easy to explain in a report and to map back to MAC concepts (“transmit now vs wait”).

Cons / risks:
- The agent cannot express more nuanced strategies (e.g., adaptive contention-window sizing, dynamic range/power, message-type changes).
- With too small an action set, improvement can saturate quickly.

### 4.3 State representation (feature engineering)

State is deliberately compact and mostly integer-valued (good for a tabular Q-table):

Common features (both Car/RSU):
- `seenCars`: unique cars observed recently (local congestion proxy).
- `prevKnownCars`: a lagged version to capture trend / persistence.
- `tickBin`: coarse discretization of time within an episode (0..3).
- `comm`: whether a communication is ongoing.

Pros:
- Interpretable: each feature has a MAC/traffic meaning.
- Discrete features reduce sample complexity for Q-learning.

Cons:
- Partial observability: nodes do not observe global traffic, only local sensing.
- Feature aliasing: many distinct situations map to the same discrete bin.

### 4.4 Q-learning implementation details

Agent: [lib/domain/ai/q_agent.dart](lib/domain/ai/q_agent.dart)

Implementation highlights:
- Tabular Q-learning with an epsilon-greedy policy.
- State keys are built by sorting state keys and concatenating (`k=v|k=v|...`).
- Update rule:
  - $Q(s,a) \leftarrow Q(s,a) + \alpha\,[r + \gamma \max_{a'} Q(s',a') - Q(s,a)]$
  - Supports a `gammaOverride` to rescale discounting based on remaining ticks.

Design choice: `gammaOverride` aligns “per-tick learning” with a **frame-level target discount** `GAMMA_FRAME`.
- Rationale: we want a consistent discount across the whole subframe, even though learning is called each tick.

Pros:
- Stabilizes learning under different `SUBFRAMES` sizes.

Cons:
- It’s a heuristic; not equivalent to a fully episodic formulation unless carefully validated.

### 4.5 Reward shaping (explicit methodology)

Reward shaping is implemented in the MDP wrappers:
- Car: [lib/domain/entities/mdp_car.dart](lib/domain/entities/mdp_car.dart)
- RSU: [lib/domain/entities/mdp_rsu.dart](lib/domain/entities/mdp_rsu.dart)

Key pattern used:
- small intermediate rewards for “being in a valid communication context” (communication ongoing or NAV active)
- **continuous reward** based on performance metrics (applied each tick, not just terminal)
- Car rewards based on resolution timing curve, RSU rewards based on response rate curve

Car reward system:
- **Curve-based on resolution timing**: Early resolution = high reward, late resolution = low reward
- Immediate resolution (tick 0): +5 total episode reward
- Mid-episode resolution (tick 50%): 0 total episode reward  
- Late resolution (tick 100%): -5 total episode reward
- Never resolves: -5 total episode reward
- **Subdivided per tick**: Continuous feedback throughout episode
- Encourages cars to complete communication as early as possible

RSU reward system:
- **Gaussian-like curve** symmetric around 50% response rate
- Neutral (0) at 50% cars answered
- Positive rewards for high completion: +1 at 50%, +2 at 65%, +3 at 75%, +4 at 82%, +5 at 87%
- Symmetrically negative for low completion: -1 at 50%, -2 at 35%, -3 at 25%, -4 at 18%, -5 at 13%
- **Subdivided per tick**: Each tick contributes `reward/SUBFRAMES` to maintain total episode reward in ±5.0 range
- Applied continuously throughout the episode for more frequent learning feedback

Pros:
- Encourages policies that maximize response rate throughout the episode
- Provides continuous feedback for stable learning
- Symmetric reward curve creates balanced incentives for both high and low performance

Cons (important to discuss in a report):
- Shaping can create local optima (agents learn to keep NAV/comm flags active even if it doesn't improve real throughput)
- Continuous rewards may reduce the impact of terminal performance evaluation

### 4.6 Exploration scheduling via Analyzer (epsilon adaptation)

The Analyzer tracks per-node rewards and can adapt epsilon based on a **reward trend (slope) detector**:
- Configuration lives in: [lib/utils/config.dart](lib/utils/config.dart)
- Logic lives in: [lib/utils/analyzer.dart](lib/utils/analyzer.dart)
- Slope helper: [lib/utils/slope_utils.dart](lib/utils/slope_utils.dart)

Mechanism:
1. After enough episodes (`REWARD_GRAD_WINDOW`), compute linear regression slope over the last window.
2. If slope is below an effective threshold (`REWARD_GRAD_THRESHOLD * REWARD_GRAD_SENSITIVITY`), treat it as “learning degrading”.
3. Increase epsilon by `EPSILON_INC` (bounded by `EPSILON_MAX`).
4. Enforce a cooldown: `EPSILON_COOLDOWN_EPISODES`.
5. Also apply passive decay toward `EPSILON_BASELINE` via `EPSILON_DECAY_FACTOR`.

Pros:
- Works as an automatic “re-exploration trigger” when learning stalls.
- Makes experiments more robust when hyperparameters aren’t perfectly tuned.

Cons:
- A reward slope drop might be due to stochasticity, not true degradation.
- Can destabilize convergence if it triggers too frequently (hence cooldown).

Visualization:
- When epsilon changes, the entity gets a temporary marker drawn (purple ring): [lib/presentation/painter.dart](lib/presentation/painter.dart)

---

## 5) Methodology for experiments (what to write in a report)

This section is written as a “method” template.

### 5.1 Experimental factors (independent variables)

Protocol/environment knobs (typical):
- `CARNUM`, `RSUNUM` (load)
- `RANGE` and sensing ranges (local contention neighborhood)
- `SUBFRAMES` (episode length)
- `FPS` (wall-clock pacing; does not change logical tick progression)

Learning knobs:
- Q-learning: `alpha`, `gamma`, `epsilon` (initial)
- Epsilon adaptation: `EPSILON_WINDOW`, `EPSILON_INC`, `EPSILON_COOLDOWN_EPISODES`, `EPSILON_DECAY_FACTOR`, `EPSILON_BASELINE`

All centralized defaults: [lib/utils/config.dart](lib/utils/config.dart)

### 5.2 Dependent variables (what you measure)

From Analyzer summary + JSON series:
- **Busy medium %** (proxy for channel occupancy)
- **Idle %** (how often nodes do nothing)
- **Soft/hard reset rates** (contention/collision severity)
- **Throughput proxy**: $\text{throughput} = \frac{\#ACK}{\#RTS}$
- **Learning curves** per node: reward trend, epsilon over time, slope measurements

Collector: [lib/utils/analyzer.dart](lib/utils/analyzer.dart)

### 5.3 Baselines and comparisons

Recommended comparisons:
- Classic mode vs MDP mode (same `CARNUM`, `RSUNUM`, ranges, timers)
- Multiple seeds / multiple runs (to address stochasticity from:
  - random placement,
  - random backoff,
  - epsilon-greedy action selection)

Important note for a report:
- The current code uses randomness without an explicit global seed control in the UI.
- Methodologically, compensate by repeating runs and reporting mean/variance.

### 5.4 Threats to validity (good to include)

Internal validity:
- Reward shaping may bias policies toward shaped objectives rather than true system-level QoS.
- Episodes are aligned to `SUBFRAMES`; changing it changes the learning problem.

External validity:
- Medium model is simplified (no PHY, no propagation delays/capture effects).
- Collision model is based on “multiple visible signals => broken”, which is a coarse approximation.

Construct validity:
- “Throughput = ACK/RTS” is a proxy; it’s useful but does not measure end-to-end application success directly.

---

## 6) How to export and analyze results (practical workflow)

### 6.1 Running and exporting

UI steps:
1. Configure Cars/RSUs/FPS and toggle “Use MDP Agents”.
2. Start simulation.
3. Stop to trigger export (or use the export icon).

UI file: [lib/presentation/home.dart](lib/presentation/home.dart)

Desktop export location:
- Typically `~/Desktop/analyzer_exports/` (created if missing).

### 6.2 What is inside the export

The Analyzer generates:
- a text summary log (human-readable) and
- a JSON containing step-level series.

The Resumer is designed to load either raw JSON or a ZIP containing a JSON.

### 6.3 Using Resumer to extract plots for the report

Resumer: [lib/utils/resumer.dart](lib/utils/resumer.dart)

Recommended report figures:
- Reward curves per node (Car vs RSU)
- Epsilon over time (and epsilon-change events)
- Environment-level throughput series (if present)

Interpretation tips:
- Prefer comparing **recent averages** (last 10% of frames/episodes) rather than only global averages.
- Report confidence intervals or std-dev across multiple runs.

---

## 7) High-level map of the `lib/` folder (for appendix-level overview)

This is the quick navigation map; details above cover what matters for the report.

- Simulation loop: [lib/application/loop.dart](lib/application/loop.dart)
- Domain entities + protocol: [lib/domain/entities/entity.dart](lib/domain/entities/entity.dart), [lib/domain/entities/classic_car.dart](lib/domain/entities/classic_car.dart), [lib/domain/entities/classic_rsu.dart](lib/domain/entities/classic_rsu.dart)
- Learning variants: [lib/domain/entities/mdp_car.dart](lib/domain/entities/mdp_car.dart), [lib/domain/entities/mdp_rsu.dart](lib/domain/entities/mdp_rsu.dart)
- Medium model: [lib/domain/network/medium.dart](lib/domain/network/medium.dart), [lib/domain/network/signal.dart](lib/domain/network/signal.dart)
- Agent: [lib/domain/ai/q_agent.dart](lib/domain/ai/q_agent.dart)
- Metrics/export/config: [lib/utils/analyzer.dart](lib/utils/analyzer.dart), [lib/utils/config.dart](lib/utils/config.dart)
- Results UI: [lib/utils/resumer.dart](lib/utils/resumer.dart)
