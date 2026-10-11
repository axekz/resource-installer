# Validation

Validated on Windows on 2026-10-11 with Windows PowerShell 5.1 and the pinned
NSIS, INetC and 7zr dependencies.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1 `
  -Network -RealPack .cache/ResourcesPack.7z
```

All 23 checks passed. Coverage includes Steam VDF parsing, custom libraries,
Unicode paths, multiple installations, app 730 rejection, manifest validation,
unsafe archives, case aliases, corrupt archives, free space, permissions,
exclusive file locks, open shared resource handles, replacement, preservation,
rollback, junction rejection, both helper languages, the complete helper pipeline,
and failed INetC downloads. Fixtures contain dummy game executables that are never
launched. Installation does not query processes or require the game to close.

The real pack contained 3,953 unique entries, including 3,526 files, and
2,234,305,800 unpacked bytes. Its integrity check and extraction succeeded.
Every installed file's SHA-256 matched the extracted source, and unrelated
configuration remained unchanged. The pack itself is intentionally not pinned.

Manual interface inspection confirmed English-to-Chinese and Chinese-to-English
switching in the same window, with the folder preserved and no second installer
launched. These checks were performed while the user's existing CS:GO session
remained open. No test wrote into a live game installation.

The unsigned portable executable is approximately 376 KiB. Build output and
downloaded dependencies are ignored; only the executable needs distribution.
