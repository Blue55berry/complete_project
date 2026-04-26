# Improved Systems

## 2026-03-31 Realtime Companion Upgrade

This timestamped wave extends the earlier stabilization work and focuses on the user-facing realtime companion behavior that still felt unfinished on device.

Implemented in this wave:

- made the expanded call companion draggable and moved its default anchor higher on screen so it interferes less with the native call controls
- tightened the minimized call chip interaction so drag and tap-to-expand no longer fight each other as aggressively
- redesigned the expanded call companion into a more compact top-biased panel with a stronger live waveform and cleaner scoring/status layout
- added stronger stale-session cleanup when leaving a monitored app so old media or call state is less likely to leak into unrelated screens
- upgraded the media preview card to show more context about the current selected target and selection confidence
- tightened the native `MediaProjection` selector so chat/feed apps are more likely to choose dominant visible media windows and more likely to fall back honestly when a broad crop is not trustworthy
- refined the Intelligence Center map with labeled regions, cyber-style network links, and stronger vector-like global presentation while keeping the terminal privacy-safe

Current engineering truth:

- the overlay movement/placement work is implemented in the client UI
- the dominant-media selector is improved, but it is still heuristic-based and still needs device-side validation against WhatsApp, Instagram, gallery viewers, and browser pages
- the waveform is a lightweight live activity visualizer, not a true call-audio amplitude meter yet
- full production readiness for realtime media still depends on device verification, because this sandbox could not complete a full Flutter/Gradle validation pass

Validation limits in this environment:

- `flutter analyze` timed out repeatedly in the sandbox before returning a result
- Gradle Kotlin compilation was blocked by the local wrapper/dist environment here
- because of those limits, the final truth for this wave still needs to come from a local APK build and on-device interaction tests

## Scope

This document records the implementation wave that upgraded RiskGuard realtime protection, native event delivery, overlay behavior, backend intelligence contracts, and the Intelligence Center UI.

The work focused on:

- deterministic realtime toggle behavior
- background persistence after the app UI closes
- stale-event prevention for overlay ownership
- truthful URL-verdict rendering
- privacy-safe deepfake-only intelligence telemetry
- lower idle overhead for constrained devices

## What Changed

### 1. Realtime runtime contract

The Flutter realtime runtime no longer treats overlay visibility as the definition of protection being active.

Implemented changes:

- added `ProtectionRuntimeState` with `off`, `starting`, `active`, `degraded`, and `stopping`
- split runtime truth into:
  - desired enabled state
  - permission readiness
  - native foreground-service health
  - overlay runtime readiness
- persisted desired enabled state immediately on toggle
- marked the system as degraded instead of fully failed when the native service starts but the overlay runtime is not yet available
- removed provider-side overlay resize/message thrash during call events

Result:

- the master toggle is now aligned to actual runtime state rather than a single fragile boolean
- turning protection on no longer fails only because the bubble/card did not appear fast enough
- reopening the app rehydrates the runtime instead of acting like a cold start every time

### 2. Native event persistence and service health

The native side previously stored only the latest URL, latest call state, and latest overlay payload. That meant late events could overwrite newer context and the overlay had no bounded backlog to recover from.

Implemented changes:

- added a bounded native JSON event queue in `ProtectionEventStore`
- preserved legacy latest-value keys for compatibility during rollout
- added event types:
  - `url_capture`
  - `call_state`
  - `overlay_status`
- added queue pruning, expiry, and URL dedupe
- added foreground-service running-state persistence
- exposed native service health to Flutter through `isForegroundServiceRunning`

Result:

- realtime events survive activity detachment better
- stale targets are less likely to reclaim the overlay after a newer target appears
- the provider can now distinguish between desired state and actual native service health

### 3. Accessibility and bubble visibility control

The overlay previously had no reliable visibility context about whether the user was inside a monitored app, so the bubble could remain visible outside the intended flow.

Implemented changes:

- the accessibility service now emits overlay visibility events on window changes
- visibility events are derived from the whitelisted package set and ignored-package rules
- launcher/system UI/input-method contexts are explicitly treated as non-overlay contexts

Result:

- the overlay runtime can stay alive in the background while the bubble is hidden
- bubble visibility is now controlled by monitored-app context instead of being permanently on-screen

### 4. Overlay runtime behavior

The overlay was previously fixed to a constant poll interval and single-latest shared-preference keys, which made it prone to stale cards and repeated old targets.

