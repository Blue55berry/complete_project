import asyncio
import importlib.util
import sys
import types
import unittest
from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _load_text_module():
    sys.path.insert(0, str(BACKEND_ROOT))

    api_pkg = sys.modules.get("api")
    if api_pkg is None:
        api_pkg = types.ModuleType("api")
        api_pkg.__path__ = [str(BACKEND_ROOT / "api")]
        sys.modules["api"] = api_pkg

    endpoints_pkg = sys.modules.get("api.endpoints")
    if endpoints_pkg is None:
        endpoints_pkg = types.ModuleType("api.endpoints")
        endpoints_pkg.__path__ = [str(BACKEND_ROOT / "api" / "endpoints")]
        sys.modules["api.endpoints"] = endpoints_pkg

    spec = importlib.util.spec_from_file_location(
        "api.endpoints.text",
        BACKEND_ROOT / "api" / "endpoints" / "text.py",
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["api.endpoints.text"] = module
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


TEXT = _load_text_module()


HUMAN_TEXT = (
    "Hey, I moved the client call to 3:15 because the vendor got stuck in traffic. "
    "If you are still coming by the office later, bring the printed quote with you. "
    "I think the numbers are fine, but I want one more quick look before we send it."
)

AI_TEXT = (
    "Furthermore, it is important to note that implementing a comprehensive governance "
    "framework enables organizations to optimize operational efficiency while maintaining "
    "long-term strategic alignment across stakeholders. In conclusion, this multifaceted "
    "approach plays a crucial role in ensuring scalable and sustainable transformation. "
    "Moreover, the findings indicate that a standardized oversight model can improve "
    "consistency, transparency, and measurable performance outcomes across distributed teams."
)

LONG_AI_TEXT = " ".join([AI_TEXT] * 8)


class TestTextAnalysisPipeline(unittest.IsolatedAsyncioTestCase):
    async def test_detect_ai_prefers_conversational_human_text(self):
        result = await TEXT._detect_ai(HUMAN_TEXT, use_cloud=False)
        self.assertLess(result["aiGeneratedProbability"], 0.45)
        self.assertIn("local", result["analysisMethod"])

    async def test_detect_ai_prefers_structured_ai_text(self):
        result = await TEXT._detect_ai(AI_TEXT, use_cloud=False)
        self.assertGreater(result["aiGeneratedProbability"], 0.70)
        self.assertGreater(result["aiConfidence"], 0.30)

    async def test_detect_ai_chunks_long_documents(self):
        result = await TEXT._detect_ai(LONG_AI_TEXT, use_cloud=False)
        self.assertGreaterEqual(result["aiSubScores"]["chunk_count"], 2)
        self.assertGreater(result["aiGeneratedProbability"], 0.70)

    async def test_short_text_returns_low_confidence(self):
        result = await TEXT._detect_ai("Sure, send it over tonight.", use_cloud=False)
        self.assertLess(result["aiConfidence"], 0.45)
        self.assertTrue(result["aiSubScores"]["low_confidence_input"])

    async def test_endpoint_rejects_tiny_inputs(self):
        with self.assertRaises(TEXT.HTTPException):
            await TEXT.analyze_text(TEXT.TextAnalysisRequest(text="Hi", useCloudAI=False))


class TestDetectorInternals(unittest.TestCase):
    def test_chunk_builder_splits_long_text(self):
        long_text = " ".join(
            [
                "This is a sentence that keeps the document moving with the same polished cadence."
                for _ in range(80)
            ]
        )
        chunks = TEXT._build_chunks(long_text)
        self.assertGreaterEqual(len(chunks), 2)
        self.assertLessEqual(len(chunks), 6)

    def test_hf_parser_uses_label_margin(self):
        narrow = TEXT._parse_hf_binary(
            [{"label": "AI", "score": 0.58}, {"label": "Real", "score": 0.42}],
            TEXT._AI_LABEL_TOKENS,
        )
        strong = TEXT._parse_hf_binary(
            [{"label": "AI", "score": 0.84}, {"label": "Real", "score": 0.16}],
            TEXT._AI_LABEL_TOKENS,
        )

        self.assertIsNotNone(narrow)
        self.assertIsNotNone(strong)
        self.assertGreater(strong["prob"], narrow["prob"])
        self.assertGreater(strong["conf"], narrow["conf"])

    def test_local_feature_breakdown_is_present(self):
        local = TEXT._local_ai_score(AI_TEXT)
        self.assertIn("struct_score", local["detail"])
        self.assertIn("repetition_score", local["detail"])
        self.assertIn("entropy_score", local["detail"])


if __name__ == "__main__":
    unittest.main()
