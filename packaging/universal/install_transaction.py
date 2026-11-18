#!/usr/bin/env python3
"""Snapshot and restore the user-owned paths touched by the universal installer."""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import uuid


MANIFEST = "manifest.json"


def exists(path: Path) -> bool:
    return os.path.lexists(path)


def remove(path: Path) -> None:
    if not exists(path):
        return
    if path.is_symlink() or not path.is_dir():
        path.unlink()
    else:
        shutil.rmtree(path)


def copy_path(source: Path, destination: Path) -> None:
    if source.is_symlink():
        os.symlink(os.readlink(source), destination)
    elif source.is_dir():
        shutil.copytree(source, destination, symlinks=True, copy_function=shutil.copy2)
    else:
        shutil.copy2(source, destination, follow_symlinks=False)


def normalize_targets(paths) -> list[Path]:
    targets = sorted({Path(os.path.abspath(os.fspath(path))) for path in paths}, key=lambda p: (len(p.parts), str(p)))
    for index, target in enumerate(targets):
        for parent in targets[:index]:
            if target == parent or parent in target.parents:
                raise ValueError(f"destinos de transacción solapados: {parent} y {target}")
    return targets


def snapshot(transaction: Path, paths) -> None:
    transaction = Path(os.path.abspath(transaction))
    targets = normalize_targets(paths)
    if exists(transaction):
        st = transaction.lstat()
        if not transaction.is_dir() or transaction.is_symlink() or st.st_uid != os.getuid() or st.st_mode & 0o077:
            raise PermissionError(f"directorio de transacción inseguro: {transaction}")
        if any(transaction.iterdir()):
            raise FileExistsError(f"directorio de transacción no vacío: {transaction}")
    else:
        transaction.mkdir(mode=0o700, parents=True)
    records = []
    try:
        for index, target in enumerate(targets):
            backup = None
            if exists(target):
                backup = f"backup-{index:04d}"
                copy_path(target, transaction / backup)
            missing = []
            parent = target.parent
            while not exists(parent):
                missing.append(str(parent))
                parent = parent.parent
            records.append({"target": str(target), "backup": backup, "created_parents": missing})
        manifest = {"version": 1, "records": records}
        temp = transaction / ".manifest.tmp"
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(manifest, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, transaction / MANIFEST)
    except Exception:
        shutil.rmtree(transaction, ignore_errors=True)
        raise


def _replace_from_backup(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = target.parent / f".{target.name}.omnia-restore-{uuid.uuid4().hex}"
    displaced = target.parent / f".{target.name}.omnia-displaced-{uuid.uuid4().hex}"
    copy_path(source, staged)
    moved_old = False
    try:
        if exists(target):
            os.replace(target, displaced)
            moved_old = True
        os.replace(staged, target)
    except Exception:
        if moved_old and not exists(target) and exists(displaced):
            os.replace(displaced, target)
        raise
    finally:
        remove(staged)
    remove(displaced)


def rollback(transaction: Path) -> None:
    transaction = Path(os.path.abspath(transaction))
    st = transaction.lstat()
    if not transaction.is_dir() or transaction.is_symlink() or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise PermissionError(f"directorio de transacción inseguro: {transaction}")
    manifest_path = transaction / MANIFEST
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("version") != 1 or not isinstance(manifest.get("records"), list):
        raise ValueError("manifiesto de transacción inválido")
    for record in reversed(manifest["records"]):
        if not isinstance(record, dict) or not isinstance(record.get("target"), str):
            raise ValueError("registro de transacción inválido")
        target = Path(record["target"])
        backup = record.get("backup")
        if backup is None:
            remove(target)
        else:
            if not isinstance(backup, str) or Path(backup).name != backup or not backup.startswith("backup-"):
                raise ValueError("ruta de respaldo inválida")
            backup_path = transaction / backup
            if not exists(backup_path):
                raise FileNotFoundError(f"falta respaldo para {target}")
            _replace_from_backup(backup_path, target)
    parents = sorted({Path(p) for r in manifest["records"] for p in r.get("created_parents", [])},
                     key=lambda p: len(p.parts), reverse=True)
    for parent in parents:
        try:
            parent.rmdir()
        except OSError:
            pass
    shutil.rmtree(transaction)


def discard(transaction: Path) -> None:
    shutil.rmtree(transaction, ignore_errors=False)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    begin = sub.add_parser("snapshot")
    begin.add_argument("transaction", type=Path)
    begin.add_argument("targets", nargs="+", type=Path)
    for action in ("rollback", "discard"):
        sub.add_parser(action).add_argument("transaction", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.action == "snapshot":
            snapshot(args.transaction, args.targets)
        elif args.action == "rollback":
            rollback(args.transaction)
        else:
            discard(args.transaction)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"omnia-installer: transacción {args.action}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
