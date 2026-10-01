#!/usr/bin/env python3
"""Build a deterministic, content-addressed SICP download from reviewed sources."""
import hashlib
from pathlib import Path
import zipfile
import io
import json

root = Path(__file__).resolve().parents[1]
book = root / "Examples/Books/SICP"
buffer = io.BytesIO()
files = [book / name for name in ("main.typ", "README.md", "ATTRIBUTION.md", "LICENSE", "manifest.json")]
files += sorted((book / "styles").rglob("*.typ")) + sorted((book / "fig").rglob("*.svg"))
assert len(list((book / "fig").rglob("*.svg"))) == 84, "The complete book needs all 84 figures"
with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for file in sorted(files):
        info = zipfile.ZipInfo(file.relative_to(book).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, file.read_bytes(), compresslevel=9)
data = buffer.getvalue()
digest = hashlib.sha256(data).hexdigest()
path = book / ("sicp-" + digest[:12] + ".zip")
path.write_bytes(data)
print(json.dumps({"filename": path.name, "bytes": len(data), "sha256": digest}, indent=2))