Implemented changes:

- replaced the old single-latest behavior with queue-aware polling
- added hidden idle surface, bubble surface, card surface, and call surface
- changed idle overlay size to a hidden `1x1` window instead of a permanent visible bubble
- added adaptive polling:
  - active UI: 200 ms
  - hidden idle: 1300 ms
- added analysis ownership so late URL-verdict results do not overwrite the currently visible target
- added short-lived auto-dismiss for settled card results
- preserved a 2-minute local URL-verdict cache

Result:

- lower idle overhead on low-end devices
- less stale overlay content while switching apps
- background monitoring can continue without forcing a visible floating icon

### 5. URL-verdict contract alignment

The backend returned snake_case fields while Flutter expected camelCase, which caused the overlay to fall back to zero-score or placeholder-looking states.

Implemented changes:

- backend `verify-url` now returns the stable contract:
  - `url`
  - `status`
  - `riskScore`
  - `threatType`
  - `intelligenceSource`
  - `recommendation`
  - `requestId`
  - `latencyMs`
  - `cacheHit`
- backend also keeps backward-compatible snake_case aliases during rollout
- Flutter `UrlVerificationResult` now accepts both camelCase and snake_case fields
- added short TTL caching on the backend URL-verdict path

Result:

- overlay verdict rendering is now based on real returned fields instead of missing-key fallback values
- repeated URL checks are cheaper and more stable

### 6. Intelligence backend

The old intelligence backend mixed real signals with placeholder/randomized visible data. That made the customer-facing map and feed look active even when the telemetry was synthetic.

Implemented changes:

- removed randomized customer-visible baseline threat generation
- restricted customer-visible intelligence to deepfake-related classes only:
  - `deepfake_image`
  - `deepfake_video`
  - `synthetic_voice`
  - `voice_clone`
- sanitized visible feed data so it excludes:
  - usernames
  - phone numbers
  - raw URLs
  - file names
  - exact coordinates
  - device identifiers
- added coarse hotspot aggregation and region fallback when city-level density is too low
- kept `log_analysis(...)` as the ingestion hook for backend analysis endpoints

Result:

- the Intelligence Center now reflects aggregated deepfake telemetry only
- user-visible data is privacy-safe by design
- empty telemetry windows remain honest instead of being filled with fabricated events

### 7. Intelligence Center UI

The previous screen used a heavy screen with placeholder-like content paths and permanent refresh behavior.

Implemented changes:

- rebuilt the screen as a focused two-panel layout:
  - world map with aggregated hotspots
  - terminal feed with sanitized deepfake telemetry rows
- added provider-controlled attach/detach polling
- refresh now occurs:
  - once on screen open
  - every 60 seconds while visible
  - never while hidden
- terminal rows now show:
  - time
  - region
  - threat class
  - severity
  - confidence band
  - analysis source
  - sanitized artifact summary

Result:

- the screen now behaves like a professional threat-intelligence surface instead of a generic dashboard
- hidden-screen polling and animation work is reduced
- the terminal no longer exposes personal or raw source data

## Runtime Flow

### Realtime activation flow

1. User turns on realtime protection.
2. Desired enabled state is persisted immediately.
3. Whitelist and desired protection state sync to native storage.
4. Android prerequisites are checked.
5. Foreground service is started and health is re-read from native state.
6. Overlay runtime is started separately and may succeed or fail independently.
7. Runtime state becomes:
   - `active` if native service and overlay runtime are both healthy
   - `degraded` if native service is healthy but overlay runtime is not
8. Accessibility and phone events continue to feed the native queue even if the main activity is detached.

### URL analysis flow

1. Accessibility detects a valid URL target from a monitored app.
2. Native side stores the latest legacy fields and also appends a queued `url_capture` event.
3. Overlay reads the queue, claims ownership of the newest URL event, and renders the capture state.
4. Overlay performs verification against the backend.
5. If another newer URL appears before the verdict returns, the late verdict is ignored for visible ownership.
6. Final verdict is shown, cached, and auto-dismissed back to bubble or hidden mode based on visibility context.

### Intelligence flow

1. Backend analysis endpoints call `log_analysis(...)` for deepfake detections.
2. Intelligence endpoints aggregate only deepfake-class events for UI exposure.
3. Client requests `scope=deepfake` for both terminal feed and risk map.
4. Provider refreshes once on open and every 60 seconds only while the screen is visible.

