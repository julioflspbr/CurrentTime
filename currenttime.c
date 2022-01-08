#include <stdio.h>
#include "currenttime.h"

static short counter = 0;

static void timerCallback(struct Time * time) {
  printf("time: %02uh %02um %02us %03ums %03uµs\n", time->hour, time->minute, time->second, time->millisecond, time->microsecond);
  if (++counter >= 3) {
    stopWatch();
  }
}

int main() {
  startWatch(UpdateRateMinute, &timerCallback);
}
