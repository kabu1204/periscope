#!/usr/bin/env bash
# ci_report.sh — one-shot verification of project state.
#
# Purpose: give the user a single command that answers "is the project
# actually where STATE.md claims it is?" without reading any code.
#
# Maintenance rule (binding): each milestone MUST append its verification
# section below before it can be marked complete (see AGENTS.md, DoD).

set -u
PASS=0
FAIL=0
declare -a RESULTS

check() { # check <name> <command...>
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS+1)); RESULTS+=("PASS  $name")
    else
        FAIL=$((FAIL+1)); RESULTS+=("FAIL  $name")
    fi
}

# ---------------------------------------------------------------- M0 section
m0_checks() {
    check "M0: ENVIRONMENT.md has no TBD placeholders" \
        bash -c '! grep -q TBD ENVIRONMENT.md'
    check "M0: Prometheus healthy" \
        curl -sf http://localhost:9090/-/healthy
    check "M0: Grafana healthy" \
        curl -sf http://localhost:3000/api/health
    check "M0: node_exporter up" \
        curl -sf http://localhost:9100/metrics
}

# ---------------------------------------------------------------- M1 section
m1_checks() {
    for v in exercises/*/verify.sh; do
        [ -e "$v" ] || continue
        check "M1: $v" bash "$v"
    done
}

# ---------------------------------------------------------------- M2 section
m2_checks() {
    check "M2: biolat oracle comparison" bash scripts/verify_m2.sh
}

# ---------------------------------------------------------------- M3 section
m3_checks() {
    check "M3: runqlat/offcpu injection scenarios" bash scripts/verify_m3.sh
}

# ---------------------------------------------------------------- M4 section
m4_checks() {
    check "M4: case-study smoke" bash scripts/verify_m4.sh
}

main() {
    local sections=("${@:-m0}")
    for s in "${sections[@]}"; do
        case "$s" in
            m0|m1|m2|m3|m4) "${s}_checks" ;;
            all) m0_checks; m1_checks; m2_checks; m3_checks; m4_checks ;;
            *) echo "unknown section: $s" >&2; exit 2 ;;
        esac
    done

    echo "=============================="
    printf '%s\n' "${RESULTS[@]:-no checks ran}"
    echo "=============================="
    echo "pass: $PASS  fail: $FAIL"
    [ "$FAIL" -eq 0 ]
}

main "$@"
