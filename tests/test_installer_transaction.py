import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "packaging/universal"))
from install_transaction import rollback, snapshot


class InstallTransaction(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_rollback_restores_files_dirs_links_and_removes_new_paths(self):
        file = self.root / "config" / "service.conf"
        file.parent.mkdir()
        file.write_text("old service\n")
        tree = self.root / "share" / "omnia"
        tree.mkdir(parents=True)
        (tree / "module.qml").write_text("old qml\n")
        (tree / "shortcut").symlink_to("module.qml")
        untouched = self.root / "share" / "user-data"
        untouched.write_text("keep\n")
        new_path = self.root / "bin" / "omnia-core"
        txn = self.root / "txn"

        snapshot(txn, [file, tree, new_path])
        file.write_text("new service\n")
        (tree / "module.qml").write_text("new qml\n")
        (tree / "new-file").write_text("temporary\n")
        new_path.parent.mkdir()
        new_path.write_text("new binary\n")

        rollback(txn)

        self.assertEqual(file.read_text(), "old service\n")
        self.assertEqual((tree / "module.qml").read_text(), "old qml\n")
        self.assertEqual((tree / "shortcut").readlink(), Path("module.qml"))
        self.assertFalse((tree / "new-file").exists())
        self.assertFalse(new_path.exists())
        self.assertEqual(untouched.read_text(), "keep\n")
        self.assertFalse(txn.exists())

    def test_overlapping_targets_are_rejected_before_snapshot(self):
        parent = self.root / "data"
        child = parent / "qml"
        txn = self.root / "txn"
        with self.assertRaises(ValueError):
            snapshot(txn, [child, parent])
        self.assertFalse(txn.exists())

    def test_rejects_symlink_transaction_directory(self):
        actual = self.root / "actual"
        actual.mkdir()
        txn = self.root / "txn"
        txn.symlink_to(actual, target_is_directory=True)
        with self.assertRaises(PermissionError):
            snapshot(txn, [self.root / "target"])
        self.assertEqual(list(actual.iterdir()), [])

    def test_rollback_rejects_symlink_transaction_directory(self):
        actual = self.root / "actual"
        actual.mkdir()
        txn = self.root / "txn"
        txn.symlink_to(actual, target_is_directory=True)
        with self.assertRaises(PermissionError):
            rollback(txn)

    def test_rollback_rejects_manifest_backup_path_escape(self):
        txn = self.root / "txn"
        txn.mkdir(mode=0o700)
        (txn / "manifest.json").write_text(
            '{"version":1,"records":[{"target":"/tmp/should-not-be-touched",'
            '"backup":"../outside"}]}\n'
        )
        with self.assertRaises(ValueError):
            rollback(txn)


if __name__ == "__main__":
    unittest.main()
