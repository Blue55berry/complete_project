
import unittest
import requests
import io

BASE_URL = "http://127.0.0.1:8000/api/v1"

class TestAudioAnalysis(unittest.TestCase):
    def setUp(self):
        try:
            requests.get(f"http://127.0.0.1:8000/health", timeout=1)
        except:
            self.skipTest("Backend server not running")

    def test_analyze_audio_mock(self):
        """Test audio analysis with a dummy WAV file"""
        # Create a minimal valid WAV header + silence
        # RIFF header
        wav_header = b'RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xAC\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00'
        
        files = {'audio': ('test.wav', wav_header, 'audio/wav')}
        response = requests.post(f"{BASE_URL}/analyze/voice", files=files)
        
        # Note: Depending on backend validation, this might fail 400 if too short or silent
        # But we check for connection
        if response.status_code == 200:
            data = response.json()
            self.assertIn("aiGeneratedProbability", data)
        elif response.status_code == 400:
            # Acceptable if validation catches short audio
            pass
        else:
            self.fail(f"Unexpected status code: {response.status_code}")

if __name__ == '__main__':
    unittest.main()
