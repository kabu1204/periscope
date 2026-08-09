#!/bin/bash
# trigger.sh — Exercise 8: Syscall latency
# Compiles and runs a C program that calls openat() 20 times, producing
# syscall latency data that bpftrace can measure with enter/exit tracepoints.
# Uses static linking to ensure bpftrace str() can read filenames and
# the count is deterministic.
set -eu
cd "$(dirname "$0")"

cat > /tmp/ex08_trigger.c <<'EOF'
#include <fcntl.h>
#include <unistd.h>
int main(void) {
    for (int i = 0; i < 20; i++) {
        int fd = open("/etc/hostname", O_RDONLY);
        if (fd >= 0) close(fd);
    }
    return 0;
}
EOF
gcc -O0 -static -o /tmp/ex08_trigger /tmp/ex08_trigger.c
/tmp/ex08_trigger
