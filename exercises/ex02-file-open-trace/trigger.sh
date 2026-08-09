#!/bin/bash
# trigger.sh — Exercise 2: File-open tracing
# Compiles and runs a C program that opens a specific file.
# Uses static linking to ensure bpftrace str() can read the filename.
set -eu
cd "$(dirname "$0")"

touch /tmp/ex02_marker_file

cat > /tmp/ex02_trigger.c <<'EOF'
#include <fcntl.h>
#include <unistd.h>
int main(void) {
    int fd = open("/tmp/ex02_marker_file", O_RDONLY);
    if (fd >= 0) close(fd);
    return 0;
}
EOF
gcc -O0 -static -o /tmp/ex02_trigger /tmp/ex02_trigger.c
/tmp/ex02_trigger
