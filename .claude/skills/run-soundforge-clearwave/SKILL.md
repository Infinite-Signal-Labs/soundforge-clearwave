---
name: run-soundforge-clearwave
description: run, test, build, verify, debug, harden, and lead development of the soundforge-clearwave DSP library and Android audio app; execute the full test suite, run smoke tests, add DSP functions, check for regressions, confirm CI readiness
---

# run-soundforge-clearwave

SoundForge ClearWave is an Android audio app with a pure-JVM DSP math library (`tests/`) that is the primary testable surface. The Android app itself requires a connected device or emulator; all CI-relevant logic lives in `tests/`. The driver for this project is `smoke.sh` — it runs the full JUnit 5 suite against `tests/src/main/kotlin/com/isl/soundforge/DspMath.kt`.

All paths below are relative to the repo root (`soundforge-clearwave/`).

---

## Prerequisites

```bash
java -version    # must be 21+; system has openjdk 21.0.10
gradle --version # system Gradle at /opt/gradle/bin/gradle (8.14.3 confirmed)
```

No `./gradlew` wrapper exists in `tests/` — use the system `gradle` binary directly.

---

## Run (agent path)

**Full suite:**
```bash
bash .claude/skills/run-soundforge-clearwave/smoke.sh
```

**Filter to one area (e.g., rms, noise, room, normalize, spectral):**
```bash
bash .claude/skills/run-soundforge-clearwave/smoke.sh --filter=rms
bash .claude/skills/run-soundforge-clearwave/smoke.sh --filter=noise
bash .claude/skills/run-soundforge-clearwave/smoke.sh --filter=normalize
```

**With full deprecation warnings (Gradle 9 readiness check):**
```bash
bash .claude/skills/run-soundforge-clearwave/smoke.sh --check
```

Output: test results streamed to stdout. `BUILD SUCCESSFUL` = all green. `BUILD FAILED` + `FAILED` lines = what to fix.

First run: ~76 s (compile + test). Subsequent runs with no source change: ~8 s (Gradle cache).

---

## Run (human path)

```bash
cd tests
gradle test --no-daemon
```

Opens nothing. Prints test results to terminal. Ctrl-C to abort.

---

## Adding a new DSP function — the required pattern

Every new DSP function MUST follow this extract-test-implement cycle:

1. **Add pure math to `DspMath.kt`** (no Android imports):
   ```
   tests/src/main/kotlin/com/isl/soundforge/DspMath.kt
   ```

2. **Add tests in `DspMathTest.kt`** covering: empty input, constant input, known mathematical result, and edge cases (silence, clipping):
   ```
   tests/src/test/kotlin/com/isl/soundforge/DspMathTest.kt
   ```
   Use backtick test names:
   ```kotlin
   @Test fun `myFunc zero input returns zero`() { ... }
   @Test fun `myFunc known signal returns expected value`() {
       assertEquals(expected, actual, 1e-5f)  // always use delta for floats
   }
   ```

3. **Run the filter to confirm new tests pass:**
   ```bash
   bash .claude/skills/run-soundforge-clearwave/smoke.sh --filter=myFunc
   ```

4. **Run the full suite to confirm no regressions:**
   ```bash
   bash .claude/skills/run-soundforge-clearwave/smoke.sh
   ```

5. **Mirror in `AudioProcessor.kt`** (Android module, calls the same logic via MediaCodec pipeline):
   ```
   android/app/src/main/java/com/isl/soundforge/audio/AudioProcessor.kt
   ```

---

## Code hardening checklist (pre-PR)

Run through this before every commit touching DSP or Firebase logic:

```bash
# 1. Full test suite — no failures
bash .claude/skills/run-soundforge-clearwave/smoke.sh

# 2. Check for Gradle 9 incompatibilities
bash .claude/skills/run-soundforge-clearwave/smoke.sh --check

# 3. Confirm float assertions use delta tolerance (grep for assertEquals without delta)
grep -n 'assertEquals.*Float\|assertEquals.*float' \
  tests/src/test/kotlin/com/isl/soundforge/DspMathTest.kt | \
  grep -v ', [0-9]' || echo "all float assertions have delta — OK"
```

