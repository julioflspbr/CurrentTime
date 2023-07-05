// The values of the UpdateRate constants are the number of processor ticks between time checks
enum UpdateRate: unsigned int {
  UpdateRateMicrosecond,
  UpdateRateMillisecond,
  UpdateRateSecond,
  UpdateRateMinute
};

// The return object from stopWatch
struct Time {
  unsigned short microsecond;
  unsigned short millisecond;
  unsigned short second;
  unsigned short minute;
  unsigned short hour;
};

typedef void (*TickCallback)(struct Time*);
extern void startWatch(enum UpdateRate, TickCallback);

extern void stopWatch(void);
