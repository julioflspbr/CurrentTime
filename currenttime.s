.data
  # enum UpdateRate
  .set UpdateRateMicrosecond  , 0
  .set UpdateRateMillisecond  , 1
  .set UpdateRateSecond       , 2
  .set UpdateRateMinute       , 3
  # end enum UpdateRate

  .set inTime           , 0x00        # struct timeval, local variable offset from stack pointer
  .set outTime          , 0x10        # struct Time, local variable offset from stack pointer
  .set getTimeOfDay     , 0x2000074   # system call number

  .set TimevalSec       , 0x00        # time_t tv_sec, struct timeval, offset from stack pointer
  .set TimevalUSec      , 0x08        # suseconds_t tv_usec, struct timeval, offset from stack pointer

  .set TimeMicrosecond  , 0x10        # Time struct variable offset from stack pointer
  .set TimeMillisecond  , 0x12        # Time struct variable offset from stack pointer
  .set TimeSecond       , 0x14        # Time struct variable offset from stack pointer
  .set TimeMinute       , 0x16        # Time struct variable offset from stack pointer
  .set TimeHour         , 0x18        # Time struct variable offset from stack pointer

.bss
  .lcomm tickCallback, 8

.text
  .global _startWatch
  .global _stopWatch

########################################################################################################################
########################################################################################################################

# void startWatch(enum UpdateRate, TickCallback)
_startWatch:
  push  %r12                          # store update rate (an UpdateRate enum value)
  push  %r13                          # store current value of the UpdateRate time unit
  push  %r14                          # store previous value of the UpdateRate time unit
  push  $0                            # dummy, stack alignment
  push  %rbp                          # store the current base pointer to recover it later on
  mov   %rsp, %rbp                    # base and top of stack at the same place, base stays static and stack pointer moves
  sub   $0x20, %rsp                   # allocate stack space for local variables (plus padding for alignment)

  mov   %edi, %r12d                   # first parameter, define the UI update rate (enum UpdateRate)
  mov   %rsi, tickCallback(%rip)      # second parameter, set the callback that watches time updates
  xor   %rcx, %rcx                    # our repeat number is small, so clear out all 64-bits of the counter

runLoop:
# put the processor in a waiting low state (system nanosleep)

# get the time from the system
  mov   $getTimeOfDay, %rax           # syscall code for system function getTimeOfDay(...)
  lea   inTime(%rsp), %rdi            # first parameter, struct timeval *tp = inTime
  xor   %rsi, %rsi                    # second parameter, struct timezone *tzp = nullptr
  xor   %rdx, %rdx                    # third parameter, uint64_t *mach_absolute_time = nullptr
  syscall                             # call getTimeOfDay and fill in inTime

# find the microseconds
  xor   %rdx, %rdx                    # zero out high quadword for division
  movq  TimevalUSec(%rsp), %rax       # fill in low quadword for division
  mov   $1000, %r8                    # prepare division by 1000
  divq  %r8                           # divide microseconds by 1000 (we only want the last three digits)
  mov   %dx, TimeMicrosecond(%rsp)    # get the remainder as the microseconds field
  cmp   $UpdateRateMicrosecond, %r12w # if user wants the UI to be updated each microsecond
  cmove %dx, %r13w                    # then move microsecond to comparison register

# in the operation to find microsecond, millisecond is already found, so no further operation is done
  mov   %ax, TimeMillisecond(%rsp)    # get the quotient as the milliseconds field
  cmp   $UpdateRateMillisecond, %r12w # if user wants the UI to be updated each millisecond
  cmove %ax, %r13w                    # then move millisecond to comparison register

# find the seconds field
  xor   %rdx, %rdx                    # zero out high quadword for division
  movq  TimevalSec(%rsp), %rax        # fill in low quadword for division
  mov   $60, %r8                      # prepare division by 60 seconds
  divq  %r8                           # divide microseconds by 60
  mov   %dx, TimeSecond(%rsp)         # get the ramainder as the seconds field
  cmp   $UpdateRateSecond, %r12w      # if user wants the UI to be updated each second
  cmove %dx, %r13w                    # then move second to comparison register

# find the minutes field
  xor   %rdx, %rdx                    # zero out high quadword for division
  mov   $60, %r8                      # prepare division by 60 minutes
  divq  %r8                           # use result from the seconds operation, divide it by 60 minutes in an hour
  mov   %dx, TimeMinute(%rsp)         # get the remainder as the minutes field
  cmp   $UpdateRateMinute, %r12w      # if user wants the UI to be updated each minute
  cmove %dx, %r13w                    # then move minute to comparison register

# find the hours field
  xor   %rdx, %rdx                    # zero out high quadword for division
  mov   $24, %r8                      # prepare division by 24 minutes
  divq  %r8                           # use result from the seconds operation, divide it by 24 hours in a day
  mov   %dx, TimeHour(%rsp)           # get the remainder as the hours field

# update UI if conditions are met
  cmp   %r13, %r14                    # compare current (r13) and prevous (r14)
  mov   %r13, %r14                    # make current to be the previous in the next iteration of the run loop
  je    haltCheck                     # skip the UI update if current and previous are the same (value hasn't changed)

# update UI by calling tickCallback
  lea   outTime(%rsp), %rdi           # tickCallback's only parameter, pointer to struct Time
  call  *tickCallback(%rip)

# finish execution if listener is null
haltCheck:
  cmpq  $0, tickCallback(%rip)        # if tick callback pointer is null
  je    returnStopWatch               # then exit run loop, that is, unsubscribe

# offload the processor
  pause                               # offload the processor and hint the system that it is a spin-wait loop
  cmp   $UpdateRateSecond, %r12w      # check if less than a second
  jb    runLoop                       # if so, don't usleep, in order to achieve high precision

pauseForSecond:
  # no need to cmp because it was executed in the previous routine
  jne   pauseForMinute                # if not comparing to a minute, jump to pause for hour precision
  mov   $1000000, %rdi                # amount of microseconds in a minute
  call  _usleep                       # sleep for the defined time
  jmp   runLoop                       # back to the start of the run loop

pauseForMinute:
  mov   $60000000, %rdi               # amount of microseconds in a minute
  call  _usleep                       # sleep for the defined time
  jmp   runLoop                       # back to the start of the run loop

returnStopWatch:
  mov   %rbp, %rsp                    # move the stack pointer back to where it was before the call to this function
  pop   %rbp                          # set the base pointer back to whatever it was before the call to this function
  pop   %r14                          # dummy, stack alignment
  pop   %r14                          # restore callee-saved register
  pop   %r13                          # restore callee-saved register
  pop   %r12                          # restore callee-saved register
  ret

########################################################################################################################
########################################################################################################################

# void stopWatch()
_stopWatch:
  movq  $0, tickCallback(%rip)        # set tick callback pointer to null, in order to unsubscribe to the time changes
  ret
