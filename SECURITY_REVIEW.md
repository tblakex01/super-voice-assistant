# Security Review: Super Voice Assistant

**Date:** 2026-02-27
**Scope:** Comprehensive audit of the main branch
**Severity Threshold:** Medium and above
**Reviewer:** Automated security review

---

## Executive Summary

Super Voice Assistant is a macOS menu bar application that provides voice transcription (local and cloud-based), text-to-speech, and screen recording with video transcription. The app interfaces with Google's Gemini API over REST and WebSocket, executes ffmpeg as a subprocess, injects keyboard events via CGEvent, and stores transcription history on disk.

This review identified **13 findings** across 7 categories:

| Severity | Count |
|----------|-------|
| High     | 1     |
| Medium   | 12    |

The highest-severity finding is **improper JSON construction** in the WebSocket TTS client, which can cause malformed API messages and potential unexpected behavior. Several medium findings relate to sensitive data logging, plaintext storage, and credential handling patterns.

---

## Findings

### HIGH-1: Unsafe JSON String Interpolation in WebSocket Messages

**Severity:** High
**File:** `SharedSources/GeminiAudioCollector.swift:83-98`
**Category:** Input Validation / Injection

**Description:**
User-provided text is interpolated directly into a JSON string literal using Swift string interpolation (`\(text)`). If the text contains JSON-special characters (`"`, `\`, newlines, tabs, or Unicode escape sequences), the resulting JSON will be malformed.

```swift
let textMessage = """
{
    "client_content": {
        "turns": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": "...speak these exact words: \(text)"
                    }
                ]
            }
        ],
        "turn_complete": true
    }
}
"""
```

**Impact:**
- Text containing `"` or `\` characters will produce invalid JSON, causing the API call to fail silently or produce unexpected behavior.
- Carefully crafted text could potentially manipulate the JSON structure (JSON injection), altering the API request semantics.
- This affects the TTS feature (Cmd+Opt+S) whenever the selected text contains special characters.

**Remediation:**
Construct the JSON using `JSONSerialization` or `Codable` to ensure proper escaping:

```swift
let payload: [String: Any] = [
    "client_content": [
        "turns": [
            [
                "role": "user",
                "parts": [
                    ["text": "...speak these exact words: \(text)"]
                ]
            ]
        ],
        "turn_complete": true
    ]
]
let jsonData = try JSONSerialization.data(withJSONObject: payload)
let jsonString = String(data: jsonData, encoding: .utf8)!
try await webSocketTask.send(.string(jsonString))
```

---

### MED-1: Sensitive Transcription Data Logged to System Console

**Severity:** Medium
**Files:**
- `Sources/AudioTranscriptionManager.swift:397` - `print("Transcription: \"\(transcription)\"")`
- `Sources/GeminiAudioRecordingManager.swift:281` - `print("✅ Gemini transcription: \"\(trimmed)\"")`
- `Sources/main.swift:350-353` - Video transcription printed in full
- `Sources/TranscriptionHistory.swift:72` - `print("Added transcription to history: \(text)")`
- `Sources/main.swift:497` - `print("📖 Selected text for streaming TTS: \(copiedText)")`
**Category:** Information Disclosure

**Description:**
Full transcription text is logged via `print()` to stdout/stderr. On macOS, these logs are captured by the unified logging system and can be read via Console.app or the `log` command by any process running as the same user or by an administrator.

**Impact:**
Transcribed content (which may include private conversations, dictated passwords, confidential information, or sensitive screen content from video transcription) is persisted in system logs with no expiry control.

**Remediation:**
- Replace `print()` calls that output sensitive content with either:
  - A conditional debug-only logging mechanism (`#if DEBUG`)
  - Apple's `os_log` with `.private` privacy level: `os_log("Transcription: %{private}@", text)`
- Keep operational status messages (start/stop/error) but redact actual transcription content.

---

### MED-2: Transcription History Stored as Unencrypted Plaintext

**Severity:** Medium
**File:** `Sources/TranscriptionHistory.swift:20-27`
**Category:** Data at Rest

**Description:**
Transcription history is stored in `~/Documents/SuperVoiceAssistant/transcription_history.json` as unencrypted JSON. The file is created with default permissions (typically `0644`), meaning any process running as the same user can read it.

Up to 100 entries are retained with no time-based expiry.

**Impact:**
- Sensitive transcribed content is accessible to any application or process running under the same user account.
- No mechanism exists for users to set a retention period or auto-purge old entries.
- If the Mac is shared, other user-level processes could exfiltrate transcription data.

**Remediation:**
- Set restrictive file permissions (0600) when writing: `try data.write(to: historyFileURL, options: [.atomic, .completeFileProtection])`
- Consider using the macOS Keychain or encrypted storage for sensitive transcription data.
- Add configurable retention periods with automatic purging of old entries.
- Apply the same treatment to `transcription_stats.json` and model metadata files.

---

### MED-3: API Key Passed as URL Query Parameter

**Severity:** Medium
**Files:**
- `SharedSources/GeminiAudioTranscriber.swift:112`
- `SharedSources/VideoTranscriber.swift:111`
- `SharedSources/GeminiAudioCollector.swift:41`
**Category:** Credential Exposure

**Description:**
The Gemini API key is included as a URL query parameter (`?key=<API_KEY>`) in both REST and WebSocket URLs. While the connections use TLS (HTTPS/WSS), the full URL including the key may appear in:

- macOS unified logging system (URL connection logs)
- Process listing (`ps` output showing WebSocket connection URLs)
- Network diagnostic tools
- Corporate TLS-inspecting proxies that log URLs

**Impact:**
The API key could be exposed through log aggregation, process monitoring, or network inspection, potentially allowing unauthorized use of the user's Gemini API quota.

**Note:** This is the authentication method prescribed by Google's Generative AI API. There is currently no alternative header-based authentication for API keys. For service-account-based deployments, OAuth2 bearer tokens via the `Authorization` header would be preferred.

**Remediation:**
- This is inherent to the Google API design and cannot be fully mitigated while using API key authentication.
- Document this limitation for users.
- Consider supporting OAuth2 authentication as an alternative if Google provides it in the future.
- Avoid logging URLs that contain the API key.

---

### MED-4: Configuration and Secrets Loaded Relative to Current Working Directory

**Severity:** Medium
**Files:**
- `Sources/main.swift:14-15` - `.env` loaded from CWD
- `SharedSources/GeminiAudioTranscriber.swift:168` - `.env` loaded from CWD
- `SharedSources/VideoTranscriber.swift:168` - `.env` loaded from CWD
- `Sources/TextReplacements.swift:15-16` - `config.json` loaded from CWD
**Category:** Configuration Security

**Description:**
Both the `.env` file (containing the API key) and `config.json` are loaded relative to `FileManager.default.currentDirectoryPath`. The current working directory depends on how the application is launched (e.g., from Finder, Terminal, a script, or a LaunchAgent).

Additionally, `.env` loading is duplicated across three files with slightly different parsing logic, increasing the risk of inconsistent behavior.

**Impact:**
- If the app is launched from an attacker-controlled directory, it could load a malicious `.env` file, redirecting API calls to a different endpoint or exfiltrating the API key.
- The `config.json` text replacements, if loaded from a malicious source, could silently alter transcription output.
- Duplicated parsing logic means a fix in one location may not propagate to others.

**Remediation:**
- Load `.env` and `config.json` from a fixed, known path (e.g., `~/.config/SuperVoiceAssistant/` or the app's bundle directory).
- Consolidate `.env` parsing into a single shared utility.
- Consider using macOS Keychain for API key storage instead of a flat `.env` file.

---

### MED-5: Unsanitized API Response Auto-Pasted at Cursor

**Severity:** Medium
**Files:**
- `Sources/main.swift:717-781` - `pasteTextAtCursor()`
- `Sources/AudioTranscriptionManager.swift:400-403`
- `Sources/GeminiAudioRecordingManager.swift:277-287`
**Category:** Output Handling / Injection

**Description:**
Transcription text received from the Gemini API (or generated by local WhisperKit/Parakeet) is automatically pasted into whatever application has focus via simulated Cmd+V keyboard events. No sanitization or user confirmation occurs before pasting.

**Impact:**
- If the focused application is a terminal emulator, injected text could be interpreted as shell commands.
- A compromised or malfunctioning API could return malicious text that gets auto-pasted.
- Even for local transcription, adversarial audio (e.g., audio played from a speaker near the mic) could inject targeted text.

**Remediation:**
- Consider adding a confirmation step or preview before auto-pasting, at least as an optional setting.
- Sanitize pasted text to strip control characters and ANSI escape sequences.
- Warn users in documentation about the auto-paste behavior and its implications.

---

### MED-6: Screen Recording Saved to Predictable Desktop Location

**Severity:** Medium
**File:** `Sources/ScreenRecorder.swift:75-79`
**Category:** Information Disclosure / Data at Rest

**Description:**
Screen recordings are saved to `~/Desktop/screen-recording-<timestamp>.mp4` with a predictable filename format. While the file is deleted after successful transcription, it persists on disk during the transcription API call.

**Impact:**
- If the app crashes during transcription or the API call fails, the video file containing potentially sensitive screen content remains on the Desktop indefinitely.
- The predictable filename pattern makes it easy for other processes to monitor for and read these files.
- Desktop files are visible to any process running as the same user.

**Remediation:**
- Save recordings to a temporary directory with restricted permissions (e.g., a subdirectory of `NSTemporaryDirectory()` with mode 0700).
- Implement cleanup of orphaned recording files on app startup.
- Use a non-predictable filename component (e.g., UUID).

---

### MED-7: No Certificate Pinning on API Connections

**Severity:** Medium
**Files:**
- `SharedSources/GeminiAudioTranscriber.swift:118` - `URLSession.shared.dataTask()`
- `SharedSources/VideoTranscriber.swift:117` - `URLSession.shared.dataTask()`
- `SharedSources/GeminiAudioCollector.swift:48` - `session.webSocketTask()`
**Category:** Network Security

**Description:**
All API connections use `URLSession.shared` without custom certificate validation or pinning. The app trusts all certificates in the system trust store.

**Impact:**
- In corporate environments with TLS-inspecting proxies, API traffic (including the API key and transcription data) could be intercepted and logged.
- A compromised or rogue CA could enable MITM attacks against API connections.
- Audio data, video data, and transcription results transit through these connections.

**Remediation:**
- For personal-use software, this risk is generally acceptable. However, if sensitive data is involved:
  - Implement certificate pinning for Google's API endpoints.
  - Use a custom `URLSessionDelegate` that validates the server certificate against known Google root CAs.

---

### MED-8: Clipboard Race Condition Window

**Severity:** Medium
**Files:**
- `Sources/main.swift:464-578` - `readSelectedText()`
- `Sources/main.swift:717-781` - `pasteTextAtCursor()`
**Category:** Data Integrity

**Description:**
The clipboard is temporarily overwritten during both the TTS flow (Cmd+C to copy selection) and the paste flow (Cmd+V to paste transcription). The original clipboard contents are saved and restored after a fixed delay (0.1s-0.2s). This creates several issues:

1. If the app crashes between overwrite and restore, clipboard data is permanently lost.
2. If the user performs a copy/paste during the delay window, it will interact with the temporary clipboard state.
3. The restore uses a fixed time delay rather than event-based completion, which is inherently racy.

**Impact:**
Users may lose clipboard contents (text, images, files) if the app crashes or encounters an error during transcription paste or TTS copy operations.

**Remediation:**
- Use `NSPasteboard`'s change count to detect if the user modified the clipboard during the operation, and skip restoration if so.
- Implement a more robust clipboard save/restore mechanism that handles errors and crashes.
- Consider using `NSPasteboard.withName(.general)` with atomic operations.

---

### MED-9: Audio Buffer Data Retained in Memory

**Severity:** Medium
**Files:**
- `Sources/AudioTranscriptionManager.swift:23,124`
- `Sources/GeminiAudioRecordingManager.swift:22,123`
**Category:** Data in Memory

**Description:**
Audio recording buffers (containing raw microphone input) remain in memory after transcription completes, only being cleared when a new recording starts. The buffer can hold up to 5 minutes of 16kHz audio (~19MB of Float data).

**Impact:**
- Sensitive audio data persists in process memory longer than necessary.
- A memory dump or debugging attachment could extract previously recorded audio.
- While Swift's ARC will eventually release the memory, the data is not actively zeroed.

**Remediation:**
- Clear the audio buffer immediately after transcription completes (not just at the start of the next recording).
- Add `audioBuffer.removeAll()` after `processRecording()` completes.

---

### MED-10: WebSocket API Responses Logged Verbatim

**Severity:** Medium
**File:** `SharedSources/GeminiAudioCollector.swift:110`
**Category:** Information Disclosure

**Description:**
Full WebSocket text messages from the Gemini API are logged via `print()`:
```swift
print("📝 Received text message: \(text)")
```

**Impact:**
API response payloads, which may contain error details, account information, or model metadata, are written to the system log. Error responses from Google's API sometimes include account identifiers or request details.

**Remediation:**
- Remove verbose response logging or limit it to `#if DEBUG` builds.
- If logging is needed for diagnostics, truncate messages and redact sensitive fields.

---

### MED-11: Fragile .env Parsing Rejects Valid Values

**Severity:** Medium
**File:** `Sources/main.swift:22-32`
**Category:** Configuration Security

**Description:**
The `.env` parser in `main.swift` splits lines on `=` and requires exactly 2 parts (`parts.count == 2`). This means any value containing an `=` character (common in base64-encoded tokens, connection strings, etc.) will be silently rejected.

The parsers in `GeminiAudioTranscriber.swift` and `VideoTranscriber.swift` use a different approach (`hasPrefix("GEMINI_API_KEY=")` then `dropFirst()`), which would handle `=` in values correctly, creating inconsistent behavior.

**Impact:**
- API keys or other secrets containing `=` would be silently dropped by the main parser but accepted by the transcriber parsers, leading to confusing partial failures.
- Silent failure makes debugging difficult.

**Remediation:**
- Split on the first `=` only: `components(separatedBy: "=")` followed by joining the rest.
- Consolidate into a single shared `.env` parser.

---

### MED-12: Test Code Writes to Predictable /tmp Paths

**Severity:** Medium
**File:** `tests/test-audio-collector/main.swift:52-53`
**Category:** File I/O Security

**Description:**
The test executable writes audio chunks to predictable paths (`/tmp/audio_chunk_1.pcm`, etc.) without checking for symlinks or existing files.

**Impact:**
- On a multi-user system, a symlink attack could redirect writes to arbitrary files.
- This is test-only code, but the executables are defined as products in `Package.swift` and could be built/run by any user of the repository.

**Remediation:**
- Use `FileManager.default.temporaryDirectory` with a unique subdirectory.
- Check for symlinks before writing, or use `O_NOFOLLOW` semantics.

---

## Dependency Analysis

### Direct Dependencies

| Package | Pinned Version | Resolved Version | Latest Available | Maintainer |
|---------|---------------|-----------------|-----------------|------------|
| KeyboardShortcuts | exact: 1.8.0 | 1.8.0 | **2.4.0** | sindresorhus (~2,600 stars, 35 contributors) |
| WhisperKit | from: 0.13.0 | 0.13.1 | **0.15.0** | argmaxinc (~5,700 stars, company-backed) |
| FluidAudio | from: 0.7.9 | 0.10.1 | 0.10.1 | FluidInference (newer org, ~7 months active) |

### Transitive Dependencies

| Package | Version | Maintainer | Risk |
|---------|---------|------------|------|
| swift-argument-parser | 1.6.1 | Apple | Low |
| swift-collections | 1.2.1 | Apple | Low |
| swift-transformers | 0.1.15 | HuggingFace | Low |
| Jinja | 1.2.4 | johnmai-dev | Low |

### CVE and Advisory Status

**No known CVEs or GitHub Security Advisories** were found for any direct or transitive dependency at the time of this review.

Note: The Python `transformers` and `Jinja2` libraries have known CVEs, but the Swift packages (`swift-transformers` and `Jinja`) are entirely separate codebases and are not affected.

### Version Currency Concerns

**KeyboardShortcuts is significantly outdated:** Pinned at v1.8.0, which is 6+ minor versions and 1 major version behind the latest (v2.4.0). The `exact:` constraint prevents receiving any bug fixes or security patches for the v1.x line.

**WhisperKit is slightly outdated:** Resolved to v0.13.1 vs latest v0.15.0. Note: v0.15.0 contains a breaking change (`TranscriptionResult` changed from struct to class). No security-related changes were identified in the missed versions.

### Supply Chain Risk: FluidAudio Binary Dependencies

**FluidAudio represents the highest supply chain risk** among all dependencies:

1. **Binary-only targets (xcframeworks):** FluidAudio includes pre-compiled binary frameworks that cannot be source-audited. The compiled ML inference code runs with the same privileges as the host application.
2. **Newer organization:** FluidInference has been active for ~7 months with 34 releases (roughly weekly). While actively maintained, it has less community scrutiny than established projects.
3. **No formal security policy:** No `SECURITY.md` or vulnerability disclosure process was found.
4. **Rapid release cadence:** Weekly releases leave less time for community review of each version.

### SPM Ecosystem Risks

- **No package signing:** Swift Package Manager does not currently enforce package signing or provenance verification.
- **No built-in SBOM support:** SPM lacks Software Bill of Materials generation (in-development as of FOSDEM 2026).
- **GitHub Advisory support:** Since June 2023, GitHub's Advisory Database supports Swift advisories via `Package.resolved`, enabling Dependabot alerts.

### Recommendations

- **Enable GitHub Dependabot** for automated vulnerability alerts on Swift dependencies.
- **Evaluate KeyboardShortcuts v2.x upgrade** to receive accumulated bug fixes and improvements.
- **Assess FluidAudio binary risk:** Verify xcframework checksums match expected values; monitor the FluidInference organization for security disclosures.
- **Pin all dependencies to exact versions** for fully reproducible builds.
- The `Jinja` transitive dependency (a Swift template engine) processes template strings and could theoretically be a vector for template injection if user input were passed to it; however, in this codebase it is used internally by WhisperKit and does not process user input.

---

## Positive Security Observations

The following security-positive patterns were observed:

1. **`.env` excluded from git:** The `.gitignore` file properly excludes `.env`, preventing accidental credential commits.
2. **No command injection in ffmpeg:** The `ScreenRecorder` uses `Process()` with an `arguments` array rather than shell string interpolation, preventing command injection.
3. **Audio buffer size limits:** Both recording managers enforce a 5-minute maximum buffer (16000 * 300 samples) to prevent memory exhaustion.
4. **HTTPS/WSS for all API calls:** All external API communication uses encrypted transport.
5. **Weak references in delegates:** Delegate patterns use `weak` references to prevent retain cycles and potential memory leaks.
6. **Recording mutual exclusion:** The app prevents simultaneous audio/screen recordings, avoiding resource conflicts.
7. **Graceful ffmpeg shutdown:** Screen recording uses SIGINT for graceful ffmpeg termination with a timeout fallback.
8. **Escape key cancellation:** Recording can be cancelled via Escape key, with proper cleanup of monitors and buffers.

---

## Summary of Recommendations (Prioritized)

### High Priority
1. **Fix JSON string construction** in `GeminiAudioCollector.swift` to use proper JSON serialization (HIGH-1).

### Medium Priority
2. **Reduce sensitive data in logs** - remove or redact transcription text and API responses from `print()` statements (MED-1, MED-10).
3. **Consolidate and fix .env parsing** - single shared parser, load from fixed path, split on first `=` only (MED-4, MED-11).
4. **Restrict file permissions** on transcription history and stats files to 0600 (MED-2).
5. **Clear audio buffers** immediately after transcription completes (MED-9).
6. **Use temporary directory** for screen recordings instead of Desktop (MED-6).

### Lower Priority
7. Consider adding optional paste confirmation (MED-5).
8. Improve clipboard save/restore robustness (MED-8).
9. Pin all dependency versions for reproducibility.
10. Document the auto-paste behavior and cloud data transmission for user awareness.
