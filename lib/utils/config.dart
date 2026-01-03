// GENERAL
final int MAX_EPISODES = 1000;
final int SUBFRAMES = 1000;
final int FPS = 10;
final int RANGE = 5;
final int PROTOCOL = 0; // 0: ClassicProtocol 1: NovelProtocol

final int CARNUM = 10;
final int RSUNUM = 4;

// MDP MODE
final bool USE_MDP = true; // Set to false to use classic Car/RSU, true for MDP agents

final int DIFS = 40;
final int SIFS = 10;
final int BROADCAST = 100;
final int RESETTIME = 150; // this has to be > NAVTIME and > MAX BACKOFF TIME and > broadcast duration

final int STARTING_EXPONENT = 0;
final int BACKOFF_SLOT_TIME = 10;
final int MAX_BACKOFF_EXPONENT = 5;

final int RTSDURATION = 1;
final int CTSDURATION = 5;
final int QUERYDURATION = 7;
final int RESPONSEDURATION = 7;
final int ACKDURATION = 5;

final int NAVTIME = RTSDURATION + CTSDURATION + QUERYDURATION + RESPONSEDURATION + ACKDURATION + SIFS * 4;
final int NAVTIMECTS = CTSDURATION + QUERYDURATION + RESPONSEDURATION + ACKDURATION + SIFS * 3;
final int NAVTIMEQUERY = QUERYDURATION + RESPONSEDURATION + ACKDURATION + SIFS * 2;
final int NAVTIMERESPONSE = RESPONSEDURATION + ACKDURATION + SIFS;
final int NAVTIMEACK = ACKDURATION;

final int PRUNECARS = SUBFRAMES;

// MDP Training
final int TRAINING_INTERVAL = 1; // Number of completed steps (SUBFRAMES) before updating weights

// Gating for frame-based gamma: desired gamma across the whole frame
final double GAMMA_FRAME = 0.99;

// Epsilon adaptation via window average comparison
// Epsilon is increased when avg of last EPSILON_WINDOW frames < avg of EPSILON_WINDOW frames before it
final int EPSILON_WINDOW = 100; // number of frames per comparison window

final double EPSILON_INC = 0.5; // amount to increase epsilon upon degradation
final double EPSILON_MAX = 1.0; // max epsilon
final double EPSILON_MIN = 0.0; // min epsilon
// Epsilon cooldown and decay
final int EPSILON_COOLDOWN_EPISODES = EPSILON_WINDOW * 2; // default cooldown in episodes
final double EPSILON_DECAY_FACTOR = 0.92; // multiplicative passive decay per episode
final double EPSILON_BASELINE = 0.05; // baseline epsilon not to drop below gradually

// Toggle adaptive epsilon behaviour. Set to `false` to disable Analyzer-driven
// epsilon decay/increase logic (useful for deterministic evaluation or
// experiments where epsilon should be fixed externally).
final bool ENABLE_EPSILON_ADAPT = false;

// Separate toggle for passive epsilon decay (multiplicative per-episode).
// When `false` passive decay is disabled but adaptive increases can still
// be enabled via `ENABLE_EPSILON_ADAPT`.
final bool ENABLE_EPSILON_DECAY = false;

// Default epsilon value to use when (a) instantiating agents for experiments
// or (b) overriding during deterministic runs.
final double DEFAULT_EPSILON = 0.4;


/*
//////////////////
/// FUNCTIONING PARAMETERS
//////////////////

// GENERAL
final int SUBFRAMES = 400;
final int FPS = 10;
final int RANGE = 5;
final int PROTOCOL = 0; // 0: ClassicProtocol 1: NovelProtocol

final int CARNUM = 3;
final int RSUNUM = 4;

// MDP MODE
final bool USE_MDP = false; // Set to false to use classic Car/RSU, true for MDP agents

final int DIFS = 40;
final int SIFS = 10;
final int BROADCAST = 100;
final int RESETTIME = 150; // this has to be > NAVTIME and > MAX BACKOFF TIME and > broadcast duration

final int STARTING_EXPONENT = 0;
final int BACKOFF_SLOT_TIME = 10;
final int MAX_BACKOFF_EXPONENT = 5;

final int RTSDURATION = 1;
final int CTSDURATION = 5;
final int QUERYDURATION = 7;
final int RESPONSEDURATION = 7;
final int ACKDURATION = 5;

final int NAVTIME = RTSDURATION + CTSDURATION + QUERYDURATION + RESPONSEDURATION + ACKDURATION + SIFS * 4;
final int NAVTIMECTS = CTSDURATION + QUERYDURATION + RESPONSEDURATION + ACKDURATION + SIFS * 3;
final int NAVTIMEQUERY = QUERYDURATION + RESPONSEDURATION + ACKDURATION + SIFS * 2;
final int NAVTIMERESPONSE = RESPONSEDURATION + ACKDURATION + SIFS;
final int NAVTIMEACK = ACKDURATION;

final int PRUNECARS = SUBFRAMES;

*/