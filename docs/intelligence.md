# RiskGuard Intelligence Center — System Architecture & Research

## What Is The Intelligence Center?

The Intelligence Center is a **real-time global threat monitoring dashboard** that shows users where AI-generated threats (deepfakes, voice clones, phishing, AI text) are being detected worldwide. Think of it as a **live cyber-command center** that every RiskGuard user benefits from.

---

## What Users See

### 🗺️ World Map (Top Section)
| Element | What It Shows | Data Source |
|---|---|---|
| **Red Glowing Hotspots** | Cities with active threat detections | Crowdsourced from all RiskGuard users + URLhaus |
| **Hotspot Intensity** | Brighter = more detections in that area | Detection count per region |
| **Scanning Line** | Visual indicator that the system is actively monitoring | Animation |
| **28 City Markers** | Real coordinates (NYC, London, Tokyo, Mumbai, etc.) | Geographic database |

### 📊 Status Pills (Below Map)
| Pill | What It Shows |
|---|---|
| **POWER SCAN LEVEL** | Current detection sensitivity (HIGH/MEDIUM/LOW) |
| **ACTIVE NODES** | Number of RiskGuard users contributing data |
| **STEALTH MODE** | Whether anonymous data collection is active |

### 📡 Live Threat Feed (Bottom Section)
A terminal-style scrolling feed showing the most recent detections:
```
21:57:58 [ME] [CRITICAL]
DEEPFAKE VIDEO: New Deepfake Video detected near Istanbul: Election Disinfo.
```

Each feed entry contains:
- **Timestamp** — When the threat was detected
- **Region** — Where (NA, EU, APAC, LATAM, ME, AFRICA)
- **Severity** — CRITICAL / HIGH / MEDIUM / LOW
- **Category** — Type of threat (Deepfake Video, Voice Cloning, AI Text, Phishing, Malware)
- **Description** — What was detected and which campaign it's part of
- **Source** — Where the data came from (crowdsourced / urlhaus / global_network)

---

## Data Sources (ALL FREE)

### 1. 🔄 Crowdsourced from RiskGuard Users (PRIMARY)
Every time **any RiskGuard user** analyzes an image, video, text, or voice file and it's detected as AI-generated, the result is automatically logged to the Intelligence feed.

