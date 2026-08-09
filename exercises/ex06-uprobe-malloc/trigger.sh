#!/bin/bash
# trigger.sh — Exercise 6: User-space uprobe on malloc
# Compiles and runs a C program that calls malloc() 100 times.
set -eu
cd "$(dirname "$0")"

cat > /tmp/ex06_trigger.c <<'EOF'
#include <stdlib.h>
int main(void) {
    for (int i = 0; i < 100; i++) {
        void *p = malloc(64);
        free(p);
    }
    return 0;
}
EOF
gcc -O0 -o /tmp/ex06_trigger /tmp/ex06_trigger.c
/tmp/ex06_trigger
