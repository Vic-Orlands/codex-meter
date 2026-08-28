import runpy
import time
import unittest
from pathlib import Path


module = runpy.run_path(str(Path(__file__).parents[1] / "cli" / "codex-meter"))


class CLITests(unittest.TestCase):
    def test_duration(self):
        self.assertEqual(module["duration"](90061), "1d 1h")
        self.assertEqual(module["duration"](120), "2m")

    def test_window_line(self):
        line = module["window_line"]("Weekly", {"usedPercent": 27, "resetsAt": time.time() + 3600})
        self.assertIn("73% left", line)
        self.assertIn("27% used", line)

    def test_render(self):
        output = module["render"]({
            "account": {"email": "dev@example.com", "planType": "pro"},
            "rateLimits": {
                "primary": {"usedPercent": 10},
                "secondary": {"usedPercent": 20},
                "credits": {"hasCredits": True, "unlimited": False, "balance": "12.50"},
            },
            "usage": {"summary": {"lifetimeTokens": 1234}},
        })
        self.assertIn("dev@example.com", output)
        self.assertIn("90% left", output)
        self.assertIn("1,234 lifetime", output)


if __name__ == "__main__":
    unittest.main()
