# RiskGuard Realtime Analysis and Intelligence Upgrade Plan

## Goal

Upgrade only the realtime analysis pipeline, call/link overlay experience, backend connection handling, biometric startup flow, and intelligence system screen so the app feels fast, accurate, and stable on typical Android devices without changing the other tabs or unrelated UI.

## Current Findings

1. The realtime link pipeline is too broad on Android accessibility input, so usernames such as `bts.bighitofficial` are being treated like URLs.
2. The accessibility scan is walking too much UI tree data too often, which can waste RAM and CPU and likely contributes to the "keeps stopping" behavior.
3. The overlay UI now activates, but it does not present the scan result clearly enough. It shows process state, but not a professional result card with source, verdict, score, and recommendation.
4. The call overlay expands in size but still renders like a small centered card instead of a proper full-page call-analysis experience.
5. Backend URL changes are not propagating reliably because the API singleton is caching the old base URL.
6. The intelligence map is still using hardcoded hotspot coordinates instead of backend hotspot data.
7. Biometric authentication is triggered too early in app startup and needs a guarded first-frame launch path.

## Scope Guardrails

- Do not redesign unrelated tabs.
- Do not remove current features.
- Keep local-model and offline-first behavior intact.
- Optimize the app-side response path even when backend analysis is slower.

## Target Product Behavior

### Realtime URL analysis

- Detect only likely real URLs, browser address-bar values, shared links, and explicit domains.
- Ignore social handles, usernames, captions, and random dotted tokens unless they meet strong URL heuristics.
- Show a fast staged response:
  - `captured`
  - `normalizing`
  - `verifying`
  - `safe` or `danger`
- Surface the scanned source clearly:
  - package/app
  - normalized URL
  - status
  - risk score
  - threat type
  - recommendation

### Realtime call analysis

- Expand to a true full-screen call-analysis overlay.
- Keep the call identity area readable and familiar, like a phone UI.
- Display live analysis state, confidence meter, model/source label, and action hints.
- Collapse cleanly back to the floating bubble when the call ends.

### Intelligence system screen

- Drive hotspots from backend `risk-map` data.
- Improve the terminal feed so each row reads like an anonymized security event rather than decorative text.
- Keep user privacy by showing only normalized content summaries, risk class, source type, and region instead of personal data.
- Make the map and feed lightweight enough for lower-end devices.

## Implementation Phases

### Phase 1: Stability and truthfulness

1. Fix dynamic backend URL propagation so every API request uses the latest saved base URL.
2. Normalize backend URLs on save:
   - add `https://` when a Cloudflare tunnel URL is entered without scheme
   - trim trailing slash
3. Make biometric auth launch after the first frame with a single guarded attempt to avoid startup race conditions.
4. Add defensive guards around Android accessibility scanning so one bad event cannot crash the service.

Acceptance:
- Saving a new backend URL updates health checks immediately.
- App launch shows biometric prompt promptly when enabled.
- Accessibility service no longer falls into a "not working" state during normal use.

### Phase 2: Realtime capture accuracy

1. Replace broad URL matching with stricter heuristics:
   - explicit `http://` or `https://`
   - browser address-bar style domains
   - domains with path/query fragments
   - optional package-aware rules for browser and messaging apps
2. Reject obvious false positives:
   - social usernames
   - labels without a valid TLD pattern
   - short dotted tokens without scheme, path, or browser context
3. Reduce scan pressure:
   - event debounce
   - max text length
   - max node budget
   - dedupe cache with TTL

Acceptance:
- Instagram handles are not shown as URLs.
- Real shared links from WhatsApp, Chrome, Telegram, and similar apps still trigger analysis.

### Phase 3: Overlay UX upgrade

1. Introduce a clearer realtime verdict card for link scanning.
2. Show package/source, normalized URL, risk score, severity color, and recommendation.
3. Keep a compact minimized bubble for idle state.
4. Upgrade the call overlay into a full-page experience with:
   - call identity header
   - analysis progress block
   - deepfake probability meter
   - status chips
   - minimize or dismiss action

Acceptance:
- The user can understand what was scanned and why the result is safe or dangerous.
- Call overlay looks intentional and fills the screen properly.

### Phase 4: Intelligence system refinement

1. Replace hardcoded hotspot points with backend `RiskHotspot` data.
2. Add fallback hotspot rendering only if backend data is unavailable.
3. Upgrade the terminal feed rows to show:
   - region
   - category
   - campaign or source type
   - severity
   - short anonymized description
4. Keep animation subtle so the screen remains smooth.

Acceptance:
- Map points move with backend data.
- Feed reads like live security telemetry, not placeholder text.

### Phase 5: Performance protection for low-end devices

1. Add local throttling for repeated URL verifications.
2. Cache recently verified URLs to avoid repeated backend calls from the same content.
3. Reduce overlay polling frequency and avoid redundant resize calls.
4. Prefer optimistic UI states immediately, then update with the final result.

