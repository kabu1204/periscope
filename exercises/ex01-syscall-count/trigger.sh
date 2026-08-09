#!/bin/bash
# trigger.sh — Exercise 1: Syscall counting
# Compiles and runs a C program that calls openat() exactly 10 times.
# Uses static linking to avoid ld.so openat calls that would inflate the count.
set -eu
cd "$(dirname "$0")"

cat > /tmp/ex01_trigger.c <<'EOF'
#include <fcntl.h>
#include <unistd.h>
int main(void) {
    for (int i = 0; i < 10; i++) {
        int fd = open("/etc/hostname", O_RDONLY);
        if (fd >= 0) close(fd);
    }
    return 0;
}
EOF
gcc -O0 -static -o /tmp/ex01_trigger /tmp/ex01_trigger.c
/tmp/ex01_trigger