Manual checks (no automated tool):
- `EngineViewModel`: every async path uses `runCatching`; `errorMessage` set on failure
- `AudioProcessor`: MediaCodec buffers always released in `finally`; no silent swallows
- `GeminiAudioAnalyzer`: returns `null` (not throws) when API key is blank
- New `DspMath.kt` functions: no Android imports, pure `kotlin.*` / `kotlin.math.*` only

---

## Debugging a failing test

1. **Run just the failing filter** to isolate:
   ```bash
   bash .claude/skills/run-soundforge-clearwave/smoke.sh --filter=<functionName>
   ```

2. **Read the failure output** — Gradle streams the assertion error and stack trace directly. The pattern is:
   ```
   DspMathTest > <test name>() FAILED
       org.opentest4j.AssertionFailedError: expected: <X> but was: <Y>
   ```

3. **Check delta tolerance** — the most common failure cause is float imprecision without a delta:
   ```kotlin
   // Wrong:  assertEquals(0.707f, rmsOf(sine))
   // Correct: assertEquals(0.707f, rmsOf(sine), 1e-5f)
   ```

4. **Check array bounds** — `estimateNoiseFloor` and `applySpectralNoiseSuppression` have minimum-frame-count guards. A short test array (< `frameSize` samples) returns early with a safe default. Confirm your test array is long enough or explicitly test the short-array edge case.

5. **Re-run full suite** after fix to confirm no regression.

---

## CI readiness gate

The Detekt workflow (`.github/workflows/detekt.yml`) runs on every PR. It only analyzes Kotlin files — `CLAUDE.md` and other Markdown are invisible to it. A PR is CI-ready when:

- `BUILD SUCCESSFUL` from the smoke driver
- No new Kotlin files with star imports, unused variables, or magic numbers (Detekt's assertive profile flags these)
- Workflow file has the corrected jq path (`.data.repository.release.tagCommit.oid` — already fixed in this branch)

---

## Gotchas

- **No `./gradlew` in `tests/`** — the wrapper was excluded from the repo. Use `gradle` (system binary). If `gradle` is not on PATH, it's at `/opt/gradle/bin/gradle`.
- **Kotlin JVM toolchain is 21** — the build will fail with Java < 21. `java -version` must show 21+.
- **Gradle 9 incompatibility warning is expected** — `build.gradle.kts` uses features deprecated in Gradle 9. It's a warning, not a failure. The `--check` flag surfaces the specific deprecations if you want to fix them.
- **`DspMath.kt` must stay Android-free** — any `android.*` import breaks the pure-JVM test module. The test compile step will fail immediately if this constraint is violated.
- **First run is slow (~76 s)** — Kotlin compilation. Subsequent runs with no source changes hit Gradle's incremental cache and finish in ~8 s.
- **`estimateNoiseFloor` uses 10th-percentile frame selection** — test arrays must have at least 2× `frameSize` samples (default: `sampleRate / 100`) to exercise the percentile logic. Shorter arrays return 0 by early-exit guard.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `gradle: command not found` | Use `/opt/gradle/bin/gradle` or add to PATH: `export PATH=/opt/gradle/bin:$PATH` |
| `error: release version 21 not supported` | Java < 21 on PATH. `export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))` |
| `Unresolved reference: android` | A `DspMath.kt` function imported an Android class. Remove it; use pure Kotlin math only. |
| `BUILD FAILED` — `ClassNotFoundException` on JUnit runner | JUnit 5 not on test classpath. Check `build.gradle.kts` has `testImplementation("org.junit.jupiter:junit-jupiter:5.10.1")` and `useJUnitPlatform()`. |
| Test result says `UP-TO-DATE` and skips test execution | Source hasn't changed since last run. Touch a source file or run `gradle clean test --no-daemon`. |
