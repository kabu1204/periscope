# DECISIONS.md — Decision Log (Append-Only, Modifying Historical Entries Is Forbidden)

> Append one entry per technology selection. Record rationale and alternatives considered, for post-hoc audit.

## Format

```
## D-NNN Title
- Date:
- Decision:
- Rationale:
- Alternatives considered (and reasons for not adopting):
- Basis: (ENVIRONMENT.md entry / benchmark data / proposal number)
```

## Entries

## D-001 eBPF Development Language
- Date: (To be filled before M2)
- Decision: Rust (libbpf-rs or aya, specific library to be selected)
- Rationale: Project constraint (see AGENTS.md)
- Alternatives considered: bcc-python (bpftrace can substitute during tutorial phase); C + libbpf (lower development efficiency)
- Basis: AGENTS.md engineering constraints