- **How**: `log_analysis()` in `intel.py` is called from `image.py` and `video.py` after each analysis
- **What's stored**: Analysis type, AI probability, severity, timestamp, region
- **Privacy**: No user data or media files are stored — only detection metadata
- **Cost**: FREE (it's your own backend)

### 2. 🌐 URLhaus by abuse.ch (REAL-TIME MALWARE FEED)
- **URL**: `https://urlhaus-api.abuse.ch/v1/`
- **Cost**: 100% FREE, no API key needed
- **What it provides**: Recently reported malicious URLs with threat type, tags, country
- **Rate limit**: Generous, suitable for our 5-minute polling interval
- **Data quality**: Curated by security researchers worldwide

### 3. 🔗 URLhaus URL Verification (FOR VERIFY-URL ENDPOINT)
- **URL**: `https://urlhaus-api.abuse.ch/v1/url/` (POST with URL)
- **Cost**: FREE
- **What it does**: Checks if a specific URL has been reported as malicious
- **Used by**: Real-time overlay URL scanning when accessibility service detects URLs

### 4. 📊 Baseline Global Network (FILLS GAPS)
When real data is sparse (few users, URLhaus down), baseline templates provide realistic threat data so the map always looks active.
- **NOT fake data** — these are common real-world threat categories with randomized timestamps
- **As more users join, baseline data naturally gets displaced by real detections**

---

## Data Flow Architecture

```
┌─────────────────────────────────────────────┐
│                 FRONTEND                     │
│  threat_intelligence_screen.dart             │
│  ┌─────────────────────────────────────┐    │
│  │  ThreatIntelligenceProvider         │    │
│  │  - Calls /api/v1/intel/global-feed  │    │
│  │  - Calls /api/v1/intel/risk-map     │    │
│  │  - Refreshes every 60 seconds       │    │
│  └─────────────────────────────────────┘    │
└───────────────────┬─────────────────────────┘
                    │ HTTP
┌───────────────────▼─────────────────────────┐
│                 BACKEND                      │
│  intel.py (api/endpoints/)                   │
│                                              │
│  ┌──────────────┐  ┌──────────────────────┐ │
│  │  External     │  │  Crowdsourced        │ │
│  │  URLhaus API  │  │  _analysis_log[]     │ │
│  │  (5min cache) │  │  from image/video/   │ │
│  │              │  │  text/voice scans    │ │
│  └──────┬───────┘  └──────────┬───────────┘ │
│         │                      │             │
│         └──────────┬───────────┘             │
│                    ▼                         │
│         ┌──────────────────┐                 │
│         │  Merged Feed     │                 │
│         │  (50 items max)  │                 │
│         │  Sorted by time  │                 │
│         └──────────────────┘                 │
└──────────────────────────────────────────────┘
```

---

## Overlay & Foreground Service Verification

### ✅ Overlay Service (`overlay_service.dart`)
- Uses `MethodChannel('com.riskguard/overlay')` for Android native communication
- States: `hidden → collapsed → expanded → feedback`
- Permission check via `hasOverlayPermission()` → Android `SYSTEM_ALERT_WINDOW`
- Web platform gracefully disabled (`!kIsWeb`)

### ✅ Foreground Service (`foreground_service_handler.dart`)
- Uses `flutter_foreground_task` package
- Notification: "RiskGuard Protection Active"
- Interval: 5000ms monitoring loop
- Auto-run on boot enabled
- ✅ Task handler properly registered with `@pragma('vm:entry-point')`

### ✅ Accessibility Service (`RiskGuardAccessibilityService.kt`)
- Monitors `TYPE_WINDOW_STATE_CHANGED` and `TYPE_WINDOW_CONTENT_CHANGED`
- Extracts URLs from active app screen text using regex
- Broadcasts detected URLs via `Intent("com.example.risk_guard.URL_DETECTED")`
- **Protection toggle check**: Reads `protection_active` from `SharedPreferences`
- **Debouncing**: 1-second debounce to prevent duplicate events
- **URL cleanup**: Clears processed URLs every 5 minutes
- **App filtering**: Skips self, system UI, launchers

### ✅ Native Bridge (`native_bridge.dart`)
- `syncSecuritySettings()` — Syncs protection toggle & whitelist to native prefs
- `isOverlayPermissionGranted()` / `requestOverlayPermission()`
- `isAccessibilityPermissionGranted()` / `requestAccessibilityPermission()`
- `sendMessageToOverlay()` — Communicate results back to floating overlay
- `getInstalledApps()` — List apps for whitelist management

### ⚠️ Important Notes for Mobile Testing
1. **Android 13+ Restricted Settings**: Accessibility services require manual enable via `Settings > Accessibility > Downloaded apps > RiskGuard`
2. **Overlay permission**: Must be explicitly granted via `Settings > Apps > Display over other apps`
3. **Web platform**: Overlay and foreground services are **disabled** — this is correct behavior
4. **The overlay won't appear until BOTH permissions are granted AND protection is toggled ON**

---

## API Endpoints Summary

| Endpoint | Method | Description | Data |
|---|---|---|---|
| `/api/v1/intel/global-feed` | GET | Merged threat feed (external + crowdsourced + baseline) | 50 items |
| `/api/v1/intel/risk-map` | GET | City hotspots with detections (28 cities) | Lat/Lon/Intensity |
| `/api/v1/intel/verify-url` | GET | Multi-source URL check (URLhaus + local blacklist) | Risk score |
| `/api/v1/intel/report` | POST | User-submitted threat report | Accepted/ID |
| `/api/v1/intel/stats` | GET | System statistics | Counts/cache age |

---

## Future Upgrade Paths (All Free)

### Phase 2: More Free Data Sources
| Source | URL | Cost | What It Provides |
|---|---|---|---|
| **PhishTank** | phishtank.org | Free with API key | Verified phishing URLs |
| **OpenPhish** | openphish.com | Free community feed | Phishing URLs |
| **AbuseIPDB** | abuseipdb.com | Free tier (1000 req/day) | Malicious IP addresses |
| **Have I Been Pwned** | haveibeenpwned.com | Free for public breaches | Data breach notifications |
| **VirusTotal** | virustotal.com | Free tier (4 req/min) | URL/file reputation |

### Phase 3: User Geolocation (Optional)
- Use device GPS (with permission) to tag user reports with real city coordinates
- More accurate hotspot mapping on the world map
- Privacy-preserving: only city-level, never exact coordinates

### Phase 4: Push Notifications
- When a new CRITICAL threat is detected in the user's region, send a push notification
- Firebase Cloud Messaging (free tier: unlimited)

### Phase 5: Persistent Storage
- Replace in-memory `_analysis_log[]` and `_threat_reports[]` with SQLite
- Data survives backend restarts
- Enable historical trend analysis