Acceptance:
- Overlay feels responsive even when verification takes longer.
- Repeated scans of the same content do not keep spiking CPU or RAM.

## First Delivery Slice for This Iteration

This implementation pass will prioritize:

1. Backend URL propagation and normalization.
2. Biometric startup reliability.
3. Accessibility URL-filter accuracy and scan-pressure reduction.
4. Overlay result-state clarity and full-page call UI upgrade.
5. Intelligence map hookup to backend hotspot data.

## Verification Checklist

1. Save a plain Cloudflare host such as `example.trycloudflare.com` and confirm it becomes `https://example.trycloudflare.com`.
2. Turn realtime protection on and verify the floating bubble stays active.
3. Open Instagram stories and confirm usernames do not trigger URL analysis.
4. Open a real shared link in WhatsApp or Chrome and confirm the overlay shows staged progress and a final verdict.
5. Start or receive a call and confirm the full-page call analysis overlay appears.
6. Open the intelligence screen and confirm hotspot rendering comes from backend data when available.
7. Reopen the app with biometrics enabled and confirm authentication appears immediately after startup.

## Risks to Watch

1. Android OEM accessibility behavior differs by vendor, so URL heuristics must stay conservative.
2. Full-screen overlay behavior may differ across Android versions and overlay plugin limitations.
3. Backend latency can still delay final verdicts, so the UI must remain staged and honest instead of pretending the result is ready.

## Done Definition

The feature is considered ready for the TensorFlow-model integration phase when:

- realtime protection captures the correct content class
- overlay verdicts are understandable and trustworthy
- call analysis presents as a real full-screen experience
- backend URL switching is reliable
- intelligence map and terminal are driven by real backend data
- the app remains responsive on repeated realtime usage

---

## Future Upgrade Section

Updated on: 2026-03-23 10:28:34 +05:30

### New Requirements Added

1. Realtime protection must behave like a deterministic power switch:
   - when the user turns it on, accessibility validation, foreground protection, floating icon eligibility, and live analysis state must become active immediately
   - when the user turns it off, all realtime services, overlays, and pending user-visible analysis states must shut down immediately without half-active leftovers
2. The overlay pipeline must stop getting stuck on stale targets. If the user moves from WhatsApp to Instagram or from one post/link to the next, the captured target, source app label, and verdict state must rotate to the newest valid target instead of staying pinned to the previous one.
3. Offline fallback must feel instant on-device. The target planning budget is sub-1-second feedback for offline verdicts and a 2-3 second ceiling for cloud-assisted verdicts, including staged UI updates while analysis continues.
4. The analysis stack must support concurrency without cancelling protection. If one user triggers multiple captures in quick succession, the system should queue, prioritize, and expire stale work safely rather than dropping analysis or blocking the UI.
5. Crash stability now needs a stronger dedicated track covering the `risk_guard keeps stopping` failure, the intermittent black-screen state with a lone `0`, overlay lifecycle failures, service restart gaps, and permission-state desynchronization during rapid toggling.
6. The calling experience needs a future native-grade track. The long-term target is a normal full-screen phone experience with familiar controls such as answer, decline, speaker, mute, keypad, hold, merge, and caller info, while RiskGuard voice analytics stays integrated as an additional trusted layer.
7. Performance must be planned for low-end Android devices as a first-class requirement. The full realtime stack should remain responsive on 3-4 GB RAM devices by reducing tree-walk pressure, overlay redraw churn, duplicate scans, and background memory growth.
8. Scale readiness must be built into the plan now. The system should be shaped so one heavy user session does not stall the pipeline, and the backend/app contract can grow toward multiple concurrent users without breakdowns in queueing, retries, or event delivery.
9. **Background Persistence**: When the app is closed, all realtime features are currently closing; this must be corrected so that the protection remains active in the background until explicitly disabled.

### Future Planning Notes

- Split the realtime state model into four clear layers: permission state, service state, overlay visibility state, and active-analysis state. The master toggle should orchestrate all four from one source of truth.
- Add a freshness-aware capture queue so the newest valid target can replace stale UI instantly, while older analysis jobs either finish in the background, merge into history, or expire safely when no longer relevant.
- Define strict latency budgets for each analysis path:
  - target extraction budget
  - offline verdict budget
  - cloud request budget
  - overlay render budget
- Introduce bounded worker scheduling and backpressure rules so repeated captures from scrolling, rapid app switching, or busy messaging sessions do not exhaust RAM or freeze the overlay.
- Add a recovery plan for the background stack:
  - crash diagnostics for accessibility and overlay services
  - automatic service health checks
  - restart-safe state restoration after process death
- Plan a low-memory operating mode that reduces nonessential animations, limits retained scan history in memory, and downgrades expensive visual effects before Android force-stops the app.
- Separate the future call experience into a dedicated delivery track: native-style call shell, RiskGuard analytics module, and graceful fallback behavior when OEM restrictions block full integration.
- Add explicit scale-readiness checkpoints to the roadmap so local queueing, backend acknowledgements, retry policy, and anonymized intelligence-event streaming can grow beyond a single-device test scenario.
- **Ensure that realtime features do not close when the application is closed or removed from the background.**

