# CLAUDE.md — SoundForge ClearWave

AI assistant and contributor reference for the `soundforge-clearwave` repository.

---

## Project Overview

**SoundForge ClearWave** is an AI-powered audio cleanup Android app built by [Infinite Signal Labs](https://github.com/Infinite-Signal-Labs) (Missoula, MT). It targets content creators, podcasters, and streamers who need one-click background noise removal, room echo correction, and loudness normalization with no manual tuning.

**Status:** MVP — active development. All core features are in progress.

**Tech stack:**
- Android (Kotlin + Jetpack Compose) — mobile client
- Firebase Auth, Firestore, Storage — user accounts and cloud job queue
- Google Gemini API — AI-driven DSP recommendations (text-only, no audio bytes sent)
- Python backend + Cloud Functions — async audio processing (planned, not yet in this repo)

---

## Repository Layout

```
soundforge-clearwave/
├── android/                          # Android application (Gradle)
│   ├── app/
│   │   ├── build.gradle              # App dependencies and SDK config
│   │   ├── proguard-rules.pro
│   │   ├── google-services.json.template   # Copy → google-services.json (not committed)
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       ├── java/com/isl/soundforge/
│   │       │   ├── MainActivity.kt         # Nav host, single-Activity entry point
│   │       │   ├── MainApplication.kt      # Firebase init, notification channels
│   │       │   ├── audio/
│   │       │   │   ├── AudioProcessor.kt        # On-device DSP pipeline
│   │       │   │   ├── AudioFileManager.kt       # File I/O, waveform, MediaStore
│   │       │   │   └── AudioProcessingService.kt # Foreground service for long jobs
│   │       │   ├── firebase/
│   │       │   │   ├── AuthManager.kt            # Firebase Auth wrapper
│   │       │   │   ├── StorageManager.kt         # Firebase Storage wrapper
│   │       │   │   └── ProcessingQueueManager.kt # Firestore job queue
│   │       │   ├── ai/
│   │       │   │   └── GeminiAudioAnalyzer.kt    # Gemini REST client
│   │       │   └── ui/
│   │       │       ├── EngineViewModel.kt         # Central state + orchestration
│   │       │       ├── theme/Theme.kt             # Cyberpunk design system
│   │       │       └── screens/
│   │       │           ├── AuthScreen.kt
│   │       │           ├── HomeScreen.kt
│   │       │           ├── ProcessScreen.kt
│   │       │           ├── LibraryScreen.kt
│   │       │           └── SettingsScreen.kt
│   │       └── res/
│   │           └── values/
│   │               ├── strings.xml     # 57 localized strings
│   │               ├── colors.xml
│   │               └── themes.xml
│   ├── build.gradle                  # Root Gradle: plugins (AGP 8.1.4, Kotlin 1.9.20, GMS)
│   ├── settings.gradle
│   ├── gradle.properties             # JVM args, AndroidX, non-transitive R
│   └── local.properties.template     # Copy → local.properties (SDK path, not committed)
│
├── tests/                            # Pure-JVM DSP unit tests (no Android dependency)
│   ├── build.gradle.kts              # Kotlin JVM, JUnit 5, JVM toolchain 21
│   ├── settings.gradle.kts
│   └── src/
│       ├── main/kotlin/com/isl/soundforge/DspMath.kt     # Extracted DSP math functions
│       └── test/kotlin/com/isl/soundforge/DspMathTest.kt # 26 JUnit 5 tests
│
├── .github/
│   └── workflows/detekt.yml          # Kotlin static analysis CI
│
└── README.md
```

**Why two separate Gradle projects?**
`tests/` is a plain Kotlin/JVM module so DSP math can be verified with JUnit 5 on any machine without an Android emulator. `android/` contains Android-specific test infra (Espresso, Compose UI tests) for integration-level work.

---

## Architecture

### Pattern: MVVM + Layered Services

```
UI (Compose screens)
    ↕  collectAsStateWithLifecycle()
EngineViewModel          ← single ViewModel, owns all AppState as StateFlow
    ↕  suspend calls / Flow
Service Layer
    ├── AuthManager          (Firebase Auth)
    ├── StorageManager       (Firebase Storage)
    ├── ProcessingQueueManager (Firestore job queue)
    ├── AudioFileManager     (file I/O, MediaStore, waveform)
    ├── AudioProcessor       (on-device DSP pipeline via MediaCodec)
    └── GeminiAudioAnalyzer  (Gemini REST API, OkHttp3)
```

- `EngineViewModel` never calls Firebase or Android APIs directly; it delegates to the service layer.
- Services throw exceptions; `EngineViewModel` catches with `runCatching` and writes `errorMessage` into `AppState`.
- All async work in the ViewModel uses `viewModelScope.launch { }`.
- Services use `suspend fun` throughout; no callbacks. Firestore listeners are bridged via `callbackFlow + awaitClose { }`.

### Two-Path Processing Model

**On-Device (fast, offline):**
1. Decode audio → raw PCM via `MediaCodec`
2. DSP stack: spectral noise suppression → room correction (IIR HPF ~80 Hz) → loudness normalization (RMS-based)
3. Encode PCM → AAC via `MediaCodec`
4. Save to app cache

**Cloud (advanced, requires network):**
1. `GeminiAudioAnalyzer` measures audio characteristics, queries Gemini API, returns DSP recommendations
2. Upload raw file to Firebase Storage (`users/{uid}/raw/`)
3. Enqueue job in Firestore (`users/{uid}/jobs/{jobId}`)
4. Python backend (planned) processes asynchronously, writes result to `users/{uid}/processed/`
5. App monitors job status via Firestore `Flow`; downloads and caches output when done

The Gemini API key is optional — the app degrades gracefully to safe defaults when not configured.

### Navigation

Single-`Activity` architecture (`MainActivity`). Navigation via `NavHost` with a `Screen` enum:

```kotlin
enum class Screen(val route: String) {
    AUTH("auth"), HOME("home"), PROCESS("process"),
    LIBRARY("library"), SETTINGS("settings")
}
```

---

## Key Files

| File | Purpose |
|------|---------|
| `android/app/src/main/java/com/isl/soundforge/MainActivity.kt` | Nav host, theme application |
| `android/app/src/main/java/com/isl/soundforge/MainApplication.kt` | Firebase init, notification channels |
| `android/app/src/main/java/com/isl/soundforge/ui/EngineViewModel.kt` | All state (`AppState`) + business logic orchestration |
| `android/app/src/main/java/com/isl/soundforge/audio/AudioProcessor.kt` | DSP pipeline (noise gate, HPF, normalization, MediaCodec) |
| `android/app/src/main/java/com/isl/soundforge/audio/AudioFileManager.kt` | Content URI handling, metadata, waveform thumbnail, MediaStore save |
| `android/app/src/main/java/com/isl/soundforge/audio/AudioProcessingService.kt` | Foreground service for long-running encode/decode jobs |
| `android/app/src/main/java/com/isl/soundforge/firebase/AuthManager.kt` | Email + Google Sign-In, password reset |
| `android/app/src/main/java/com/isl/soundforge/firebase/StorageManager.kt` | Upload/download with progress, batch delete |
| `android/app/src/main/java/com/isl/soundforge/firebase/ProcessingQueueManager.kt` | Firestore job CRUD + real-time status Flow |
| `android/app/src/main/java/com/isl/soundforge/ai/GeminiAudioAnalyzer.kt` | Gemini 1.5 Flash REST client, JSON parsing, graceful fallback |
| `android/app/src/main/java/com/isl/soundforge/ui/theme/Theme.kt` | `IslColors`, typography, Material3 dark theme |
| `tests/src/main/kotlin/com/isl/soundforge/DspMath.kt` | Pure-JVM DSP functions (extracted from `AudioProcessor`) |
| `tests/src/test/kotlin/com/isl/soundforge/DspMathTest.kt` | 26 JUnit 5 tests for all DSP math functions |

---

## Build & Run Commands

### Android App

Requires Android Studio (Electric Eel+) or Android SDK 34 on PATH.

```bash
# One-time setup: copy template files
cp android/local.properties.template android/local.properties   # set sdk.dir
cp android/app/google-services.json.template android/app/google-services.json

# Debug build
cd android && ./gradlew assembleDebug

# Install on connected device
cd android && ./gradlew installDebug

# Run Android instrumented tests (requires emulator/device)
cd android && ./gradlew connectedAndroidTest
```

### DSP Unit Tests (JVM, no device needed)

```bash
cd tests && ./gradlew test
```

Outputs test report at `tests/build/reports/tests/test/index.html`.

### Static Analysis

Detekt runs automatically via CI (`.github/workflows/detekt.yml`) on every push to `main` and every PR. To run locally:

```bash
# Download detekt CLI (v1.15.0) and run manually, or rely on CI
```

---

## Testing Conventions

- All DSP math lives in `tests/src/main/kotlin/com/isl/soundforge/DspMath.kt` as pure functions with no Android imports. When adding DSP logic to `AudioProcessor`, extract the math into `DspMath.kt` and write a corresponding test.
- Test framework: **JUnit 5 (Jupiter)**. Use backtick-quoted descriptive names:
  ```kotlin
  @Test fun `rmsOf constant signal equals that value`() { ... }
  ```
- Float comparisons always use a delta: `assertEquals(expected, actual, 1e-5f)`
- The 26 existing tests cover: `rmsOf`, `estimateNoiseFloor`, `measurePeakDb`, `estimateNoiseFloorDb`, `applyRoomCorrection`, `normalizeLoudness`, `applySpectralNoiseSuppression`.

---

## Code Conventions

### Naming

| Kind | Convention | Example |
|------|-----------|---------|
| Classes, objects, enums | PascalCase | `AudioProcessor`, `IslColors` |
| Functions, properties, variables | camelCase | `estimateNoiseFloor`, `currentUser` |
| Constants | UPPER_SNAKE_CASE | `BASE_URL`, `NOTIFICATION_ID` |
| Sealed class variants (inline) | PascalCase | `ProcessingState.Idle`, `ProcessingState.Done(item)` |

### File & Package Organization

- One class per file (sealed class inner types are the only exception).
- Package structure is feature-based: `audio/`, `firebase/`, `ui/`, `ai/`.
- No star imports — explicit imports only.
- Tests mirror source: `tests/src/test/` mirrors `tests/src/main/`.

### Coroutines & State

```kotlin
// ViewModel: launch all async work in viewModelScope
viewModelScope.launch { ... }

// Blocking I/O in services: always switch dispatcher
withContext(Dispatchers.IO) { ... }

// Service functions: always suspend, never callbacks
suspend fun uploadFile(uri: Uri): String { ... }

// Firestore real-time listeners: callbackFlow
fun watchJob(jobId: String): Flow<Job> = callbackFlow {
    val sub = firestore.document(path).addSnapshotListener { snap, _ -> trySend(snap.toObject()) }
    awaitClose { sub.remove() }
}

// State: private MutableStateFlow, exposed as read-only
private val _state = MutableStateFlow(AppState())
val state: StateFlow<AppState> = _state.asStateFlow()
```

### Error Handling

```kotlin
// Services: throw, don't return nulls for failures
suspend fun signIn(email: String, password: String) {
    auth.signInWithEmailAndPassword(email, password).await()  // throws on failure
}

// ViewModel: catch everything, write to errorMessage
runCatching { authManager.signIn(email, password) }
    .onSuccess { _state.update { it.copy(isAuthenticated = true) } }
    .onFailure { e -> _state.update { it.copy(errorMessage = e.message) } }
```

### Compose UI Patterns

- Composable screens receive state as parameters, not by injecting the ViewModel directly.
- `collectAsStateWithLifecycle()` in screens, not `collectAsState()`.
- Padding/spacing in explicit `.dp` values inside `Modifier` chains.
- `Icons.AutoMirrored.Filled.ArrowBack` for back navigation (not deprecated `Icons.Filled`).

---

## Design System

Defined in `android/app/src/main/java/com/isl/soundforge/ui/theme/Theme.kt`.

**ISL Cyberpunk palette (`IslColors` object):**

| Name | Hex | Usage |
|------|-----|-------|
| `Void` | `#06060C` | App background |
| `Surface` | `#0D0D1A` | Card/surface background |
| `SurfaceHigh` | `#141428` | Elevated surfaces |
| `Cyan` | `#00F0FF` | Primary accent, interactive |
| `Magenta` | `#FF00AA` | Secondary accent |
| `TextPrimary` | `#E0E0FF` | Body text |
| `TextSecondary` | `#99B0B0CC` | Captions, disabled |
| `Success` | `#00FF88` | Done states |
| `Warning` | `#FFCC00` | Warnings |
| `Error` | `#FF3355` | Error states |

**Typography:** Monospace font for body/code text; system default for headings.

Material3 dark theme. Always use `IslColors` constants rather than raw hex values in new UI code.

---

## Firebase & Backend Schema

### Auth

Firebase Auth with email/password and Google Sign-In (ID token exchange). The Firebase UID (`uid`) is the primary user key across all services.

### Firestore: Job Queue

Path: `users/{uid}/jobs/{jobId}`

```
Job {
    id: String
    status: "queued" | "processing" | "done" | "error"
    rawFileName: String
    outputFileName: String
    noiseReduction: Boolean      // default true
    roomCorrection: Boolean      // default true
    normalization: Boolean       // default true
    targetLUFS: Float            // default -14.0
    noiseThreshold: Float        // default 0.3
    errorMessage: String
    createdAt: Long              // epoch ms
    inputPeakDb: Float
    outputPeakDb: Float
    noiseFloorDb: Float
}
```

### Firebase Storage

| Path | Content |
|------|---------|
| `users/{uid}/raw/{filename}` | Raw uploaded audio file |
| `users/{uid}/processed/{filename}` | Processed output (written by backend) |

### Local State

No local SQLite or Room database. All persistent state is in Firebase. In-memory state is `AppState` held as a `StateFlow` in `EngineViewModel`.

### Gemini API

Model: `gemini-1.5-flash` (text-only — no audio bytes are transmitted).  
The client sends measured audio characteristics (peak dB, RMS, noise floor, dynamic range, filename) and parses a JSON response for DSP parameter recommendations.  
The API key is stored in `BuildConfig` or provided by the user at runtime via Settings. The analyzer returns `null` when the key is blank, and `AudioProcessor` falls back to `ProcessingOptions` defaults.

---

## CI/CD

`.github/workflows/detekt.yml` runs Detekt v1.15.0 static analysis on:
- Push to `main`
- All pull requests
- Weekly schedule (Sundays 01:17 UTC)
- Manual dispatch

Results are uploaded as a SARIF report to the GitHub Security tab. Fix any Detekt findings before merging to `main`.

---

## What Is NOT in This Repository

| Component | Status |
|-----------|--------|
| Python DSP backend | Planned — not yet present |
| Firebase Cloud Functions | Planned — referenced in architecture |
| `google-services.json` | Excluded from git — use `.template` to create it |
| `local.properties` | Excluded from git — use `.template` to create it |
| Build artifacts (`build/`, `.gradle/`) | Excluded via `.gitignore` |

---

## Quick Reference: DSP Parameters

`AudioProcessor.ProcessingOptions` (defaults):

| Parameter | Default | Description |
|-----------|---------|-------------|
| `noiseReduction` | `true` | Spectral soft-knee noise gate |
| `roomCorrection` | `true` | Single-pole IIR HPF at ~80 Hz |
| `normalization` | `true` | RMS-based gain to target LUFS |
| `targetLUFS` | `-14f` | Standard streaming loudness target |
| `noiseThreshold` | `0.3f` | Gate threshold (0.0–1.0) |
