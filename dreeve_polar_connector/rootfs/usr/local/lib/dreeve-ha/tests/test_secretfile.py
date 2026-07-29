import os
import tempfile
import unittest
from pathlib import Path

from dreeve_ha import secretfile


class WriteTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "nested" / "secret"

    def test_writes_the_payload_and_creates_parents(self):
        secretfile.write(self.path, b"client-secret")

        self.assertEqual(self.path.read_bytes(), b"client-secret")

    def test_is_mode_600_even_under_a_permissive_umask(self):
        previous = os.umask(0o000)
        self.addCleanup(os.umask, previous)

        secretfile.write(self.path, b"client-secret")

        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_tightens_an_existing_looser_file_and_truncates_it(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(b"much longer previous content")
        self.path.chmod(0o644)

        secretfile.write(self.path, b"short")

        self.assertEqual(self.path.read_bytes(), b"short")
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
