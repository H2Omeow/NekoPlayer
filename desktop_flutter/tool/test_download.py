import io
from pathlib import Path
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

from download import fetch


class Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *arguments):
        return False


class DownloadTests(unittest.TestCase):
    def test_retries_gateway_timeouts(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "file.bin"
            calls = []

            def opener(url, timeout=90):
                calls.append(url)
                if len(calls) == 1:
                    raise urllib.error.HTTPError(url, 504, "Gateway Time-out", {}, None)
                return Response(b"payload")

            with patch("download.urllib.request.urlopen", side_effect=opener), \
                    patch("download.time.sleep") as sleep:
                fetch("https://example.invalid/file", destination)
            self.assertEqual(destination.read_bytes(), b"payload")
            self.assertEqual(len(calls), 2)
            sleep.assert_called_once()

    def test_client_errors_fail_without_retrying(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "file.bin"
            with patch(
                "download.urllib.request.urlopen",
                side_effect=urllib.error.HTTPError("https://example.invalid", 404, "Not Found", {}, None),
            ) as opener, patch("download.time.sleep"):
                with self.assertRaises(urllib.error.HTTPError):
                    fetch("https://example.invalid/file", destination)
            self.assertEqual(opener.call_count, 1)
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
