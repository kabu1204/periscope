# M2 Coding Standards

> Engineering standards for all custom eBPF tools in this project. These rules apply to every crate under `tools/`.

## Formatting

- **Tool**: `cargo fmt` (default rustfmt style).
- **Check**: `cargo fmt --check` (used in `ci_report.sh` M2 section).
- **Project deviations**: none. If a deviation is needed, record it in a `rustfmt.toml` at the crate root with a justification comment.

## Linting

- **Tool**: `cargo clippy -- -D warnings` (warnings treated as errors).
- **Check**: `ci_report.sh` M2 section runs clippy and fails on any warning.
- **Allowed lints**: none. If a lint must be allowed, add `#[allow(clippy::...)]` with a comment explaining why.

## Build and Test Routine

- **Build**: `cargo build --release` — all tools must build in release mode.
- **Test**: `cargo test` — run unit tests where unit-testable logic exists.
- **CI order**: `cargo fmt --check` → `cargo clippy -- -D warnings` → `cargo build --release` → oracle verification.

## Error Handling

- **Tool errors**: use `anyhow::Result` for the `main` function and any fallible operation that doesn't need structured error types.
- **Library errors**: use `thiserror` for custom error types if a crate exposes a library API (not applicable for CLI-only tools).
- **Error propagation**: use `?` operator. Do not unwrap in production code paths; panics on unexpected conditions are acceptable only in `expect()` calls with a descriptive message.
- **BPF errors**: if the BPF object fails to load or attach, print a diagnostic message and exit with a non-zero status.

## Logging

- **CLI tools**: use `eprintln!` for diagnostic messages (e.g., "Tracing... Hit Ctrl-C to end.") and `println!` for data output (histograms, counts). This keeps data output separable from diagnostic noise when piped.
- **Log levels**: not used for simple CLI tools. If a tool grows complex enough to need log levels, add the `log` crate + `env_logger`.

## Reproducibility

Per `AGENTS.md`:
- **Fixed parameters**: all benchmark scripts use fixed parameters (no random seeds, no environment-dependent defaults).
- **≥3 runs**: each configuration in a verification script is run at least 3 times. The verification script reports all runs, not a single value.
- **Distributions**: scripts report distributions (histograms or min/median/max), not single point values.

## BPF Code Conventions

- **BPF programs**: written in C, compiled with `clang`, using `libbpf-cargo` for skeleton generation.
- **Headers**: `vmlinux.h` (generated from kernel BTF via `bpftool btf dump`) + standard `bpf_helpers.h`.
- **Map definitions**: use BTF-defined maps (`__uint`, `__type`, `SEC(".maps")`).
- **License**: every BPF program must include `char LICENSE[] SEC("license") = "GPL";`.
- **Naming**: BPF source files follow `<name>.bpf.c` convention. Programs are named `<name>_<function>`.
