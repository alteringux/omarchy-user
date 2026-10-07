# PRD 03 deterministic fixture evidence

Run from the repository root:

```sh
node --test docs/prds/evidence/03-recovery-help/recovery-fixtures.test.js
```

The fixture harness loads the current `RecoveryTrigger.js` and `RecoveryModel.js`
source in a Node VM after removing only `.pragma library`. It injects timestamps
and inert binding/event objects. It has no QML globals, catalog process, command
executor, or desktop input path. Fixture `command` and `args` strings are inert
and are asserted absent from the presentation and attempt records.

## Latest result

22 tests pass, 0 fail (including collision ordering/classification, capacity,
unknown-key and execution-isolation fixtures).
No source defect remains in the tested deterministic policy/model cases.

Covered: three distinct misses and four-second expiration; duplicate chords and
physical press IDs; repeat, typing, modifier-only, editor, composition,
unowned, disabled, and focus-loss exclusions; handled/unavailable resets;
context change; cooldown boundary; clock rollback; recovery whole-word matching;
exact duplicate merge vs. same-description distinct chords; modifier/keycode
labels, submap and activation flags; local panel records; search; invalid catalog
type; collision classification and ordering; per-layer capacity; and
command/executor field isolation.

## Coverage boundary

This is fixture evidence for policy, presentation functions, and the isolated
live-reader adapter, not proof of native focus routing, passive announcement
behavior, or per-plugin dispatch ownership. In PRD terms, the fixtures cover portions of
R01–R02, R04–R05, and R07–R10. R03, R06 runtime behavior, R11 native
accessibility, and R12 real integration routing remain unverified here. These fixtures do not establish global unmatched-key detection.

Separate [native Pulse/Timers evidence](native-recovery-pilot.md) now records
owned routing, editor suppression, passive suggestions, cooldown and manual
Help keyboard navigation. External AT-SPI delivery and enlarged Help layout
remain gaps; the deterministic fixtures do not replace those checks.

The model has no JSON decoder. Its invalid-input check verifies rejection of a
non-array catalog value; malformed JSON and process failures are covered by the
isolated reader fixture below.

## Isolated native reader fixture

`run-catalog-fixture.py` copies the production `RecoveryCatalog.qml` and
`RecoveryModel.js` into a temporary directory, then runs a no-window Quickshell
`ShellRoot` probe. A temporary `hyprctl` stub is first in PATH only inside each
fixture process. Its trace records only argument strings and verifies every
reader invocation is exactly `-j binds`. Scenarios cover valid and empty JSON,
invalid JSON, nonzero exit, retry after failure, and the five-second deadline.
No real `hyprctl` or recovery command is invoked; no panel, desktop window, or
user preference is opened.

Latest run: all six scenarios passed. The fixture reports one call each for
valid, empty, invalid, nonzero, and deadline cases, and two `-j binds` calls for
the retry case. Error cases return no records and the shared truthful error;
retry returns the fixture record. This closes R09 reader behavior for these
inert cases, not for compositor or live catalog conditions.
