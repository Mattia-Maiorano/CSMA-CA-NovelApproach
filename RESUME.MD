# Daemon - V2X Communication Simulation with MDP/Q-Learning

## Project Overview

This Flutter application simulates **Vehicle-to-Infrastructure (V2X)** communication using a **Markov Decision Process (MDP)** framework with **Q-Learning** agents. The simulation models cars and Road Side Units (RSUs) communicating over a shared wireless medium, implementing collision avoidance protocols inspired by **CSMA/CA (Carrier Sense Multiple Access with Collision Avoidance)**.

---

## Table of Contents

1. [Agent States](#1-agent-states)
2. [Actions](#2-actions)
3. [Training](#3-training)
4. [Protocol](#4-protocol)
5. [MDP Implementation](#5-mdp-implementation)
6. [Epsilon-Greedy Implementation](#6-epsilon-greedy-implementation)
7. [Testing Environment](#7-testing-environment)
8. [Visualization Tools](#8-visualization-tools)

---

## 1. Agent States

### 1.1 Node States (`NodeState` enum)

Each entity (Car or RSU) operates in one of the following states:

| State | Description |
|-------|-------------|
| `idle` | Node is inactive, waiting for events |
| `sleeping` | Node is in sleep mode (NAV timer active) |
| `waiting` | Node is waiting for a response |
| `querying` | Node is actively transmitting/communicating |
| `collision` | Node detected a collision and is handling it |

### 1.2 Talking Stages (`TalkingStage` enum)

The communication protocol follows these stages:

| Stage | Description |
|-------|-------------|
| `idle` | No active communication |
| `rts` | Request To Send |
| `cts` | Clear To Send |
| `query` | Sending the actual query/data |
| `response` | Receiving response from RSU |
| `ack` | Acknowledgment |

### 1.3 MDP Car State Representation

The MDPCar agent observes a state with these features:

```dart
Map<String, dynamic> _state() => {
  'tick': (tick * 4) ~/ SUBFRAMES,  // Discretized time within frame
  'busy': nav > 0 ? 1 : 0,           // Is medium currently busy?
  'resolved': (free || stop) ? 1 : 0 // Has communication been resolved?
}
```

### 1.4 MDP RSU State Representation

The MDPRSU agent observes:

```dart
Map<String, dynamic> _state() => {
  'tick': (tick * 4) ~/ SUBFRAMES,                    // Discretized time
  'busy': nav > 0 ? 1 : 0,                             // Is medium busy?
  'queue': (knownCars.length - _answered.length).clamp(0, 4)  // Pending requests
}
```

---

## 2. Actions

### 2.1 Car Actions

| Action | Description |
|--------|-------------|
| `startComm` | Initiate communication (sets `broadcastTimer = 0` to trigger query) |
| `defer` | Wait/backoff (sets random `backoffSlots` between 1-3) |

### 2.2 RSU Actions

| Action | Description |
|--------|-------------|
| `ready` | Be available to respond to incoming requests |
| `defer` | Wait/backoff (sets random `backoffSlots` between 1-3) |

---

## 3. Training

### 3.1 Q-Learning Algorithm

The system uses tabular Q-Learning with the following update rule:

```
Q(s, a) = Q(s, a) + α * (r + γ * max(Q(s', a')) - Q(s, a))
```

**Hyperparameters** (configured in `config.dart`):

| Parameter | Default | Description |
|-----------|---------|-------------|
| `alpha` | 0.1 | Learning rate |
| `gamma` | 0.99 | Discount factor |
| `epsilon` | 0.9 | Initial exploration rate |
| `GAMMA_FRAME` | 0.99 | Frame-level discount factor |

### 3.2 Reward Structure

#### Car Rewards

| Condition | Reward | Description |
|-----------|--------|-------------|
| Success (`free` or `stop`) | +3.0 | Communication completed successfully |
| Soft collision | -1.0 × cf | Recoverable collision (scaled by congestion) |
| Hard collision | -2.0 × cf | Unrecoverable collision (scaled by congestion) |
| Failed communication | -0.5 × cf | Communication failed (scaled by congestion) |
| Defer action | -0.1 | Flat deferral cost |
| Unfinished at frame end | -3.0 or +1.0 | Penalty/bonus based on resolution state |

#### RSU Rewards

| Condition | Reward | Description |
|-----------|--------|-------------|
| Successful response | +2.0 | Responded to a car request |
| Soft collision | -0.5 × cf | Recoverable collision (scaled by congestion) |
| Hard collision | -1.0 × cf | Unrecoverable collision (scaled by congestion) |
| Ready but no car | -0.2 × cf | Missed opportunity (scaled by congestion) |
| Defer action | -0.1 | Flat deferral cost |

#### Congestion Factor

Both entities use a non-linear congestion factor to soften penalties in crowded conditions:

```dart
double _congestionFactor() {
  final n = seenCarIds.length; // or knownCars.length for RSU
  return 1.0 / (1.0 + 0.5 * n * n);  // Quadratic scaling
}
```

| Cars nearby | Congestion Factor |
|-------------|-------------------|
| 0 | 1.0 |
| 1 | 0.67 |
| 2 | 0.33 |
| 3 | 0.18 |
| 4 | 0.11 |

### 3.3 Decision-Based Learning

MDP entities use **decision-based learning** (not per-tick):

1. **Decision Point Check**: Agent is consulted only when `_canDecide()` returns true:
   - Car: `state == idle`, `nav == 0`, not resolved, not waiting for outcome
   - RSU: `state == idle`, `nav == 0`, not waiting for outcome

2. **Outcome Tracking**: After choosing an action, the entity waits for resolution:
   - Car: Communication completed, collision detected, or resolution achieved
   - RSU: Response given, collision detected, or backoff expired

3. **Immediate Learning**: Upon outcome resolution, `agent.learn()` is called with the actual reward

### 3.4 Training Configuration

```dart
final int MAX_EPISODES = 1000;        // Maximum training episodes
final int SUBFRAMES = 1000;           // Ticks per episode/frame
final int TRAINING_INTERVAL = 1;      // Steps between weight updates
```

---

## 4. Protocol

### 4.1 Communication Protocol (RTS/CTS/Query/Response/ACK)

The protocol implements a 5-way handshake similar to IEEE 802.11 RTS/CTS:

```
Car                     RSU
 |                       |
 |------- RTS ---------> |  (Request To Send)
 |<------ CTS ---------- |  (Clear To Send)
 |------- Query -------> |  (Actual data request)
 |<------ Response ----- |  (RSU's response: stop/free)
 |------- ACK ---------> |  (Acknowledgment)
 |                       |
```

### 4.2 Signal Types

```dart
enum SignalType {
  broken,    // Collision detected
  rts,       // Request To Send
  cts,       // Clear To Send
  query,     // Data query
  response,  // RSU response
  ack        // Acknowledgment
}

enum SignalData {
  stop,      // Car should stop
  free       // Car can proceed
}
```

### 4.3 Timing Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `DIFS` | 40 | Distributed Inter-Frame Space |
| `SIFS` | 10 | Short Inter-Frame Space |
| `BROADCAST` | 100 | Broadcast interval |
| `RESETTIME` | 150 | Timeout before reset |
| `RTSDURATION` | 1 | RTS signal duration |
| `CTSDURATION` | 5 | CTS signal duration |
| `QUERYDURATION` | 7 | Query signal duration |
| `RESPONSEDURATION` | 7 | Response signal duration |
| `ACKDURATION` | 5 | ACK signal duration |

### 4.4 NAV (Network Allocation Vector) Times

| Signal | NAV Duration |
|--------|--------------|
| RTS | `NAVTIME` (full handshake) |
| CTS | `NAVTIMECTS` |
| Query | `NAVTIMEQUERY` |
| Response | `NAVTIMERESPONSE` |
| ACK | `NAVTIMEACK` |

### 4.5 Collision Handling

- **Soft Reset**: Recoverable collision handling with exponential backoff
- **Hard Reset**: Full state reset after `MAX_BACKOFF_EXPONENT` (5) consecutive collisions
- **Backoff**: Random slots from 0 to `2^(consecutiveCollisions) - 1`

---

## 5. MDP Implementation

### 5.1 Agent Interface

```dart
abstract class Agent {
  final int id;
  final List<String> actions;

  Map<String, dynamic> stateFromEntity(dynamic entity);
  String chooseAction(Map<String, dynamic> state);
  void learn(Map<String, dynamic> state, String action, double reward, 
             Map<String, dynamic> nextState, {bool done = false, double? gammaOverride});
  Map<String, double> parameters();
  double getEpsilon();
  void setEpsilon(double e);
}
```

### 5.2 QAgent Implementation

The `QAgent` class implements tabular Q-Learning:

```dart
class QAgent extends Agent {
  final Map<String, Map<String, double>> _qTable = {};
  double alpha;   // Learning rate
  double gamma;   // Discount factor
  double epsilon; // Exploration rate
}
```

**Key Methods:**

- `_keyFromState()`: Converts state dict to string key for Q-table lookup
- `chooseAction()`: Epsilon-greedy action selection
- `learn()`: TD(0) Q-value update
- `toJson()`/`fromJson()`: Q-table serialization for persistence

### 5.3 State Encoding

States are encoded as pipe-separated key-value pairs:

```dart
String _keyFromState(Map<String, dynamic> s) {
  final sorted = s.keys.toList()..sort();
  return sorted.map((k) => '$k=${s[k]}').join('|');
}
// Example: "busy=0|resolved=0|tick=2"
```

### 5.4 MDP Entity Architecture

```
Entity (abstract base)
├── Car (classic CSMA/CA behavior)
│   └── MDPCar (RL-enhanced decision making)
└── RSU (classic RSU behavior)
    └── MDPRSU (RL-enhanced decision making)
```

**MDPCar and MDPRSU extend their classic counterparts** by:
1. Overriding `handleState()` to inject agent decisions
2. Overriding `specificStep()` to trigger learning after outcome resolution
3. Tracking decision state, pending action, and waiting-for-outcome flag

---

## 6. Epsilon-Greedy Implementation

### 6.1 Action Selection

```dart
String chooseAction(Map<String, dynamic> state) {
  final key = _keyFromState(state);
  if (!_qTable.containsKey(key)) _qTable[key] = _initActionMap();
  
  // Epsilon-greedy exploration
  if (_rnd.nextDouble() < epsilon) {
    return actions[_rnd.nextInt(actions.length)];  // Random action
  }
  
  // Greedy exploitation
  String best = actions.first;
  double bestV = double.negativeInfinity;
  for (final a in actions) {
    final v = _qTable[key]![a]!;
    if (v > bestV) {
      bestV = v;
      best = a;
    }
  }
  return best;
}
```

### 6.2 Adaptive Epsilon

The Analyzer implements **adaptive epsilon** based on reward gradient:

```dart
// Configuration
final int EPSILON_WINDOW = 100;         // Frames per comparison window
final double EPSILON_INC = 0.5;         // Increase on degradation
final double EPSILON_MAX = 1.0;         // Maximum epsilon
final double EPSILON_MIN = 0.0;         // Minimum epsilon
final int EPSILON_COOLDOWN_EPISODES = 200; // Cooldown between changes
final double EPSILON_DECAY_FACTOR = 0.92;  // Passive decay per episode
final double EPSILON_BASELINE = 0.05;   // Minimum baseline epsilon
```

**Adaptation Logic:**

1. **Passive Decay**: Every episode, epsilon decays: `ε = ε × 0.92` (until baseline)
2. **Gradient Check**: Compare average reward of last `EPSILON_WINDOW` frames vs previous window
3. **Increase on Degradation**: If `recentAvg < prevAvg`, increase epsilon by `EPSILON_INC`
4. **Cooldown**: Prevent rapid changes with `EPSILON_COOLDOWN_EPISODES`

---

### 6.3 Toggle for Adaptive Epsilon

- **Configuration flag:** You can enable or disable Analyzer-driven epsilon adaptiveness via the `ENABLE_EPSILON_ADAPT` flag in [lib/utils/config.dart](lib/utils/config.dart).
- **When enabled (default):** Analyzer will perform passive decay each episode and may increase epsilon when the reward gradient indicates degradation.
- **When disabled:** Analyzer will neither decay nor increase agent epsilons; agents will retain whatever epsilon they have unless changed by other code.

### 6.4 Non-MDP Executions (how epsilon is handled)

- **Non-MDP mode (`USE_MDP = false`)**: The simulation instantiates classic `Car` and `RSU` entities without attaching `Agent` instances. The `Analyzer`'s MDP tracking is not enabled in this mode (see `Loop.start()`), so no epsilon adaptation occurs and learning is inactive.
- **Why:** Epsilon is meaningful only for agents that implement exploration/exploitation (e.g., `QAgent`). In non-MDP runs there are no such agents, so adaptive epsilon is irrelevant and safely ignored.
- **Recommendation for evaluations:** For reproducible, deterministic experiments set `ENABLE_EPSILON_ADAPT = false` and either set agent epsilons to fixed values (when running MDP agents) or run in `USE_MDP = false` to use classic protocol behavior.

## 7. Testing Environment

### 7.1 Test Files

| Test File | Purpose |
|-----------|---------|
| `q_agent_test.dart` | Q-Learning algorithm correctness |
| `mdp_car_clean_test.dart` | MDPCar decision-point learning |
| `mdp_rsu_test.dart` | MDPRSU decision-point learning |
| `signal_flow_test.dart` | Communication protocol flow |
| `analyzer_helpers_test.dart` | Analyzer utility functions |
| `analyzer_slope_export_test.dart` | Export functionality |
| `config_recommend_test.dart` | Configuration recommendations |
| `reward_grad_test.dart` | Reward gradient computation |
| `slope_utils_test.dart` | Slope calculation utilities |

### 7.2 Test Agent Mock

```dart
class TestAgent implements Agent {
  int chooseCount = 0;
  int learnCount = 0;
  Map<String, dynamic>? lastState;
  String actionToReturn = 'defer';

  String chooseAction(Map<String, dynamic> state) {
    chooseCount++;
    lastState = state;
    return actionToReturn;
  }

  void learn(...) { learnCount++; }
}
```

### 7.3 Key Test Assertions

- **Decision Point Verification**: Agent `chooseCount` should be much less than tick count
- **Learning Verification**: Agent `learnCount > 0` after full frame
- **State Structure**: State contains expected keys (`tick`, `busy`, `resolved`/`queue`)

### 7.4 Simulation Environment

```dart
// Grid-based Manhattan layout
List<List<int>> manhattanGrid;  // 0=empty, 1-4=road directions, 5=crossroad, 100=RSU

// Entity positioning
// - Cars: Distributed using farthest-first (k-center) selection
// - RSUs: Placed at predefined grid positions (tile value 100)

// Default configuration
final int CARNUM = 10;
final int RSUNUM = 4;
final int RANGE = 5;
```

---

## 8. Visualization Tools

### 8.1 ScenePainter

Real-time visualization of the simulation state:

| Element | Color/Style |
|---------|-------------|
| Normal Car | Blue circle |
| Stopped Car | Yellow circle |
| Free Car | Green circle |
| Collision | Black circle |
| RSU | Red square |
| RSU Range | Semi-transparent red circle |
| Epsilon Change | Purple stroke ring |
| RTS Signal | Green ring |
| ACK Signal | Orange ring |
| Other Signals | Purple ring |

### 8.2 Analyzer

The `Analyzer` class tracks and exports simulation metrics:

**Metrics Tracked:**
- Idle/busy slot percentages
- Soft/hard reset frequencies
- Throughput (acks/rts ratio)
- Per-node MDP progress (rewards, states, parameters)
- Epsilon change events

**Export Format:**
- JSON file with per-step data
- Text log with summary statistics
- Combined ZIP archive

### 8.3 Resumer Page

Interactive visualization tool for analyzing exported data:

**Features:**
- Load JSON/ZIP exports
- Per-node reward graphs with running average
- Parameter tracking (alpha, gamma, epsilon)
- State feature visualization
- Environment throughput metrics
- Multi-field overlay comparison

### 8.4 Configuration UI

Home page provides runtime configuration:
- Number of cars (`_carNum`)
- Number of RSUs (`_rsuNum`)
- Frames per second (`_fps`)
- MDP mode toggle (`_useMDP`)

---

## Architecture Summary

```
lib/
├── main.dart                    # App entry point
├── application/
│   └── loop.dart                # Main simulation loop
├── data/
│   ├── in_mem_repo_base.dart    # In-memory entity repository
│   └── repo_view.dart           # Filtered repository view
├── domain/
│   ├── ai/
│   │   ├── agent.dart           # Agent interface
│   │   └── q_agent.dart         # Q-Learning implementation
│   ├── entities/
│   │   ├── entity.dart          # Base entity class
│   │   ├── position.dart        # Position/direction handling
│   │   ├── classic_car.dart     # Classic car behavior
│   │   ├── classic_rsu.dart     # Classic RSU behavior
│   │   ├── mdp_car.dart         # MDP-enhanced car
│   │   └── mdp_rsu.dart         # MDP-enhanced RSU
│   ├── network/
│   │   ├── medium.dart          # Wireless medium simulation
│   │   └── signal.dart          # Signal types and data
│   └── repositories/
│       └── base_repo.dart       # Repository interface
├── presentation/
│   ├── home.dart                # Main UI and configuration
│   └── painter.dart             # Canvas rendering
└── utils/
    ├── config.dart              # Global configuration
    ├── analyzer.dart            # Metrics collection and export
    ├── measurement.dart         # Per-step measurement data
    └── resumer.dart             # Export visualization tool
```

---

## Running the Simulation

1. **Configure** simulation parameters on the home screen
2. **Start** the simulation (entities begin communicating)
3. **Observe** real-time visualization of cars, RSUs, and signals
4. **Stop** to export analyzer data (ZIP with JSON + log)
5. **Analyze** using the Resumer page to visualize learning progress

---

## Key Design Decisions

1. **Decision-Based Learning**: Agents are queried only at meaningful decision points, not every tick
2. **Immediate Outcome Learning**: Learning occurs right after outcome resolution, not at fixed intervals
3. **Congestion-Scaled Rewards**: Penalties are softened in high-congestion scenarios to encourage cooperation
4. **Adaptive Exploration**: Epsilon increases when performance degrades, enabling re-exploration
5. **Modular Architecture**: MDP entities extend classic behavior, allowing easy comparison