## Performance and Stability Impact

Measured values were not available in this sandbox because Flutter formatting/analyzer/build commands timed out and no device-attached logging was available. The architectural improvements that reduce load are:

- hidden idle overlay instead of permanent visible bubble
- adaptive polling rather than fixed high-frequency polling at all times
- bounded queue size and URL dedupe at the native layer
- short TTL verdict caching on both client and backend sides
- paused Intelligence Center polling when the screen is not visible
- removal of placeholder/randomized visible intelligence generation

Expected practical impact:

- lower idle UI overhead on 3-4 GB devices
- fewer stale overlay redraws
- less repeated backend work for identical URLs
- more stable behavior when the app UI is closed but protection is still enabled

## Files Changed

Core runtime and native:

- `frontend/android/app/src/main/kotlin/com/example/risk_guard/ProtectionEventStore.kt`
- `frontend/android/app/src/main/kotlin/com/example/risk_guard/MainActivity.kt`
- `frontend/android/app/src/main/kotlin/com/example/risk_guard/services/RiskGuardAccessibilityService.kt`
- `frontend/android/app/src/main/kotlin/com/example/risk_guard/services/RiskGuardForegroundService.kt`
- `frontend/lib/core/services/native_bridge.dart`
- `frontend/lib/core/services/realtime_protection_provider.dart`

Overlay and models:

- `frontend/lib/screens/overlay/risk_guard_overlay.dart`
- `frontend/lib/core/models/analysis_models.dart`

Backend and intelligence:

- `backend/api/endpoints/intel.py`
- `frontend/lib/core/services/api_service.dart`
- `frontend/lib/core/services/threat_intelligence_provider.dart`
- `frontend/lib/screens/intelligence/threat_intelligence_screen.dart`

Documentation:

- `docs/final implementation plan.md`
- `docs/IMPROVED_SYSTEMS.md`

## Known Limits

- Full Flutter formatting could not be completed in this environment because `dart format` timed out repeatedly.
- Python backend compilation could not be executed here because no local Python runtime was available from the shell.
- No ADB/device log capture was available in this session, so runtime verification on the target phone is still required.
- Companion call mode is improved as an overlay companion, not as a default dialer replacement. System-level dialer controls remain OEM-dependent.

## Required Verification On Device

Run these checks on the rebuilt APK:

1. Toggle realtime protection on and off repeatedly and confirm the switch state, service state, and overlay state remain aligned.
2. Turn protection on, close the app task, then open a whitelisted app and verify capture still occurs.
3. Confirm the bubble is hidden on the launcher and appears only while using whitelisted apps or active call analysis.
4. Trigger rapid URL changes across multiple apps and confirm late verdicts do not replace newer visible targets.
5. Verify safe and malicious URLs both show non-placeholder verdict fields.
6. Open and close the Intelligence Center and confirm polling stops while hidden and resumes on reopen.
7. Confirm the terminal shows only sanitized deepfake telemetry and never raw personal data.

---

## 2026-03-24 Stabilization Addendum

### Additional Improvements Completed

1. Fixed the security-settings realtime toggle so it no longer dismisses the modal during on/off actions.
2. Corrected native overlay visibility handling so launcher, system UI, keyboard, and RiskGuard screens now actively hide the bubble instead of inheriting stale visible state.
3. Tightened native whitelist behavior so non-whitelisted apps do not keep the realtime bubble visible.
4. Changed realtime shutdown order so the overlay closes before the foreground service stops, reducing the "app is closing" perception during toggle-off.
5. Replaced the overlay runtime state handling with a session-oriented path for URL, media, and call ownership.
6. Fixed call teardown so `IDLE` clears the call session instead of leaving a stale `CALL ENDED` card on later screens.
7. Restored a denser cyber-map world renderer for the Intelligence Center while preserving the privacy-safe deepfake-only terminal.

### What These Changes Improve

- bubble visibility now tracks the actual foreground whitelist context more closely
- call analysis no longer owns the overlay after the call has ended
- modal toggles stay interactive instead of collapsing their own UI
- the Intelligence screen regains a stronger professional world-map look

### Validation Still Required

These changes still need rebuilt-APK verification on the target phone because full formatter/analyzer execution was not available in this environment.

---

## 2026-03-24 Realtime UI Recovery Addendum

### Additional Fixes Applied

