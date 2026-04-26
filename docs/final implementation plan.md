# RiskGuard Final Implementation Plan

## 2026-03-31 Progress Note

- call companion upgrade is in active implementation: compact top-biased panel, drag support, and improved waveform/status presentation are now part of the current code wave
- dominant-media capture heuristics have been tightened for chat/feed/viewer apps so the overlay is less likely to present a whole-screen crop as if it were the true media target
- bubble/call overlay movement handling has been refined on the Flutter side, but final behavior still requires device verification
- the Intelligence Center world-map presentation has been upgraded again toward a more professional cyber-map style with network links and regional labeling
- remaining gate before calling this production-ready: local build plus on-device validation across WhatsApp, Instagram, gallery, browser, and call flows

## Summary

- Create a new master document at `docs/final implementation plan.md` that merges the existing realtime-hardening plan and the Intelligence Center privacy/UI plan; keep `docs/upgrade implementation plan.md` as historical context.
- Implement one coordinated upgrade wave across Android native services, Flutter realtime runtime, overlay rendering, backend contracts, and the Intelligence Center.
- The target outcome is a deterministic realtime system that:
  - turns on and off instantly and correctly
  - stays active after the app UI is closed
  - remains responsive on 3-4 GB RAM devices
  - handles multiple events without stale overlay state
  - exposes only privacy-safe deepfake intelligence in the map and terminal

## Implementation Changes

### 1. Documentation deliverables and execution order

- First step of execution:
  - create `docs/final implementation plan.md` as the merged master spec
- Final step of execution:
  - create `docs/IMPROVED_SYSTEMS.md` as the engineering report with:
    - before/after behavior
    - subsystem changes
    - measured improvements
    - runtime flow
    - known platform limits
    - verification results
- Execution order:
  1. state/runtime contract
  2. native event queue and background persistence
  3. overlay and toggle responsiveness
  4. backend contract fixes and latency controls
  5. call companion mode
  6. Intelligence Center privacy and UI refinement
  7. verification and engineering report

### 2. Realtime runtime, master toggle, and app-close persistence

- Replace the current boolean toggle behavior with a runtime state machine:
  - `off`
  - `starting`
  - `active`
  - `degraded`
  - `stopping`
- Track four independent truths:
  - `desiredEnabled`
  - `permissionsReady`
  - `nativeServicesRunning`
  - `overlayRuntimeReady`
- Toggle-on behavior:
  - persist `desiredEnabled=true` immediately
  - sync whitelist and feature flags to native immediately
  - start native foreground service immediately
  - mark runtime `active` once native service health is confirmed
  - do not block protection activation on overlay visibility
- Toggle-off behavior:
  - persist `desiredEnabled=false` immediately
  - stop new event intake
  - drain or expire queued work
  - stop foreground service and close overlay runtime
  - remove all user-visible realtime UI
- Repeated toggles must be idempotent:
  - no duplicate start calls
  - no duplicate notifications
  - no stuck `starting` state
  - no stale `0`/black-screen overlay artifacts
- App-close behavior:
  - closing the Flutter activity or removing the task must not disable protection
  - native protection remains active while `desiredEnabled=true`
  - reopening the app must rehydrate current state instead of restarting from scratch

### 3. Native event transport and concurrency

- Replace the current single-latest SharedPreferences event storage with a bounded persisted queue stored in native preferences as JSON.
- Internal queue schema:
  - `ProtectionEvent { id, kind, targetType, normalizedTarget, sourcePackage, createdAtMs, expiresAtMs, priority, sessionId, status }`
- Event kinds:
  - `url_capture`
  - `call_state`
  - `voice_chunk_status`
  - `overlay_status`
- Queue rules:
  - max 24 pending events
  - dedupe identical URL captures within 6 seconds
  - call-state events preempt URL events
  - URL events older than 8 seconds may finish in cache/history but cannot reclaim the overlay
