"""Signing setup regression checks; only temporary source copies are changed."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('signing_setup', ROOT / 'script/configure_signing.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

class SigningSetupTests(unittest.TestCase):
    def test_custom_setup_reconfiguration_and_conflict(self):
        original, _, _ = setup.prepare(ROOT)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for path, content in original.items():
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_text(content)
            _, changed, _ = setup.prepare(root, 'TEST123456', 'com.example.asunatracks')
            for path, content in changed.items():
                (root / path).write_text(content)
            first, repeated, values = setup.prepare(root, 'TEST123456', 'com.example.asunatracks')
            self.assertEqual(first, repeated)
            self.assertEqual(values[2:], ('group.com.example.asunatracks', 'TEST123456.com.example.asunatracks'))
            setup.prepare(root)  # Check entitlements and runtime groups after configuration.
            _, second, _ = setup.prepare(root, 'NEXT123456', 'another.asunatracks')
            for path, content in second.items():
                (root / path).write_text(content)
            setup.prepare(root)
            project = root / setup.PROJECT
            project.write_text(project.read_text().replace('"PRODUCT_BUNDLE_IDENTIFIER" = "$(ASUNATRACKS_APP_BUNDLE_ID)";', '"PRODUCT_BUNDLE_IDENTIFIER" = "broken.override";', 1))
            before = {p: (root / p).read_bytes() for p in original}
            with self.assertRaisesRegex(ValueError, 'overridden'):
                setup.prepare(root, 'LAST123456', 'third.asunatracks')
            self.assertEqual(before, {p: (root / p).read_bytes() for p in original})

if __name__ == '__main__':
    unittest.main()
