// GENERAL
final int SUBFRAMES = 2000;
final int FPS = 10;
final int RANGE = 7;
final int PROTOCOL = 0; // 0: ClassicProtocol 1: NovelProtocol

final int CARNUM = 10;
final int RSUNUM = 4;

// MDP MODE
final bool USE_MDP = true; // Set to false to use classic Car/RSU, true for MDP agents

final int DIFS = 40;
final int SIFS = 10;
final int BROADCAST = 200;
final int RESETTIME = 500; // this has to be > NAVTIME and > MAX BACKOFF TIME and > broadcast duration

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
final int TRAINING_INTERVAL = 2; // Number of completed steps (SUBFRAMES) before updating weights