- Ownership rules:
  - the newest valid event owns the visible overlay
  - older analyses are not cancelled, but their late results cannot overwrite the current visible target
- Activity independence:
  - native services and overlay runtime must function without `MainActivity` being alive
  - Flutter activity receives events opportunistically, but queue delivery is the source of truth
- Keep the current native foreground-service architecture; do not migrate this wave to WorkManager or default-dialer ownership

### 4. Accessibility capture, overlay truthfulness, and low-end performance

- Accessibility service must emit only supported realtime targets:
  - explicit URLs
  - browser address-bar domains
  - domains with path/query
  - future media targets only when a real extractor exists
- Explicitly reject:
  - usernames
  - handles
  - captions
  - random dotted text
  - decorative labels
- Overlay stages:
  - `captured`
  - `normalizing`
  - `offline_precheck`
  - `cloud_verifying`
  - `verdict_ready`
  - `degraded_offline`
- Overlay card must always display:
  - source app
  - target type
  - normalized target
  - verdict
  - risk score
  - threat class
  - intelligence source
  - recommendation
- Visibility rules:
  - bubble/card visible only for whitelisted apps, active call companion mode, or unresolved high-priority verdict display
  - hidden on launcher and non-whitelisted apps while background monitoring continues
- Performance rules for low-end devices:
  - adaptive overlay polling:
    - 150-250 ms while visible and active
    - 1200-1500 ms while idle
  - no repeated resize calls unless surface type changes
  - retain only 30 recent overlay entries in memory
  - retain only 2-minute verdict cache for normalized URLs
- Latency budgets:
  - capture-to-card: <= 250 ms
  - offline verdict target: <= 1 s
  - cloud verdict target: <= 3 s
- Degraded behavior must be honest:
  - if cloud misses deadline, show offline/degraded state without freezing the UI

### 5. Backend contract fixes and scale-readiness

- Standardize the URL verdict contract between backend and Flutter.
- During rollout, frontend must accept both old and new keys, but final target contract is:
  - `url`
  - `status`
  - `riskScore`
  - `threatType`
  - `intelligenceSource`
  - `recommendation`
  - `requestId`
  - `latencyMs`
  - `cacheHit`
- Fix the current snake_case vs camelCase mismatch so overlay verdicts stop falling back to empty or placeholder values.
- Add backend URL-verification cache with short TTL and deadline-bounded third-party lookups.
- Scale guards:
  - every realtime request carries `requestId`
  - bounded retries only
  - no duplicate verification storm for repeated identical targets
- Voice realtime path:
  - local/offline path provides immediate UI state
  - cloud enrichment updates the result only if it arrives within deadline
- Keep backend aggregation efficient enough for multiple concurrent users without changing unrelated APIs.

### 6. Call companion mode

- Implement full-screen companion mode, not default dialer replacement.
- Entry conditions:
  - `RINGING` and `OFFHOOK` open the companion immediately
  - `IDLE` closes it cleanly back to idle/bubble-hidden state
- The companion UI must look like a professional phone screen with embedded RiskGuard analysis.
- Required visible sections:
  - caller identity block
  - call state block
  - realtime voice-analysis block
  - confidence/probability block
  - system action row
- Controls:
  - answer/end where Android permissions allow
  - mute/speaker where reliable
  - keypad/hold/merge route to native in-call UI if direct control is not reliable on the device
- Non-negotiable rendering constraints:
  - no black screen
  - no partial-card fullscreen mismatch
  - no stray text or lone numeric overlays
  - no rapid surface thrashing between card and fullscreen

### 7. Intelligence Center: deepfake-only, privacy-safe, professional UI

- Intelligence Center scope becomes deepfake-only for customer-visible UI.
- Allowed terminal/map threat classes:
  - `deepfake_image`
  - `deepfake_video`
  - `synthetic_voice`
  - `voice_clone`
