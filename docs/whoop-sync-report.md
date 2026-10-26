# WHOOP sync investigation report template

Copy this template to a private workspace and fill it with evidence from
[the sync workflow](whoop-sync-investigation.md). This blank template contains
no observed WHOOP protocol findings.

## Target and coverage

| Item | Value / evidence |
| --- | --- |
| Phone model / Android release / API level | Unknown |
| WHOOP app version / package ID | Unknown |
| Band model / firmware version | Unknown |
| APK paths and SHA-256 (including splits) | Unknown |
| Capture path and SHA-256 | Unknown |
| REA version / source commit | Unknown |
| JADX JAR hash / JDK version | Unknown |
| TShark version / capture encapsulation | Unknown |
| Experiment start/end / time zone / clock uncertainty | Unknown |
| Missing splits, payloads, discovery or truncated results | Unknown |

## Experiment timeline

| Time and clock source | Action / visible state | Capture frame or evidence reference |
| --- | --- | --- |
| Unknown | Baseline | Unknown |
| Unknown | Sync started | Unknown |
| Unknown | Sync completed | Unknown |

## Evidence ledger

Use `observed` for direct recorded facts, `derived` for parsed/decompiled
representations, `inferred` for interpretations and `unknown` for unresolved
questions. Each new claim needs its own row. Cite file hash plus frame numbers
for captures, or APK hash plus class/method/DEX descriptor for code.

| Claim | Classification | Source / location | Coverage and alternative explanations | Next check |
| --- | --- | --- | --- | --- |
| Sync message format | Unknown | No evidence yet | No capture analysed | Inspect selected connection |
| App message handler | Unknown | No evidence yet | No APK analysed | Inspect candidate methods |
| Cloud upload path | Unknown | No evidence yet | Bluetooth evidence alone is insufficient | Trace app upload code |

## Protocol notebook

| Capture / connection | Service / characteristic UUID | Handle | Direction / opcode | Payload interpretation | Frames + app method | Confidence |
| --- | --- | --- | --- | --- | --- | --- |
| Unknown | Unknown | Unknown | Unknown | Unknown | None | Unknown |

Do not reuse handle mappings across connections without supporting discovery.
Keep raw personal payloads in the private evidence files.

## Result

- Established behaviour: none yet.
- Repeatability across captures: untested.
- Remaining unknowns: band model, firmware, message meanings, storage and upload.
- Capability gap demonstrated in REA: none yet.
- Next smallest experiment: acquire the installed APK and one normal-sync trace.
