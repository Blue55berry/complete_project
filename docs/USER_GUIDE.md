# RiskGuard User Guide

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Features](#features)
4. [Troubleshooting](#troubleshooting)

## Introduction

RiskGuard is an AI-powered digital protection app that helps you identify scams, deepfakes, and suspicious communications in real-time.

### Key Features

- **Real-Time Call Protection**: Analyze incoming calls for scam patterns
- **AI Voice Detection**: Identify AI-generated voices (Note: not 100% accurate)
- **Message Analysis**: Detect phishing and scam messages
- **Video Deepfake Detection**: Analyze videos for manipulation
- **Overall Analytics**: View comprehensive statistics and trends

## Getting Started

### Installation

1. Install the app from your app store
2. Grant required permissions:
   - Phone (for call monitoring)
   - Microphone (for voice analysis)
   - Storage (for video analysis)

### First Launch

1. Complete the onboarding tutorial
2. Enable call monitoring from the dashboard
3. Start receiving real-time protection

## Features

### 1. Dashboard

The main dashboard shows:
- **Protection Status**: Current monitoring status
- **Recent Calls**: Latest analyzed calls with risk scores
- **Quick Actions**: Access to all analysis features
- **Statistics**: Overview of detected threats

**How to use:**
- Tap the shield icon to toggle protection ON/OFF
- Tap"Overall Analysis" to view detailed statistics
- Use quick action buttons to access specific features

### 2. Call Protection

Real-time analysis of incoming and outgoing calls.

**Features:**
- Risk score (0-100) displayed during calls
- Risk level indicator (Low, Medium, High)
- AI voice detection with confidence percentage
- Post-call detailed analysis

**Understanding Risk Scores:**
- **0-30**: Low risk (likely safe)
- **31-60**: Medium risk (exercise caution)
- **61-100**: High risk (potential scam)

**AI Voice Detection:**
- 👤 **Human Voice**: Natural speech patterns detected
- 🤖 **AI Generated**: Synthetic voice likely detected
- ❓ **Uncertain**: Unable to determine with confidence

> **Note**: AI voice detection is not 100% accurate and may have false positives/negatives.

### 3. Voice Analysis

Standalone voice analysis for audio recordings.

**How to use:**
1. Navigate to Voice Analysis from dashboard
2. Upload an audio file or record new audio
3. Wait for analysis to complete
4. Review results and detected patterns

**What it detects:**
- Pitch stability anomalies
- Repetitive frequency patterns
- Missing micro-variations
- Breathing pattern irregularities

### 4. Message Analysis

Scan messages for phishing and scam patterns.

**How to use:**
1. Go to Message Analysis
2. Paste or type the message
3. Tap "Analyze"
4. Review detected threats

**Threat Types:**
- 🎣 **Phishing**: Account verification scams
- ⚠️ **Urgency**: Pressure tactics
- 🎁 **Fake Offers**: Prize/lottery scams
- 🔗 **Suspicious Links**: Shortened or malicious URLs
- 💰 **Financial Scams**: Money transfer requests

### 5. Video Analysis

Detect deepfakes and video manipulation.

**How to use:**
1. Navigate to Video Analysis
2. Tap "Select Video File"
3. Choose a video from your device
4. Wait for analysis (may take 1-2 minutes)
5. Review deepfake probability and patterns

**What it detects:**
- Facial expression inconsistencies
- Micro-artifacts around face regions
- Temporal frame inconsistencies
- Lip sync anomalies

**Deepfake Probability:**
- **0-20%**: Likely authentic
- **21-40%**: Possibly edited
- **41-100%**: Likely deepfake or heavily manipulated

### 6. Overall Analysis

Comprehensive analytics dashboard showing all detected threats.

**Features:**
- Total calls and risk breakdown
- AI voice detection statistics
- Message threat analysis
- 7-day trend chart
- Recent activity timeline

**How to use:**
1. Tap"Overall Analysis" on dashboard
2. View statistics cards
3. Scroll to see trend chart
4. Review recent activity
5. Pull down to refresh data

**Exporting Data:**
- Tap the menu icon (⋮)
- Select "Export Report"
- Choose format (PDF/CSV)
- Share or save

## Troubleshooting

### Call Protection Not Working

**Problem**: Calls are not being analyzed

**Solutions:**
1. Check that protection is enabled (shield icon is green)
2. Verify phone permission is granted
3. Ensure the app is not battery-optimized
4. Try restarting the app

### AI Voice Detection Showing "Uncertain"

**Problem**: Voice classification is uncertain

**Explanation**: This is normal. AI detection has limitations and some voices fall in the uncertain range (35-65% synthetic probability).

**Tips:**
- Consider other risk factors (unknown number, urgency, etc)
- Use your judgment alongside AI analysis
- Report false positives to improve the system

### Video Analysis Taking Too Long

**Problem**: Video analysis is slow or stuck

**Solutions:**
1. Check your internet connection (for cloud analysis)
2. Ensure video file is under 100MB
3. Try a shorter video clip
4. Check storage space on device

### Message Analysis Not Detecting Threats

**Problem**: Known scam messages show as safe

**Explanation**: Pattern-based detection may miss sophisticated scams

**Tips:**
- Always use critical thinking
- Check for suspicious links manually
- Report missed scams to improve detection
- Verify sender identity independently

### App Crashes or Freezes

**Solutions:**
1. Force close and reopen the app
2. Clear app cache (Settings > Apps > RiskGuard > Clear Cache)
3. Update to latest version
4. Reinstall if issues persist

## Privacy & Security

### Data Collection

RiskGuard processes analysis locally when possible. Cloud analysis (if enabled) sends encrypted data to secure servers.

**What we collect:**
- Anonymous usage statistics
- Analysis results (for improvement)
- Crash reports

**What we DON'T collect:**
- Personal conversations
- Private messages
- Call recordings (unless you explicitly save them)

### Permissions

- **Phone**: Required for call monitoring
- **Microphone**: For voice analysis
- **Storage**: To save analysis results and videos
- **Internet**: For cloud analysis and updates

## FAQ

**Q: Is my data secure?**
A: Yes. All sensitive data is encrypted and processed locally when possible.

**Q: Does the app record my calls?**
A: Only if you explicitly enable call recording in settings.

**Q: How accurate is AI voice detection?**
A: Typically 70-85% accurate. It's a helpful indicator but not definitive proof.

**Q: Can I use the app offline?**
A: Yes, local analysis works offline. Cloud analysis requires internet connection.

**Q: How do I report false positives?**
A: Use the "Report" button on any analysis result.

## Getting Help

- **Email**: support@riskguard.app
- **Website**: https://riskguard.app
- **GitHub**: https://github.com/riskguard/app

## Version History

- **v1.0.0**: Initial release with all core features
