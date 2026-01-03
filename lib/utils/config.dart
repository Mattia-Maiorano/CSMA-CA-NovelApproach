/// ============================================================================
/// Simulation Configuration Constants
/// ============================================================================
/// Central configuration file for all simulation parameters.
/// Adjust these values to change simulation behavior.
/// ============================================================================

// ignore_for_file: dangling_library_doc_comments, non_constant_identifier_names

// ─────────────────────────────────────────────────────────────────────────────
// General Simulation Parameters
// ─────────────────────────────────────────────────────────────────────────────
final int MAX_EPISODES = 1000; // Maximum frames before auto-stop
final int SUBFRAMES = 1000; // Ticks per frame (fine-grained timing)
final int FPS = 10; // Frames per second (visualization speed)
final int RANGE = 5; // Default transmission range in tiles
final int PROTOCOL = 0; // Protocol variant (0: Classic CSMA/CA)

final int CARNUM = 10; // Default number of cars
final int RSUNUM = 4; // Default number of RSUs

// ─────────────────────────────────────────────────────────────────────────────
// MDP Mode Configuration
// ─────────────────────────────────────────────────────────────────────────────
final bool USE_MDP = true; // true: Use RL agents, false: Classic protocol

// ─────────────────────────────────────────────────────────────────────────────
// MAC Protocol Timing (in ticks)
// ─────────────────────────────────────────────────────────────────────────────
final int DIFS = 40; // Distributed Inter-Frame Space
final int SIFS = 10; // Short Inter-Frame Space
final int BROADCAST = 100; // Interval between RTS broadcasts
final int RESETTIME = 150; // Timeout before reset (must be > NAVTIME)

// ─────────────────────────────────────────────────────────────────────────────
// Backoff Parameters
// ─────────────────────────────────────────────────────────────────────────────
final int STARTING_EXPONENT = 0; // Initial backoff exponent
final int BACKOFF_SLOT_TIME = 10; // Duration of one backoff slot
final int MAX_BACKOFF_EXPONENT = 5; // Maximum backoff exponent (2^5 = 32 slots)

// ─────────────────────────────────────────────────────────────────────────────
// Signal Durations (in ticks)
// ─────────────────────────────────────────────────────────────────────────────
final int RTSDURATION = 1;
final int CTSDURATION = 5;
final int QUERYDURATION = 7;
final int RESPONSEDURATION = 7;
final int ACKDURATION = 5;

// ─────────────────────────────────────────────────────────────────────────────
// NAV (Network Allocation Vector) Durations
// ─────────────────────────────────────────────────────────────────────────────
// These define how long entities should defer after hearing a signal
final int NAVTIME =
    RTSDURATION +
    CTSDURATION +
    QUERYDURATION +
    RESPONSEDURATION +
    ACKDURATION +
    SIFS * 4;
final int NAVTIMECTS =
    CTSDURATION + QUERYDURATION + RESPONSEDURATION + ACKDURATION + SIFS * 3;
final int NAVTIMEQUERY =
    QUERYDURATION + RESPONSEDURATION + ACKDURATION + SIFS * 2;
final int NAVTIMERESPONSE = RESPONSEDURATION + ACKDURATION + SIFS;
final int NAVTIMEACK = ACKDURATION;

// ─────────────────────────────────────────────────────────────────────────────
// Knowledge Pruning
// ─────────────────────────────────────────────────────────────────────────────
final int PRUNECARS = SUBFRAMES; // Age before forgetting a car's position

// ─────────────────────────────────────────────────────────────────────────────
// MDP Training Parameters
// ─────────────────────────────────────────────────────────────────────────────
final int TRAINING_INTERVAL = 1; // Steps between weight updates
final double GAMMA_FRAME = 0.99; // Frame-level discount factor

// Epsilon Adaptation (exploration rate adjustment)
final int EPSILON_WINDOW = 100; // Frames per comparison window
final double EPSILON_INC = 0.5; // Increase amount upon degradation
final double EPSILON_MAX = 1.0; // Maximum epsilon
final double EPSILON_MIN = 0.0; // Minimum epsilon
final int EPSILON_COOLDOWN_EPISODES = EPSILON_WINDOW * 2; // Cooldown period
final double EPSILON_DECAY_FACTOR = 0.92; // Passive decay per episode
final double EPSILON_BASELINE = 0.05; // Minimum epsilon floor

// Toggle switches for adaptive behavior
final bool ENABLE_EPSILON_ADAPT =
    false; // Enable gradient-based epsilon adjustment
final bool ENABLE_EPSILON_DECAY = false; // Enable passive epsilon decay
final double DEFAULT_EPSILON = 0.4;         // Default starting epsilon