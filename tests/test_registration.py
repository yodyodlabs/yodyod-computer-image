import contextlib
import importlib.util
import io
import json
import os
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(os.environ.get("YODYOD_SOURCE_ROOT", str(Path(__file__).resolve().parents[1])))
spec = importlib.util.spec_from_file_location("registration", ROOT / "scripts" / "register-template.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RegistrationTests(unittest.TestCase):
    def run_registration(self, templates):
        calls = []

        def fake_open(request, timeout):
            calls.append(request)
            result = {"data": templates} if request.method == "GET" else {
                "name": "yodyod-computer", "revision": 2, "image_digest": "sha256:test"
            }
            return io.BytesIO(json.dumps(result).encode())

        output = io.StringIO()
        with patch.dict(os.environ, {
            "AGENT37_API_KEY": "test-workspace-key", "AGENT37_API_URL": "https://api.agent37.com",
            "GHCR_USERNAME": "test-user", "GHCR_TOKEN": "test-registry-token",
        }), patch("sys.argv", ["register-template.py", "--image", "ghcr.io/example/image:sha-test"]), \
                patch.object(module.urllib.request, "urlopen", side_effect=fake_open), \
                contextlib.redirect_stdout(output):
            module.main()
        self.assertNotIn("test-registry-token", output.getvalue())
        self.assertNotIn("test-workspace-key", output.getvalue())
        return calls

    def test_new_template_uses_post_and_private_registry_auth(self):
        calls = self.run_registration([])
        self.assertEqual([r.method for r in calls], ["GET", "POST"])
        body = json.loads(calls[1].data)
        self.assertEqual(body["name"], "yodyod-computer")
        self.assertEqual(body["registry_auth"]["username"], "test-user")
        self.assertEqual(body["default_port"], 3737)

    def test_update_uses_template_name_not_an_instance_or_build_id(self):
        calls = self.run_registration([{
            "name": "yodyod-computer", "scope": "workspace", "image_ref": "old:image"
        }])
        self.assertEqual(calls[-1].method, "PATCH")
        self.assertEqual(calls[-1].full_url, "https://api.agent37.com/v1/templates/yodyod-computer")

    def test_same_reference_does_not_publish_a_revision(self):
        calls = self.run_registration([{
            "name": "yodyod-computer", "scope": "workspace",
            "image_ref": "ghcr.io/example/image:sha-test", "revision": 2,
        }])
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
