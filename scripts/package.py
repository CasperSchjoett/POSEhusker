#!/usr/bin/env python3
"""Build dist/POSEhusker-<version>.zip (top-level POSEhusker/ folder, ready for Interface/AddOns)."""
from pathlib import Path
import hashlib, re, sys, zipfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'src/POSEhusker'

def main():
    toc = (SRC / 'POSEhusker.toc').read_text()
    version = re.search(r'^## Version:\s*(\S+)', toc, re.M).group(1)
    if len(sys.argv) > 1 and sys.argv[1].lstrip('v') != version:
        raise SystemExit(f'Tag {sys.argv[1]} does not match TOC version {version}')
    files = sorted(p for p in SRC.iterdir() if p.is_file() and not p.is_symlink())
    out = ROOT / 'dist' / f'POSEhusker-{version}.zip'
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in files + [ROOT / 'README.md']:
            info = zipfile.ZipInfo('POSEhusker/' + p.name, (2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            z.writestr(info, p.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
    sha = hashlib.sha256(out.read_bytes()).hexdigest()
    (out.parent / (out.name + '.sha256')).write_text(f'{sha}  {out.name}\n')
    print(out); print('SHA-256', sha)

if __name__ == '__main__':
    main()
