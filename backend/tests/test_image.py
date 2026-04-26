
import unittest
import requests
import base64

BASE_URL = "http://127.0.0.1:8000/api/v1"

class TestImageAnalysis(unittest.TestCase):
    def setUp(self):
        try:
            requests.get(f"http://127.0.0.1:8000/health", timeout=1)
        except:
            self.skipTest("Backend server not running")

    def test_analyze_image_mock(self):
        """Test image analysis with a 1x1 pixel mock image"""
        # 1x1 pixel black PNG
        dummy_img = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        
        files = {'image': ('test.png', dummy_img, 'image/png')}
        response = requests.post(f"{BASE_URL}/analyze/image", files=files)
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("aiGeneratedProbability", data)
        self.assertIn("isAiGenerated", data)

if __name__ == '__main__':
    unittest.main()
