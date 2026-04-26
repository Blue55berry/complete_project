# RiskGuard API Documentation

## Overview

RiskGuard provides a comprehensive API for real-time digital risk detection including voice analysis, message scanning, video deepfake detection, and call risk assessment.

## Base URL

```
http://localhost:8000/api/v1
```

## Authentication

Currently, the API does not require authentication for local development. For production deployment, implement appropriate authentication mechanisms.

## API Endpoints

### Voice Analysis

#### POST /analyze/voice

Analyzes an audio file for AI-generated voice detection.

**Request:**
```http
POST /analyze/voice
Content-Type: multipart/form-data

audio: <audio_file>
```

**Response:**
```json
{
  "syntheticProbability": 0.35,
  "confidence": 0.85,
  "detectedPatterns": [
    "Unusual pitch stability",
    "Repetitive frequency patterns"
  ],
  "explanation": "Voice shows some unusual patterns...",
  "isLikelyAI": false
}
```

**Status Codes:**
- `200 OK` - Analysis successful
- `400 Bad Request` - Invalid audio file
- `500 Internal Server Error` - Analysis failed

---

### Message Analysis

#### POST /analyze/text

Analyzes a text message for phishing and scam patterns.

**Request:**
```http
POST /analyze/text
Content-Type: application/json

{
  "text": "Urgent! Verify your account now..."
}
```

**Response:**
```json
{
  "riskScore": 75,
  "threats": ["phishing", "urgency"],
  "patterns": ["Urgency: \"urgent\"", "Phishing: \"verify your account\""],
  "urls": [],
  "explanation": "High risk detected! This message shows strong indicators of: Phishing Attempt, Urgency Manipulation.",
  "isSafe": false
}
```

**Status Codes:**
- `200 OK` - Analysis successful
- `400 Bad Request` - Invalid request
- `500 Internal Server Error` - Analysis failed

---

### Video Analysis

#### POST /analyze/video

Analyzes a video file for deepfake detection.

**Request:**
```http
POST /analyze/video
Content-Type: multipart/form-data

video: <video_file>
```

**Response:**
```json
{
  "deepfakeProbability": 0.65,
  "confidence": 0.82,
  "threats": ["deepfake", "manipulation"],
  "patterns": [
    "Facial expression inconsistencies detected",
    "Temporal inconsistencies between frames"
  ],
  "analyzedFrames": 30,
  "explanation": "Strong indicators of video manipulation detected...",
  "isAuthentic": false
}
```

**Status Codes:**
- `200 OK` - Analysis successful
- `400 Bad Request` - Invalid video file
- `413 Payload Too Large` - Video file too large
- `500 Internal Server Error` - Analysis failed

---

### Risk Scoring

#### POST /score/calculate

Calculates comprehensive risk score based on multiple factors.

**Request:**
```http
POST /score/calculate
Content-Type: application/json

{
  "phoneNumber": "+911234567890",
  "callMetadata": {},
  "voiceAnalysis": {},
  "contentAnalysis": {}
}
```

**Response:**
```json
{
  "riskScore": 45,
  "riskLevel": "medium",
  "category": "unknown",
  "explanation": "This incoming call shows some caution signs...",
  "riskFactors": ["Unknown caller", "International number"]
}
```

## Error Handling

All endpoints return errors in the following format:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable error message",
    "details": {}
  }
}
```

## Rate Limiting

- **Development**: No rate limiting
- **Production**: Implement rate limiting based on your requirements

## Data Models

### VoiceAnalysisResult

| Field | Type | Description |
|-------|------|-------------|
| syntheticProbability | number (0-1) | Probability of AI-generated voice |
| confidence | number (0-1) | Confidence in the analysis |
| detectedPatterns | string[] | List of detected suspicious patterns |
| explanation | string | Human-readable explanation |
| isLikelyAI | boolean | Whether voice is likely AI-generated |

### MessageAnalysisResult

| Field | Type | Description |
|-------|------|-------------|
| riskScore | number (0-100) | Overall risk score |
| threats | string[] | Detected threat types |
| patterns | string[] | Suspicious patterns found |
| urls | string[] | Extracted URLs |
| explanation | string | Human-readable explanation |
| isSafe | boolean | Whether message is safe |

### VideoAnalysisResult

| Field | Type | Description |
|-------|------|-------------|
| deepfakeProbability | number (0-1) | Probability of deepfake |
| confidence | number (0-1) | Confidence in the analysis |
| threats | string[] | Detected video threats |
| patterns | string[] | Manipulation patterns found |
| analyzedFrames | number | Number of frames analyzed |
| explanation | string | Human-readable explanation |
| isAuthentic | boolean | Whether video is authentic |

## Best Practices

1. **Audio Files**: Use M4A or WAV format, minimum 3 seconds duration
2. **Messages**: Minimum 10 characters for meaningful analysis
3. **Videos**: MP4 format recommended, maximum 100MB file size
4. **Error Handling**: Always implement proper error handling
5. **Timeouts**: Set appropriate timeout values for analysis operations

## Support

For questions or issues, please contact the development team or open an issue on the GitHub repository.