1. Bubble interaction:
   - fixed re-expansion after minimize
   - preserved user-chosen bubble position
   - added deterministic centered expansion for the analysis card
2. Overlay runtime:
   - removed right-side gravity from the overlay runtime launch path
   - tightened session adoption so generic manual-analysis payloads no longer masquerade as live call state
3. Call companion:
   - changed from an oversized overlay surface to a bottom-centered hybrid companion panel
   - kept native call controls as the primary control path instead of faking unsupported dialer actions
4. Intelligence Center:
   - replaced simplified continent geometry with a denser coast-rendered world map

### Actual Technical Boundary

- The current codebase still does not have a native producer for live visible image/video screen content. That means realtime URL and call flows can be stabilized now, but trustworthy live media-screen analysis still requires a dedicated screen/media capture pipeline before it can be claimed as complete.

### Build Verification

- `flutter build apk --debug --no-pub` completed successfully on 2026-03-24
- `flutter build apk --release --split-per-abi --no-pub` completed successfully on 2026-03-24

---

## 2026-03-26 Realtime Media Capture Foundation Addendum

### Scope of This Slice

This wave did not try to finish the entire realtime product. It focused on adding the missing native capture foundation and stabilizing the overlay UX path that was still causing call-positioning, bubble flicker, and media-session ownership issues.

### Implemented Changes

1. Native MediaProjection foundation:
   - added a dedicated Android service for screen-frame capture
   - added native state persistence for whether MediaProjection is active
   - added native event emission for captured screen frames as `media_result`
   - added Flutter/native bridge methods for:
     - requesting screen-capture permission
     - checking whether screen capture is active
     - requesting a realtime frame capture
     - stopping the capture service

2. Accessibility-driven media capture requests:
   - the accessibility service now requests a frame capture for whitelisted apps on stable window/content changes
   - media capture is throttled with a debounce window so scrolling-heavy apps do not flood the pipeline
   - capture requests are ignored unless protection is active, the app is whitelisted, and MediaProjection is already running

3. Overlay media-session handling:
   - the overlay now consumes real captured-frame events instead of showing only placeholder media states
   - captured frame files are analyzed through the existing image-analysis backend path
   - the active media card now keeps ownership while that frame is being analyzed, so newer transient frame events do not immediately repaint the UI
   - media sessions now keep a preview path so the overlay can show the actual frame being analyzed

4. Bubble and card stability:
   - added a visibility-hide debounce so transient system/launcher/input-method events do not instantly collapse the overlay
   - added surface pinning during user-triggered expansion and media capture startup so the card does not disappear immediately after opening
   - added snap-to-edge behavior when the bubble drag ends
   - kept bubble position persistence while preventing off-screen placement

5. Call companion positioning:
   - moved the call companion away from bottom-sheet anchoring toward a centered floating companion layout
   - reduced call-surface size so the native phone UI remains more visible behind it

### Backend Wiring Status

The current realtime media path is wired to the backend through the existing image-analysis endpoint:

- native screen frame capture -> queued `media_result` event
- Flutter overlay consumes the frame
- Flutter sends the captured frame to the image-analysis backend
- overlay renders a live verdict when the backend returns

This means the backend is now in the loop for realtime visible-screen media analysis. The current implementation is frame-based, not continuous video-stream classification.

### Important Technical Limits

These are still true after this slice:

- realtime URL and call flows remain the most mature paths
- visible image/video analysis is now based on sampled screen frames captured through MediaProjection
- this is not yet a full continuous video-stream detector
- remote call-audio deepfake capture is still limited by Android platform restrictions and is not solved by this slice
- full production validation has not been completed yet because local build and on-device runtime verification were intentionally deferred in this session

### Verification Status

Build verification for this 2026-03-26 slice was intentionally stopped before completion at user request. The code changes were recorded, but compile/runtime validation for this slice still needs to happen locally.

### Required Local Checks For This Slice

1. Confirm the app still builds after the MediaProjection service and bridge additions.
2. Turn realtime protection on and grant screen-capture permission when prompted.
3. Open a whitelisted app with visible media and confirm the bubble remains stable without flickering.
4. Tap the bubble and confirm the expanded card stays centered instead of disappearing immediately.
5. Confirm the expanded card shows a small preview of the captured frame.
6. Confirm the centered call companion no longer blocks the whole lower portion of the native call screen.
7. Confirm captured media frames are actually reaching the backend and returning visible verdicts.
