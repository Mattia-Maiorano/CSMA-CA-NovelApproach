Roadside Assistance Simulation

A Flutter-based simulation of **Vehicle-to-Everything (V2X) communication** between cars and Roadside Units (RSUs), implementing a CSMA/CA-like MAC protocol with optional **Reinforcement Learning** agents.

## 🎯 What is this?

This project simulates a road network where:
- **Cars** drive on a grid and periodically request assistance from RSUs
- **RSUs** (Roadside Units) respond to cars with collision avoidance decisions ("stop" or "free to go")
- Communication follows a **CSMA/CA-inspired protocol** with RTS/CTS handshake
- Optionally, **Q-Learning agents** can control when nodes transmit (MDP mode)

The simulation visualizes the network in real-time and exports detailed metrics for analysis.

---

## 🖼️ Features

| Feature | Description |
|---------|-------------|
| **Visual Simulation** | Real-time grid visualization of cars, RSUs, and wireless signals |
| **CSMA/CA Protocol** | RTS→CTS→Query→Response→ACK handshake with NAV and backoff |
| **MDP Mode** | Q-Learning agents that learn when to transmit or defer |
| **Configurable** | Adjust number of cars, RSUs, speed, and learning parameters |
| **Metrics Export** | JSON + log export with detailed per-tick data |
| **Resumer Tool** | Built-in plotting tool to analyze learning curves |

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.0+)
- Dart SDK (included with Flutter)

### Run the Simulation

```bash
# Clone the repository
git clone <repository-url>
cd Daemon

# Get dependencies
flutter pub get

# Run on your preferred platform
flutter run -d macos    # macOS
flutter run -d chrome   # Web browser
flutter run -d windows  # Windows
```

### Quick Start Guide

1. **Launch the app** → You'll see a configuration panel
2. **Adjust parameters**:
   - Number of cars (1-20)
   - Number of RSUs (1-4)
   - FPS (simulation speed)
   - Toggle MDP mode on/off
3. **Click "START SIMULATION"**
4. **Watch the visualization**:
   - 🔵 Blue circles = cars moving
   - 🟡 Yellow = stopped cars
   - 🟢 Green = cars free to move
   - 🔴 Red squares = RSUs (with range circles)
   - Colored rings = active signals
5. **Click "STOP"** to end and export results

---

## 📁 Project Structure

```
lib/
├── main.dart                 # App entry point
├── application/
│   └── loop.dart             # Main simulation loop
├── presentation/
│   ├── home.dart             # UI and configuration
│   └── painter.dart          # Canvas rendering
├── domain/
│   ├── entities/             # Car, RSU, MDP variants
│   ├── network/              # Signal and Medium (channel)
│   ├── ai/                   # Q-Learning agent
│   └── repositories/         # Data layer interface
├── data/                     # In-memory repositories
└── utils/
    ├── config.dart           # All configuration constants
    ├── analyzer.dart         # Metrics collection & export
    ├── resumer.dart          # Results visualization
    └── measurement.dart      # Per-tick metrics
```

---

## ⚙️ Configuration

All simulation parameters are in [`lib/utils/config.dart`](lib/utils/config.dart):

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MAX_EPISODES` | 1000 | Maximum frames before auto-stop |
| `SUBFRAMES` | 1000 | Ticks per frame (timing granularity) |
| `CARNUM` | 10 | Default number of vehicles |
| `RSUNUM` | 4 | Default number of RSUs |
| `USE_MDP` | true | Enable RL agents by default |

### Protocol Timing

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DIFS` | 40 | Distributed Inter-Frame Space |
| `SIFS` | 10 | Short Inter-Frame Space |
| `BROADCAST` | 100 | Interval between RTS broadcasts |
| `MAX_BACKOFF_EXPONENT` | 5 | Maximum backoff window (2^5 = 32 slots) |

### Learning Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DEFAULT_EPSILON` | 0.4 | Exploration rate for Q-Learning |
| `GAMMA_FRAME` | 0.99 | Discount factor |
| `ENABLE_EPSILON_ADAPT` | false | Auto-adjust exploration rate |

---

## 📊 Analyzing Results

### Export Location
- **Desktop/Linux**: `~/Desktop/analyzer_exports/`
- **Web**: Downloaded as ZIP file

### Export Contents
- `analyzer_log_*.txt` - Human-readable summary
- `analyzer_mdp_*.json` - Per-tick data for all nodes

### Using the Resumer

1. Click the 📊 (chart) button in the app
2. Load an exported JSON or ZIP file
3. Select a node to view its learning progress
4. Toggle fields to overlay on the chart

---

## 🔬 Two Operating Modes

### Classic Mode (`USE_MDP = false`)
Standard CSMA/CA protocol:
- Cars broadcast RTS at fixed intervals
- Backoff and NAV follow standard rules
- No learning - deterministic behavior

### MDP Mode (`USE_MDP = true`)
Reinforcement Learning agents:
- **Car Agent**: Chooses `startComm` (transmit now) or `defer` (wait)
- **RSU Agent**: Chooses `ready` (listen) or `defer` (wait)
- Learns from rewards based on successful communications
- Uses Q-Learning with epsilon-greedy exploration

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Simulation Loop                         │
│                   (loop.dart - FPS timer)                   │
└────────────────────────────┬────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
    ┌─────────┐        ┌─────────┐        ┌─────────┐
    │  Cars   │        │  RSUs   │        │ Medium  │
    │(Entities)│        │(Entities)│        │(Channel)│
    └────┬────┘        └────┬────┘        └────┬────┘
         │                   │                   │
         │    ◄──── Signals ────►                │
         │                   │                   │
    ┌────┴────┐        ┌────┴────┐              │
    │Q-Agent? │        │Q-Agent? │              │
    │ (MDP)   │        │ (MDP)   │              │
    └─────────┘        └─────────┘              │
                                                │
                    ┌───────────────────────────┘
                    ▼
              ┌──────────┐
              │ Analyzer │ ──► Export (JSON/ZIP)
              └──────────┘
```

---

## 📚 Documentation

For detailed technical documentation (suitable for academic reports), see:
- [`lib/README.md`](lib/README.md) - Comprehensive protocol and MDP methodology documentation

---

## 🎓 Academic Use

This project is designed for research and education in:
- Wireless MAC protocols (CSMA/CA, RTS/CTS)
- Reinforcement Learning (Q-Learning, MDP)
- Vehicle-to-Everything (V2X) communication
- Multi-agent systems

### Citing Key Files
- Protocol state machine: `lib/domain/entities/entity.dart`
- Q-Learning agent: `lib/domain/ai/q_agent.dart`
- MDP integration: `lib/domain/entities/mdp_car.dart`, `mdp_rsu.dart`
- Metrics: `lib/utils/analyzer.dart`

---

## 📝 License

This project is part of the Autonomous Networking course at university.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

---

*Built with Flutter 💙*
