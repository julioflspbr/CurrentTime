.data
  .set inTime           , 0x00      # struct timeval, local variable offset from stack pointer
  .set outTime          , 0x10      # struct Time, local variable offset from stack pointer
  .set waitCount        , 0x1a      # how many iterations to pause, local variable offset from stack pointer
  .set getTimeOfDay     , 0x2000074 # system call number

  .set TimevalSec       , 0x00      # time_t tv_sec, struct timeval, offset from stack pointer
  .set TimevalUSec      , 0x08      # suseconds_t tv_usec, struct timeval, offset from stack pointer

  .set TimeMicrosecond  , 0x10      # Time struct variable offset from stack pointer
  .set TimeMillisecond  , 0x12      # Time struct variable offset from stack pointer
  .set TimeSecond       , 0x14      # Time struct variable offset from stack pointer
  .set TimeMinute       , 0x16      # Time struct variable offset from stack pointer
  .set TimeHour         , 0x18      # Time struct variable offset from stack pointer

.bss
  .lcomm tickCallback, 8

.text
  .global _startWatch
  .global _stopWatch

########################################################################################################################
########################################################################################################################

# void startWatch(enum UpdateRate, TickCallback)
_startWatch:
  push  %rbp                        # store the current base pointer to recover it later on
  mov   %rsp, %rbp                  # base and top of stack at the same place, base stays static and stack pointer moves
  sub   $0x20, %rsp                 # allocate stack space for local variables (plus padding for alignment)

  mov   %edi, waitCount(%rsp)       # first parameter, store the number of iterations to wait for
  mov   %rsi, tickCallback(%rip)    # second parameter, set the callback that watches time updates
  xor   %rcx, %rcx                  # our repeat number is small, so clear out all 64-bits of the counter

runLoop:
# get the time from the system
  mov   $getTimeOfDay, %rax         # syscall code for system function getTimeOfDay(...)
  lea   inTime(%rsp), %rdi          # first parameter, struct timeval *tp = inTime
  xor   %rsi, %rsi                  # second parameter, struct timezone *tzp = nullptr
  xor   %rdx, %rdx                  # third parameter, uint64_t *mach_absolute_time = nullptr
  syscall                           # call getTimeOfDay and fill in inTime

# find the microseconds and the milliseconds fields
  xor   %rdx, %rdx                  # zero out high quadword for division
  movq  TimevalUSec(%rsp), %rax     # fill in low quadword for division
  mov   $1000, %r8                  # prepare division by 1000
  divq  %r8                         # divide microseconds by 1000 (we only want the last three digits)
  mov   %dx, TimeMicrosecond(%rsp)  # get the remainder as the microseconds field
  mov   %ax, TimeMillisecond(%rsp)  # get the quotient as the milliseconds field

# find the seconds field
  xor   %rdx, %rdx                  # zero out high quadword for division
  movq  TimevalSec(%rsp), %rax      # fill in low quadword for division
  mov   $60, %r8                    # prepare division by 60 seconds
  divq  %r8                         # divide microseconds by 60
  mov   %dx, TimeSecond(%rsp)       # get the ramainder as the seconds field

# find the minutes field
  xor   %rdx, %rdx                  # zero out high quadword for division
  mov   $60, %r8                    # prepare division by 60 minutes
  divq  %r8                         # use result from the seconds operation, divide it by 60 minutes in an hour
  mov   %dx, TimeMinute(%rsp)       # get the remainder as the minutes field

# find the hours field
  xor   %rdx, %rdx                  # zero out high quadword for division
  mov   $24, %r8                    # prepare division by 24 minutes
  divq  %r8                         # use result from the seconds operation, divide it by 24 hours in a day
  mov   %dx, TimeHour(%rsp)         # get the remainder as the hours field

# call tickCallback
  lea   outTime(%rsp), %rdi         # tickCallback's only parameter, pointer to struct Time
  call  *tickCallback(%rip)

# repeats nop for arg0 processor ticks, to avoid overflow UI with billions of updates per second
  mov   waitCount(%rsp), %ecx       # set the amount of idle processor ticks (comes from the 1st method parameter)
sleep:
  pause                             # keep processor idle
  loop  sleep

# finish execution if listener is null
  cmpq  $0, tickCallback(%rip)      # if tick callback pointer is null
  je    returnStopWatch             # then exit run loop, that is, unsubscribe

# do it all over again
  jmp   runLoop                     # keep timer run loop up

returnStopWatch:
  mov   %rbp, %rsp                  # move the stack pointer back to where it was before the call to this function
  pop   %rbp                        # set the base pointer back to whatever it was before the call to this function
  ret

########################################################################################################################
########################################################################################################################

# void stopWatch()
_stopWatch:
  movq  $0, tickCallback(%rip)      # set tick callback pointer to null, in order to unsubscribe to the time changes
  ret
