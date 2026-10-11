# AXE GOKZ Resource Installer

- Only support standalone Windows Source 1 CS:GO, Steam app 4465480. Never fall back to app 730.
- Read README.md before changes. Keep both English and Simplified Chinese messages in sync.
- Build with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build.ps1`.
- Test with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/run.ps1`.
- Use temporary Steam/game fixtures. Never install into a real game folder during automated tests.
- Preserve unrelated game files. Validate archive entries before extraction and destination paths before writes.
- Dependency downloads must match dependencies.json SHA-256 pins. Never disable TLS verification.
- Do not commit .cache, dist, diagnostic logs, resource packs, or personal Steam paths.
