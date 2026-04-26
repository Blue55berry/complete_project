# RiskGuard — Feature Roadmap

## ✅ Implemented Features

### Core Detection (Backend — FastAPI)
| Feature | Status | Details |
|---------|--------|---------|
| Voice/Audio Detection | ✅ Done | wav2vec2 + MFCC + spectral + silence analysis |
| Image Deepfake Detection | ✅ Done | Multi-stage pipeline: DCT, CLIP, noise, metadata, ELA |
| Video Analysis | ✅ Done | Frame-by-frame deepfake detection + local fallback |
| Text/Phishing Detection | ✅ Done | DistilBERT-based NLP classification |
| Blockchain Reporting | ✅ Done | SHA-256 hash + batch verification on Polygon |
| Risk Scoring | ✅ Done | Weighted multi-factor risk assessment |
| **Intelligence Engine** | ✅ Done | Aggregates URLhaus + Crowdsourced + Global Node data |

### Frontend (Flutter)
| Feature | Status | Details |
|---------|--------|---------|
| Home Dashboard | ✅ Done | Security status card, shield count, scan history |
| Analysis Center | ✅ Done | Dedicated tabs for Voice, Image, Video, and Text |
| Intelligence Center | ✅ Done | Animated World Map + Live Scrolling Threat Feed |
| Blockchain Report Screen | ✅ Done | Batch verification, on-chain proof |
| Scan History (Hive) | ✅ Done | Persistent local storage, timeline view |
| Profile & Settings | ✅ Done | Full settings UI with all controls |
| **Auth & Security** | ✅ Done | Full Logout + Data Wipe + Biometric Lock |

### Native & Background (Android)
| Feature | Status | Details |
|---------|--------|---------|
| Foreground Service | ✅ Done | Persistent protection monitoring with notification |
| Floating Overlay | ✅ Done | System-alert-window for real-time risk alerts |
| Accessibility Service | ✅ Done | Active screen scanning for malicious URLs (Kotlin) |
| Native Bridge | ✅ Done | Seamless sync between Flutter and Kotlin services |
| **Real-time Call Guard** | ✅ Done | Incoming AI caller detection with full-screen scan overlay |
| **Multi-modal Fusion** | ✅ Done | Audio + Visual combined deepfake analysis (video) |
| **Visual Identity** | ✅ Done | Professional transparent logo & production launcher icons |

---

## 🔨 Final Polish for Production (Play Store Ready)

To make RiskGuard 100% professional and ready for the Google Play Store, we need to address these final gaps:

### 🚀 Performance & Packaging
- [ ] **ProGuard/R8 Obfuscation**: Protect backend URL and logic from reverse engineering.
- [ ] **App Bundle (.aab)**: Optimize install size (≈15-20% smaller than APK).
- [ ] **Release Signing**: Generate a secure production Keystore.

### 🎨 UI/UX Excellence
- [ ] **App Store Assets**: Designing professional screenshots with feature callouts.
- [ ] **Dynamic Icon**: Adaptive Android icons that change shape based on device theme.
- [ ] **Dark/Light Mode Sync**: Ensure 100% of screens respect system brightness changes.

### 🛡️ Security Hardening
- [ ] **SSL Pinning**: Prevent Man-in-the-Middle attacks on the backend connection.
- [ ] **Secure Storage**: Move sensitive tokens from Hive to EncryptedSharedPreferences.
- [ ] **Privacy Policy**: Generate a comprehensive document covering data collection.

### 🌍 Global Scale
- [ ] **Localization**: Support for multiple languages (Spanish, Hindi, Turkish, etc.).
- [ ] **Deep Linking**: Allow users to share specific threat reports via links.

---

## 🗺️ Future Roadmap (V4.0)

### Phase 3: TFLite Local ML (Hybrid Gatekeeper)
- **Status**: Researching
- **Logic**: Use local models to filter 80% of common scans, only calling the cloud for complex cases. 
- **Benefit**: Massive reduction in latency and hosting costs.

### Phase 6: Regional Threat Intelligence
- **Goal**: Allow users to see threat trends specifically in their city/neighborhood using GPS tagging (Privacy-preserving).

---

*Last updated: March 17, 2026 | Session: Intelligence & Privacy Overhaul*
