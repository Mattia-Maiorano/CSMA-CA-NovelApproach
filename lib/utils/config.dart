import 'package:daemon/utils/slope_utils.dart' as slope_utils;


// GENERAL
final int SUBFRAMES = 400;
final int FPS = 10;
final int RANGE = 5;
final int PROTOCOL = 0; // 0: ClassicProtocol 1: NovelProtocol

final int CARNUM = 6;
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

// Reward gradient detector and epsilon adaptation
// Number of most recent episodes to consider when computing the linear
// reward gradient slope. The Analyzer uses a linear regression across the
// last REWARD_GRAD_WINDOW points and triggers if the slope is below the
// configured threshold.
final int REWARD_GRAD_WINDOW = 100; // episodes used to compute linear slope
final double REWARD_GRAD_SENSITIVITY = 1.0; // multiplier applied to threshold

// Set the target drop you'd like the detector to pick up by default
final double TARGET_DROP_START = 0.8;
final double TARGET_DROP_END = 0.7;
final int TARGET_DROP_WINDOW = REWARD_GRAD_WINDOW;
final double TARGET_DROP_SENSITIVITY = REWARD_GRAD_SENSITIVITY;

// If you don't want the threshold to be computed automatically, set
// COMPUTE_REWARD_GRAD_THRESHOLD=false; otherwise we'll compute a recommended
// threshold based on `TARGET_DROP_START` -> `TARGET_DROP_END` and `TARGET_DROP_WINDOW`.
final bool COMPUTE_REWARD_GRAD_THRESHOLD = true;

final double REWARD_GRAD_THRESHOLD = COMPUTE_REWARD_GRAD_THRESHOLD
	? slope_utils.recommendThresholdForDrop(TARGET_DROP_START, TARGET_DROP_END,
		window: TARGET_DROP_WINDOW, sensitivity: TARGET_DROP_SENSITIVITY)
	: -0.1; // slope threshold (y per x unit) below which epsilon is increased
/*
	Example guidance: To detect a drop from 0.8 -> 0.7 (delta -0.1), compute slope
	S ≈ (end - start) / (W - 1) = -0.1 / (W - 1), where W = REWARD_GRAD_WINDOW.
	If computed S < (REWARD_GRAD_THRESHOLD * REWARD_GRAD_SENSITIVITY) the Analyzer
	will trigger an epsilon increase.

	Examples (approx):
	- W = 2  -> S ≈ -0.1000 → set REWARD_GRAD_THRESHOLD ≈ -0.09 (detect)
	- W = 5  -> S ≈ -0.0250 → set REWARD_GRAD_THRESHOLD ≈ -0.02 (detect)
	- W = 10 -> S ≈ -0.01111 -> set REWARD_GRAD_THRESHOLD ≈ -0.01 (detect)
	- W = 100-> S ≈ -0.00101 -> set REWARD_GRAD_THRESHOLD ≈ -0.001 (detect)

	Sensitivity applies multiplicatively:
		effectiveThreshold = REWARD_GRAD_THRESHOLD * REWARD_GRAD_SENSITIVITY
	Lower sensitivity (<1.0) makes detection easier (threshold closer to 0),
	higher sensitivity (>1.0) makes it stricter (threshold more negative).

	Practical rule: choose W according to how quickly you want to detect a drop,
	then set threshold slightly less negative than S (e.g., S * 0.9) so it triggers
	reliably for that size of decline.
*/
// (moved; declared above near window to define defaults before use)
final double EPSILON_INC = 0.5; // amount to increase epsilon upon degradation
final double EPSILON_MAX = 1.0; // max epsilon
final double EPSILON_MIN = 0.0; // min epsilon
// Epsilon cooldown and decay
final int EPSILON_COOLDOWN_EPISODES = REWARD_GRAD_WINDOW; // default cooldown in episodes
final double EPSILON_DECAY_FACTOR = 0.95; // multiplicative passive decay per episode
final double EPSILON_BASELINE = 0.05; // baseline epsilon not to drop below gradually


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