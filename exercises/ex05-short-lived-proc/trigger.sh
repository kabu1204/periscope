#!/bin/bash
# trigger.sh — Exercise 5: Short-lived process capture
# Spawns a uniquely-named short-lived process that exits almost immediately.
# Binary name is ≤16 chars to fit in kernel comm field.
set -eu
cd "$(dirname "$0")"

# Create a short-lived binary with a name that fits the 16-char comm limit
cat > /tmp/ex05_slp.c <<'EOF'
int main(void) { return 0; }
EOF
gcc -O0 -o /tmp/ex05_slp /tmp/ex05_slp.c

# Run it 3 times — each execution is nearly instantaneous
for i in $(seq 1 3); do
    /tmp/ex05_slp
done
