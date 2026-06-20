# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for DropFX backend
# Run: pyinstaller assets/dropfx_backend.spec --distpath assets/

a = Analysis(
    ['dropfx_backend.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=['wave', 'struct', 'http.server', 'threading'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter', 'unittest', 'email', 'xml', 'pydoc'],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='dropfx_backend',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
