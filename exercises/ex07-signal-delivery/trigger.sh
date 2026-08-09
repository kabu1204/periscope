#!/bin/bash
# trigger.sh — Exercise 7: Signal delivery tracing
# Compiles and runs a C program that sends itself SIGUSR1 (signal 10) 5 times.
set -eu
cd "$(dirname "$0")"

cat > /tmp/ex07_trigger.c <<'EOF'
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>

static volatile sig_atomic_t count = 0;

void handler(int sig) {
    count++;
}

int main(void) {
    struct sigaction sa;
    sa.sa_handler = handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGUSR1, &sa, NULL);

    for (int i = 0; i < 5; i++) {
        raise(SIGUSR1);
    }
    return 0;
}
EOF
gcc -O0 -o /tmp/ex07_trigger /tmp/ex07_trigger.c
/tmp/ex07_trigger