- Excluded from terminal and map:
  - usernames
  - phone numbers
  - raw captions/messages
  - full URLs
  - file names
  - exact user coordinates
  - device identifiers
- Use sanitized intelligence event payloads only:
  - `eventId`
  - `timestamp`
  - `region`
  - `cityOrZoneLabel`
  - `threatClass`
  - `mediaType`
  - `severity`
  - `confidenceBand`
  - `analysisSource`
  - `artifactSummary`
- Privacy rule:
  - if fewer than 3 qualifying events exist in a city bucket, collapse the hotspot to region level
- Map behavior:
  - render only real aggregated backend deepfake hotspots
  - no random hotspot jitter
  - no fabricated user-visible telemetry
  - professional cyber-command styling with restrained motion
- Terminal behavior:
  - monospace terminal layout
  - one stable row format
  - only deepfake telemetry
  - no personal data
  - no phishing-only rows
- Empty state policy:
  - if no verified deepfake telemetry exists, show professional standby state instead of fake events
- Lifecycle:
  - refresh once on open
  - refresh every 60 seconds only while visible
  - stop polling and heavy animation while hidden
  - force refresh on reopen

## Public/Internal Interface Changes

- Flutter runtime adds:
  - `ProtectionRuntimeState`
  - `desiredEnabled`
  - `isDegraded`
  - `activeForegroundSource`
  - `lastProtectionError`
- Native layer adds persisted `ProtectionEvent` queue with ack and expiry metadata.
- `verify-url` moves to a stable verdict contract with backward-compatible parsing during rollout.
- Intelligence endpoints support deepfake-only scoped retrieval:
  - `GET /api/v1/intel/global-feed?scope=deepfake`
  - `GET /api/v1/intel/risk-map?scope=deepfake`
- Customer-visible intelligence payloads become sanitized and aggregated by design.

## Test Plan

- Toggle stability:
  - toggle realtime protection on/off 20 times consecutively with no stuck state, duplicate notification, or crash
- Background persistence:
  - enable protection, close the app task, open a whitelisted app, and confirm capture still works
- Whitelist gating:
  - bubble hidden on launcher/non-whitelisted apps, visible only when rules allow
- Stale-target handling:
  - move rapidly between WhatsApp, Instagram, and Chrome; overlay must follow the newest valid target only
- URL verdict truthfulness:
  - verify one safe and one malicious URL; result fields must be populated correctly and consistently
- Low-end device profile:
  - 30 minute mixed-use run on constrained memory profile with no ANR, no crash loop, and no sustained jank
- Call companion:
  - incoming, answered, rejected, missed, outgoing, ended
  - no black screen or orphan overlay artifact in any path
- Intelligence privacy:
  - terminal and map never expose personal data, full URLs, or exact user coordinates
- Intelligence scope:
  - phishing-only events do not appear in customer-visible terminal/map
- Intelligence lifecycle:
  - polling pauses while hidden and resumes on reopen
- Backend load:
  - burst repeated URL captures from one device and concurrent users without queue corruption or duplicate storms

## Assumptions and Defaults

- The merged master plan file path is `docs/final implementation plan.md`.
- `docs/upgrade implementation plan.md` remains as history and is not the new source of truth after this wave starts.
- `docs/IMPROVED_SYSTEMS.md` is the engineering report produced after implementation and verification.
- Companion call mode is the target for this wave; RiskGuard does not become the default dialer.
- Unsupported dialer controls on restricted OEM devices must deep-link to the native in-call UI rather than expose broken fake controls.
- Customer-visible Intelligence Center data is deepfake-only and privacy-safe by default.

---

## Implementation Progress Update

Updated on: 2026-03-24 00:00:00 +05:30

### Completed In This Execution Wave

