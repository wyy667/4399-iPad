from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
out = root / 'artifacts' / 'Flash4399-iPad-source.zip'
out.parent.mkdir(exist_ok=True)
entries = ['Flash4399', 'Flash4399.xcodeproj', 'scripts', 'tests',
           '.github',
           'README.md', 'package.json', 'package-lock.json', 'playwright.config.cjs', '.gitignore']
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for entry in entries:
        target = root / entry
        for file in sorted(target.rglob('*')) if target.is_dir() else [target]:
            if file.is_file() and file.suffix not in ['.zip', '.pyc']:
                archive.write(file, Path('Flash4399-iPad') / file.relative_to(root))
with zipfile.ZipFile(out) as archive:
    assert archive.testzip() is None
    assert any(name.endswith('.wasm') for name in archive.namelist())
print(f'{out}: {out.stat().st_size / 1024 / 1024:.1f} MiB')
