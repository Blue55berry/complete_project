# RiskGuard Realtime Media Capture Implementation Plan

Updated on: 2026-03-24 16:20:00 +05:30

## Objective

Build a production-grade realtime detection pipeline for:

- visible URLs and text on screen
- visible images on screen
- visible video on screen
- capturable media audio on screen
- call-state intelligence without leaking stale overlay state

The target outcome is a realtime system that:

- reacts within a usable latency budget on 3-4 GB RAM devices
- preserves overlay correctness during rapid app switching
- keeps the UI honest about what is actually being analyzed
- avoids exposing personal user data in Intelligence Center
- scales to multiple users without backend contract drift

## Current Truth

The current codebase has a partial realtime pipeline:

- URL extraction exists through Accessibility.
- Call-state detection exists through telephony listeners.
- Overlay session ownership is now more stable.
- Live visible image/video screen analysis does not exist yet.
- Live media-audio capture does not exist yet.

That means the bubble can be made correct and responsive, but it cannot truthfully claim full live image/video/audio analysis until the missing capture producers are implemented.

## Platform Constraints That Must Shape The Design

This plan is based on current official Android platform behavior:

- `MediaProjection` is the supported API for capturing screen contents. User consent is required for each projection session. On Android 14+, the projection token is effectively one-time for `createVirtualDisplay()`. Source: [Media projection](https://developer.android.com/media/grow/media-projection), [MediaProjection API](https://developer.android.com/reference/android/media/projection/MediaProjection)
- Audio playback capture is supported from Android 10+ through `AudioPlaybackCaptureConfiguration`, but only for apps/usages that allow capture. Source: [Capture video and audio playback](https://developer.android.com/media/platform/av-capture), [AudioPlaybackCaptureConfiguration](https://developer.android.com/reference/android/media/AudioPlaybackCaptureConfiguration)
- Ordinary apps cannot promise full phone-call audio capture on stock Android. Official guidance is that the call always receives audio, and voice-call capture is limited to accessibility/privileged paths, with full call-audio capture requiring privileged capability such as `CAPTURE_AUDIO_OUTPUT`. Source: [Sharing audio input](https://developer.android.com/media/platform/sharing-audio-input)
- A true native in-call replacement UI is an `InCallService` / default dialer path, not a generic overlay. Source: [InCallService](https://developer.android.com/reference/android/telecom/InCallService)

## Product Definition

RiskGuard realtime must be defined as four distinct lanes:

### 1. URL/Text Lane

Supported now and should be hardened further.

- detect browser address bars, explicit URLs, capturable domains, and high-signal text
- verify fast with local precheck and backend enrichment
- show truthful source app, target, score, and recommendation

### 2. Visual Lane

New implementation required.

- capture visible screen frames from whitelisted apps using `MediaProjection`
- detect whether the visible content is a static image, moving video, or non-media UI
- downsample and analyze only selected frames/crops
- emit truthful image/video deepfake verdicts into the overlay

### 3. Audio Lane

New implementation required with platform-aware scope.

- support media playback audio capture where Android allows it
- support mic/local recorded voice analysis in manual flows
- do not falsely claim arbitrary third-party app audio capture when the app or OS does not permit it
- do not falsely claim full remote call-audio deepfake analysis on stock Android unless a privileged/default-dialer path is actually implemented

### 4. Call Lane

Must remain hybrid unless the product explicitly becomes the default dialer.

- maintain caller identity, call state, and companion analysis UI
- clear immediately on `IDLE`
- integrate supported analysis signals without pretending to own unsupported native controls

## Architecture

## A. Native Realtime Stack

### 1. Realtime Orchestrator Service

Create a single Android-side orchestrator owned by the foreground service.

Responsibilities:

- start and stop capture subsystems
- own realtime session lifecycle
- track health of:
  - accessibility lane
  - media projection lane
  - audio playback lane
  - overlay runtime
- gate all capture by:
  - `desiredEnabled`
  - whitelist package
  - active consent state
  - device capability

### 2. Capture Session Manager

Add a typed native session model:

`CaptureSession { id, kind, sourcePackage, startedAtMs, projectionState, audioState, ownerPriority, uiEligibility }`

Kinds:

- `url`
- `text`
- `image`
- `video`
- `media_audio`
- `call`

Rules:

- newest valid session owns overlay
- call preempts all others
- stale results can be recorded but not repaint the current session
- sessions expire aggressively when foreground context changes

### 3. MediaProjection Manager

Implement a dedicated Android manager for screen capture.

Responsibilities:

- request and store user consent state for the current projection session
- start projection only when:
  - realtime is enabled
  - a whitelisted app is foregrounded
  - no capture session is already active for that package
- create a virtual display surface
- feed frames to a throttled frame sampler
- tear down immediately when:
  - user leaves whitelisted context
  - token is revoked
  - app disables realtime protection

Important:

- on Android 14+, do not try to reuse tokens or create multiple virtual displays from the same token
- projection must be treated as a session resource, not a static permission

### 4. Frame Sampler And Visual Prefilter

Implement a low-cost on-device visual prefilter before backend calls.

Responsibilities:

- read screen frames at adaptive rates:
  - static image candidate: 0.5 to 1 fps
  - moving video candidate: 1 to 3 fps on low-end devices
  - idle/non-media UI: 0 fps, keep suspended
- detect:
  - motion level
  - face presence
  - text density
  - aspect-ratio blocks typical of video players
  - repeated frames
- only forward candidates that pass heuristics

Required output:

`FrameCaptureEvent { sessionId, sourcePackage, mediaTypeGuess, frameHash, timestampMs, cropRects, downsampledBytes }`

### 5. OCR And On-Screen URL/Text Fusion

Do not rely on Accessibility alone for visual text/URL capture.

Add an OCR fusion path:

- use Accessibility first when available
- use OCR on MediaProjection frames when Accessibility data is weak or absent
- merge duplicate targets with confidence ranking

This gives coverage for:

- browser URLs
- link previews in apps
- phishing text embedded in images or video frames

### 6. Audio Playback Capture Engine

Implement only where the platform supports it.

Responsibilities:

- acquire audio-capable `MediaProjection`
- configure `AudioPlaybackCaptureConfiguration`
- limit capture to `USAGE_MEDIA` and other supported usages where appropriate
- treat uncapturable apps as unsupported, not as silent success
- emit small analysis chunks, for example 1.0 to 1.5 second windows

Required output:

`AudioChunkEvent { sessionId, sourcePackage, chunkIndex, durationMs, sampleRate, pcmBytes }`

### 7. Call Intelligence Path

Keep call logic separate from general media playback capture.

Stock-Android plan:

- keep call-state detection through telephony
- keep hybrid companion UI
- optionally analyze:
  - caller metadata
  - user-side microphone samples in allowed flows
  - previously captured or user-approved voice samples

Do not define success as full remote-call audio capture unless the product later adopts a privileged/default-dialer architecture.

## B. Flutter Runtime And Overlay

### 8. Unified Realtime Event Contract

Replace ad hoc payloads with one stable contract:

`RealtimeAnalysisEvent {`
`  sessionId,`
`  sessionKind,`
`  sourcePackage,`
`  targetType,`
`  targetLabel,`
`  captureState,`
`  analysisState,`
`  score,`
`  threatType,`
`  recommendation,`
`  analysisSource,`
`  requestId,`
`  timestampMs`
`}`

Capture states:

- `detected`
- `sampling`
- `queued`
- `analyzing`
- `ready`
- `degraded`
- `dismissed`

### 9. Overlay Behavior

The overlay must stay truthful and deterministic.

Rules:

- bubble is visible only in whitelisted apps or live call sessions
- bubble tap expands to center for URL/text/image/video sessions
- call companion opens as a bottom-centered hybrid panel
- bubble position is user-controlled and restored after minimize
- overlay must not say it is analyzing `image` or `video` unless a real visual capture session exists
- overlay must not keep stale `CALL ENDED` or old target state after ownership changes

### 10. Overlay Content Model

For each supported realtime lane, the overlay must show:

- source app
- detected media type
- captured target label
- stage
- current risk score or `pending`
- model source:
  - local
  - backend
  - hybrid
- recommendation

## C. Backend Realtime Pipeline

### 11. Realtime API Surface

Add explicit endpoints for realtime ingestion.

Suggested endpoints:

- `POST /api/v1/realtime/url/verify`
- `POST /api/v1/realtime/frame/analyze`
- `POST /api/v1/realtime/audio/analyze`
- `POST /api/v1/realtime/batch/submit`

Each request must include:

- `requestId`
- `sessionId`
- `sourcePackage`
- `targetType`
- `capturedAtMs`
- `deadlineMs`

Each response must include:

- `requestId`
- `sessionId`
- `status`
- `riskScore`
- `threatType`
- `recommendation`
- `analysisSource`
- `latencyMs`
- `cacheHit`

### 12. Backend Processing Rules

Backend must be deadline-aware.

Rules:

- URL verification:
  - local cache first
  - threat feed lookup bounded by deadline
- frame analysis:
  - dedupe by frame hash
  - skip repeated frames
  - batch nearby frames from the same session
- audio analysis:
  - aggregate chunk-level verdicts into rolling confidence
  - return partials fast

### 13. Model Integration Strategy

The backend should adopt a two-stage path:

- Stage 1:
  - lightweight filters
  - cache lookups
  - fast heuristics
- Stage 2:
  - expensive deepfake models only for promoted candidates

This is the correct place to integrate later TF/TFLite-backed or server-side deepfake models.

## Performance Budgets

Target budgets for low-end Android devices:

- whitelist app entry to bubble visible: <= 150 ms
- first URL/text candidate surfaced: <= 300 ms
- local URL precheck verdict: <= 700 ms
- cloud URL verdict target: <= 2500 ms
- frame prefilter per accepted frame: <= 120 ms
- first visual candidate decision: <= 1000 ms
- audio chunk partial verdict: <= 1500 ms after chunk close
- overlay repaint after event ownership change: <= 120 ms

Low-end guardrails:

- max one active visual analysis session
- max two queued frame batches
- aggressive stale-drop on app switch
- downsample frames before backend upload
- disable nonessential overlay animation under load

## Privacy And Security

The plan must preserve privacy by design.

Rules:

- no raw user frames stored long-term by default
- no personal data sent to Intelligence Center
- only aggregated deepfake telemetry reaches map/terminal
- raw capture artifacts use TTL and secure deletion
- MediaProjection consent state must be explicit in UI
- token revocation must immediately stop capture and surface a clear status

## Rollout Plan

### Phase 1. Capture Foundation

- add MediaProjection session flow
- add audio playback capture flow
- add native capture session manager
- add projection-health reporting into Flutter

Exit criteria:

- projection starts and stops correctly
- token revocation handled correctly
- no crash loops after app close or whitelist transitions

### Phase 2. Visual Realtime Producer

- implement frame sampler
- implement OCR fusion
- implement image/video candidate classifier
- emit `image` and `video` session events to overlay

Exit criteria:

- realtime overlay can truthfully show visible image/video sessions
- stale frames do not repaint after app switching

### Phase 3. Backend Realtime Endpoints

- implement frame/audio realtime endpoints
- add request IDs, deadlines, caches, and dedupe
- normalize all verdict contracts

Exit criteria:

- stable partial/final verdict responses
- no contract mismatch between app and backend

### Phase 4. Overlay And UX Hardening

- refine centered card expansion
- finalize bottom-anchored call companion
- add truthful capture-stage labels
- add unsupported-state UI for uncapturable audio/media

Exit criteria:

- no fake analysis state
- no stale call state
- no bubble visibility outside whitelist rules

### Phase 5. Device Validation

Test matrix:

- 3-4 GB RAM Android device
- Android 10+
- Chrome, WhatsApp, Telegram, Instagram, gallery/video player
- incoming call, outgoing call, call end, rapid app switching

Acceptance criteria:

- no ANR
- no crash loop
- no stale overlay ownership
- honest unsupported states
- backend verdicts match UI state

## Definition Of Done

The realtime media system is only considered complete when all of the following are true:

- URL/text realtime works across supported whitelisted apps
- visible image/video screen analysis is backed by a real MediaProjection capture path
- media audio analysis works only where Android explicitly allows it, and unsupported apps are labeled honestly
- call overlay behaves correctly without stale state
- overlay ownership is deterministic during rapid app switching
- backend returns stable realtime verdict contracts
- Intelligence Center remains privacy-safe
- 3-4 GB RAM devices sustain extended use without app collapse

## Explicit Non-Lies

The product must not claim these unless they are actually implemented:

- full live image/video deepfake analysis without a MediaProjection producer
- full remote call-audio deepfake analysis on ordinary stock Android
- full native dialer replacement behavior while still using only an overlay-based call companion

## Recommended Next Execution Step

Implement Phase 1 first:

- Android `MediaProjection` manager
- native capture session manager
- audio playback capture capability detection
- Flutter runtime health state for projection/audio capture

That is the minimum missing foundation required before live image/video/audio realtime can be truthfully completed.
