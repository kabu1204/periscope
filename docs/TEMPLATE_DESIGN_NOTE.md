# Design Note Template

> One note per deliverable. Target reader: someone who understands operating systems and systems programming but has zero eBPF background (i.e., the user).
> The document serves as both engineering record and tutorial. Style requirements are in AGENTS.md "Language and Documentation Style."

## Title: MX-Name

## Conclusion First

(3–5 sentences: what was delivered, what the verification results are.)

## Background and Principles

(Explain the relevant mechanisms clearly: what kernel path does this tool observe, where are the probes attached, how is data aggregated. Define terms on first occurrence.)

## Design

(Architecture and key implementation decisions. Link technology selection decisions to DECISIONS.md entries.)

## Verification

(What is the oracle, comparison method, results summary (table + key output), within/outside tolerance determination.)

## How to Manually Verify

(Numbered checklist; user can spot-check item by item. Each item provides a command and expected output characteristics.)

## Known Limitations

(List honestly: overhead, kernel version dependencies, uncovered scenarios.)
