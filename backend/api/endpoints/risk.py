"""
Risk Scoring API Endpoint
Combines multiple risk factors into a final trust score
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict

router = APIRouter()


class RiskInput(BaseModel):
    callScore: Optional[int] = None
    voiceScore: Optional[int] = None
    contentScore: Optional[int] = None
    historyScore: Optional[int] = None
    riskFactors: Optional[List[str]] = []


class RiskFactor(BaseModel):
    name: str
    contribution: int
    category: str


class RiskScoringResponse(BaseModel):
    finalScore: int
    riskLevel: str
    confidence: float
    componentScores: Dict[str, int]
    riskFactors: List[RiskFactor]
    explanation: str


# Scoring weights
CALL_WEIGHT = 0.25
VOICE_WEIGHT = 0.30
CONTENT_WEIGHT = 0.30
HISTORY_WEIGHT = 0.15


def calculate_risk_score(input_data: RiskInput) -> dict:
    """
    Calculate weighted risk score from all components.
    """
    component_scores = {}
    total_weighted = 0.0
    total_weight = 0.0
    risk_factors = []
    
    # Process call score
    if input_data.callScore is not None:
        component_scores["call"] = input_data.callScore
        total_weighted += input_data.callScore * CALL_WEIGHT
        total_weight += CALL_WEIGHT
        
        if input_data.callScore > 50:
            risk_factors.append({
                "name": "Suspicious call pattern",
                "contribution": int(input_data.callScore * 0.3),
                "category": "call"
            })
    
    # Process voice score
    if input_data.voiceScore is not None:
        component_scores["voice"] = input_data.voiceScore
        total_weighted += input_data.voiceScore * VOICE_WEIGHT
        total_weight += VOICE_WEIGHT
        
        if input_data.voiceScore > 40:
            risk_factors.append({
                "name": "AI voice indicators",
                "contribution": int(input_data.voiceScore * 0.4),
                "category": "voice"
            })
    
    # Process content score
    if input_data.contentScore is not None:
        component_scores["content"] = input_data.contentScore
        total_weighted += input_data.contentScore * CONTENT_WEIGHT
        total_weight += CONTENT_WEIGHT
        
        if input_data.contentScore > 40:
            risk_factors.append({
                "name": "Suspicious content",
                "contribution": int(input_data.contentScore * 0.4),
                "category": "content"
            })
    
    # Process history score
    if input_data.historyScore is not None:
        component_scores["history"] = input_data.historyScore
        total_weighted += input_data.historyScore * HISTORY_WEIGHT
        total_weight += HISTORY_WEIGHT
    
    # Add user-provided risk factors
    for factor in input_data.riskFactors or []:
        risk_factors.append({
            "name": factor,
            "contribution": 10,
            "category": "user"
        })
    
    # Calculate final score
    final_score = int(total_weighted / total_weight) if total_weight > 0 else 0
    final_score = min(100, max(0, final_score))
    
    # Determine risk level
    if final_score <= 30:
        risk_level = "LOW"
    elif final_score <= 70:
        risk_level = "MEDIUM"
    else:
        risk_level = "HIGH"
    
    # Confidence is about evidence coverage and consistency, not certainty.
    coverage = len(component_scores) / 4 if component_scores else 0.0
    avg_strength = (
        sum(component_scores.values()) / (len(component_scores) * 100.0)
        if component_scores else 0.0
    )
    spread = (
        (max(component_scores.values()) - min(component_scores.values())) / 100.0
        if len(component_scores) > 1 else 0.0
    )
    confidence = 0.15 + coverage * 0.35 + min(avg_strength, 0.8) * 0.25 - spread * 0.10
    if len(component_scores) == 1:
        confidence = min(confidence, 0.42)
    elif len(component_scores) == 2:
        confidence = min(confidence, 0.62)
    confidence = min(max(confidence, 0.12), 0.88)
    
    # Generate explanation
    if final_score <= 30:
        explanation = "This interaction appears safe. No significant risk indicators."
    elif final_score <= 70:
        highest = max(component_scores.items(), key=lambda x: x[1]) if component_scores else ("unknown", 0)
        explanation = f"Exercise caution. Primary concern: {highest[0]} (score: {highest[1]})."
    else:
        top_factors = [f["name"] for f in risk_factors[:2]]
        explanation = f"High risk! Key threats: {', '.join(top_factors)}. Do not share information."
    
    return {
        "finalScore": final_score,
        "riskLevel": risk_level,
        "confidence": round(confidence, 2),
        "componentScores": component_scores,
        "riskFactors": risk_factors,
        "explanation": explanation
    }


@router.post("/calculate", response_model=RiskScoringResponse)
async def calculate_risk(request: RiskInput):
    """
    Calculate comprehensive risk score from multiple inputs.
    
    Accepts: Individual component scores (call, voice, content, history)
    Returns: Weighted final score, risk level, and explanation
    """
    try:
        result = calculate_risk_score(request)
        return RiskScoringResponse(**result)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Scoring failed: {str(e)}"
        )


@router.get("/weights")
async def get_weights():
    """
    Get current scoring weights.
    """
    return {
        "callWeight": CALL_WEIGHT,
        "voiceWeight": VOICE_WEIGHT,
        "contentWeight": CONTENT_WEIGHT,
        "historyWeight": HISTORY_WEIGHT
    }