1. Native accessibility visibility handling now emits hidden-state updates for launcher, system UI, keyboard, and RiskGuard screens instead of returning early.
2. Native whitelist behavior is now strict. If an app is not explicitly whitelisted, bubble visibility and realtime capture do not surface there.
3. The realtime toggle inside the security modal no longer closes the modal and now reflects provider state while the sheet remains open.
4. Realtime provider shutdown now closes the overlay runtime before stopping the foreground service.
5. Overlay rendering now uses session ownership instead of sticky bubble state, with explicit separation between URL, media, and call sessions.
6. Call-session teardown now clears on `IDLE` and no longer leaves the previous call result floating above WhatsApp, Intelligence, or the launcher.
7. The Intelligence Center map renderer was restored toward a fuller cyber-map presentation while keeping the privacy-safe terminal and visible-only polling lifecycle.

### Remaining Device Validation

- repeated toggle on/off testing from both settings entry points
- whitelist-only bubble confirmation on the target device
- call overlay visual quality and teardown timing on real incoming and outgoing calls
- rapid app switching with stale-result suppression
- low-end device smoothness and crash resistance over sustained usage

---

## Realtime UI Recovery Update

Updated on: 2026-03-24 12:10:00 +05:30

### Follow-Up Scope

- stabilize bubble interaction and centered expansion
- keep bubble movement user-controlled
- prevent manual analysis payloads from contaminating live call state
- reduce call overlay intrusion while keeping the hybrid companion model
- improve the Intelligence world map renderer again

### Follow-Up Implementation Notes

1. Bubble collapse no longer blocks re-expansion. The overlay now stores a collapsible-session marker that still permits direct reopen when the user taps the bubble.
2. Bubble drag and deterministic repositioning are now part of the overlay runtime behavior. Centered card expansion and bottom-anchored call companion placement are driven explicitly through overlay move operations.
3. The overlay runtime no longer uses right-side gravity for post-drag placement, which allows the bubble to remain where the user leaves it.
4. The manual analysis surfaces now publish typed media payloads so voice/image/video/text scans from in-app tools do not impersonate realtime phone-call sessions.
5. The hybrid call companion now uses a smaller bottom-centered surface instead of a broad full-screen overlay window.
6. The map renderer now uses denser continent geometry instead of simplified placeholder-like land shapes.

### Still Not Solved By UI Stabilization Alone

- The codebase still lacks a real live screen-media capture producer. URL and call events are emitted natively today, but visible image/video screen content still requires new capture infrastructure before the overlay can show trustworthy realtime media verdicts.

---

## Realtime Media Capture Foundation Update

Updated on: 2026-03-26 00:00:00 +05:30

### Implemented In This Slice

1. Added a native MediaProjection-based screen capture service as the first truthful producer for visible screen-media analysis.
2. Extended the native bridge with methods to:
   - request screen-capture permission
   - check active capture state
   - request a live frame capture
   - stop the capture service
3. Extended native event persistence with a `media_result` path for captured frames.
4. Updated the accessibility service to request throttled frame captures for whitelisted apps when MediaProjection is active.
5. Updated the overlay reducer to:
   - consume captured frame events
   - analyze the frame through the existing image-analysis backend
   - keep media-session ownership stable while analysis is in progress
   - retain a preview of the current analyzed frame in the bubble/card UI
6. Updated bubble behavior with:
   - drag persistence
   - edge snap
   - delayed hidden-state handling to reduce flicker from transient system events
7. Moved the call companion toward a smaller centered floating layout instead of a larger bottom-anchored presentation.

### Status After This Slice

- realtime URL flow: implemented
- realtime call-state flow: implemented
- realtime visible-screen media capture: implemented as sampled frame capture
- realtime visible-screen media verdict path: wired to backend through the image-analysis API
- full build/runtime verification for this slice: pending local confirmation

### Remaining Risks Before Calling This Production-Ready

- this slice still needs local compile confirmation after the new Android service and overlay changes
- scrolling-heavy apps may still need additional tuning after device validation
- current media analysis is sampled-frame based, not full continuous video-stream classification
- Android platform limits for remote call audio still remain outside this slice