## Plan Update

Updated on: 2026-03-21 22:36:48 +05:30

### Newly Added Ideas

1. Realtime protection must keep working even after the main app UI is closed, as long as the user has realtime analysis enabled.
2. The floating icon must not stay visible all the time. It should appear only when:
   - a whitelisted app is currently in use
   - or a call-analysis session is active
3. When the user is outside the whitelisted apps, the protection stack should keep monitoring in the background, but the floating icon should stay hidden unless there is an active alert or call state that requires user-visible output.
4. The `risk_guard keeps stopping` behavior needs a dedicated crash-stability investigation track, especially around:
   - accessibility-service lifetime
   - foreground-service survival after app close
   - overlay visibility transitions between whitelisted apps, home screen, and call mode

### Planning Notes for the Next Upgrade Pass

- Add a foreground-app gate so overlay visibility is controlled by the current package and the whitelist state.
- Separate `service active` from `overlay visible` so background monitoring can continue even when the bubble is hidden.
- Add a persistence rule for app-close behavior:
  - closing the UI must not stop protection services
  - stopping protection explicitly from the app must stop them cleanly
- Add a crash-diagnostics checklist for the background stack before the next implementation pass.

---

## Execution Update

Updated on: 2026-03-24 00:00:00 +05:30

### Root Causes Confirmed In Code

1. The realtime toggle inside the security settings modal was still closing the bottom sheet because it called `Navigator.pop(ctx)` after every toggle action.
2. Overlay visibility could stay stale because the accessibility service returned early for launcher, system UI, keyboard, and RiskGuard screens before emitting a visibility update.
3. Whitelist gating was still permissive when no whitelist apps were enabled, which allowed the bubble to appear outside the intended app scope.
4. The overlay runtime still depended on sticky bubble state and generic payload repainting, which allowed call-session state to leak into unrelated screens.
5. The simplified Intelligence map painter had replaced the stronger world-map presentation and reduced the visual quality of the screen.

### Changes Implemented In This Pass

1. Native window changes now always recalculate overlay visibility before non-whitelisted or ignored packages are filtered out.
2. Realtime scanning and bubble visibility are now strict whitelist-only from the native accessibility layer.
3. The security settings realtime toggle no longer dismisses its own modal and is now bound to provider state through `Consumer`.
4. Realtime provider teardown now closes the overlay runtime before stopping the foreground service so toggle-off hides UI immediately.
5. The overlay runtime was rebuilt around typed session ownership for URL, media, and call flows.
6. Call teardown now clears the session immediately on `IDLE` instead of leaving a lingering `CALL ENDED` card over unrelated apps.
7. Bubble visibility is now derived from the current foreground whitelist state and live call state instead of a sticky flag.
8. The Intelligence Center map was rebuilt with a denser cyber-map renderer, pulsing backend hotspots, grid overlay, and scan-line effect while keeping the privacy-safe terminal.

### Current Verification Focus

- repeated on/off toggles from both the main page and the security settings modal
- bubble hidden on launcher, RiskGuard screens, and non-whitelisted apps
- call overlay cleared immediately when the call ends
- faster app switching between WhatsApp, Instagram, Chrome, and home screen
- Intelligence map quality and correct pause/resume behavior while hidden

---

## Realtime UI Recovery Update

Updated on: 2026-03-24 12:10:00 +05:30

### Additional Conclusions Confirmed In Code

1. The current native realtime event path still emits only `url_capture` and `call_state`. There is no true screen-media producer yet for visible image/video content, so live media verdicts cannot be honest until that producer exists.
2. The floating bubble failed to reopen because collapsed sessions were being tracked in a way that blocked re-expansion.
3. The overlay runtime was still launched with right-side gravity, which worked against free dragging and deterministic centered expansion.
4. The call companion was still too intrusive because the overlay surface itself was oversized, not just the visual card.

### Changes Added In This Follow-Up Pass

1. Bubble expansion now reopens correctly after collapse, and tap-to-expand moves the analysis card to the center of the screen.
2. Bubble position is preserved so the user can drag it and minimize back to the same location.
3. Overlay runtime gravity was changed so the bubble is no longer forced back to the screen edge after movement.
4. Manual overlay payloads from image, text, video-frame, and voice analysis screens were normalized into an explicit typed contract to reduce session leakage into realtime call state.
5. The hybrid call companion was reshaped into a bottom-anchored panel instead of an oversized full-screen surface.
6. The Intelligence Center world map painter was upgraded again with denser continent geometry and stronger coastline rendering.

### Remaining Boundary

- True live screen image/video analysis still requires a dedicated capture pipeline such as MediaProjection or another explicit media producer. The current fixes stabilize the realtime UI and session ownership, but they do not invent raw screen-media capture that the codebase does not yet have.
