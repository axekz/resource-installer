# AXE GOKZ Resource Installer

A portable, standalone Windows tool that downloads and installs AXE GOKZ resources
for **standalone CS:GO Legacy, Steam app 4465480**.

**Players do not install this tool.** They download one `.exe` and run it.
There is no setup wizard for the tool, no Python/.NET runtime to download, no
separate 7-Zip installation, no shortcuts, no background service, and no
uninstall registration. Windows PowerShell 5.1, already included in Windows
10/11, runs the bundled helper without opening a console window.

## Player usage

1. Download `AXE-Resource-Installer.exe`, and open it.
2. Confirm the automatically detected game folder and click **Install resources**.
3. Wait for **Resources installed**. If already in game, reconnect to the server to load new resources.

The main screen uses your Windows language automatically. English and 简体中文
can be selected on that screen; it refreshes automatically and preserves the
selected game folder. If several installations
exist, select one. If none are detected, use **Browse** to select the standalone
game folder or its `csgo` subfolder. It must belong to the Steam app 4465480
installation; app 730/CS2 and its old beta branch are not supported.

The tool always downloads the current pack from:

<https://r2.axekz.com/packages/ResourcesPack.7z>

Run the same executable again to refresh resources. Matching resource files
are replaced; unrelated files and personal configuration are preserved.
Downloads can be cancelled or retried. Once copying starts, let it finish or
recover automatically rather than terminating it.

[简体中文使用说明](docs/usage.zh-CN.md)

## Build and test

From this repository on Windows 10/11:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

Build output: `dist/AXE-Resource-Installer.exe`. Only this executable needs to
be distributed. The builder fetches NSIS 3.13, INetC 1.0.5.3, and 7zr 26.04
using the SHA-256 pins in `dependencies.json`. Dependencies and outputs are
ignored by Git. `curl.exe`, included in Windows 10 version 1803 and later,
is used only on the developer machine to fetch build dependencies.

To exercise the actual resource pack without touching a real game:

```powershell
curl.exe --fail --location --proto '=https' --proto-redir '=https' `
  https://r2.axekz.com/packages/ResourcesPack.7z -o .cache/ResourcesPack.7z
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1 `
  -RealPack .cache/ResourcesPack.7z
```

Tests create independent Steam/game fixtures under `.cache/t-*` and leave them
for inspection. They never launch or install into a real CS:GO game. The real
pack test verifies archive CRCs, extracts the pack, installs into a fixture,
and compares every installed file's SHA-256 with the staging copy.

## GitHub releases

[Build and release workflow](.github/workflows/release.yml) tests and builds on
Windows for pushes, pull requests, and manual runs. Pushing a version tag also
publishes a GitHub release containing the portable EXE and `SHA256SUMS.txt`.
The executable's version is taken from the tag. All fixture and download-failure
tests must pass before publishing; CI does not download the full resource pack.
Actions and build dependencies are pinned. Only the publishing job has write
permission, using GitHub's automatic token; no personal token is needed.

After configuring this independent repository's GitHub `origin`:

```powershell
git push -u origin HEAD
git tag -a v1.0.0 -m "AXE GOKZ Resource Installer 1.0.0"
git push origin v1.0.0
```

Use a new `vMAJOR.MINOR.PATCH` tag for each release. Version components must be
at most 65535. To build a matching version locally, pass `-Version 1.0.0` to
`build.ps1`. Manual runs on a branch produce a downloadable Actions artifact;
manual runs on a version tag publish that tag. A failed draft release can be
retried; published release assets are never overwritten by this workflow.
The repository must allow GitHub Actions and the publishing job's
`contents: write` permission. Releases remain unsigned.

## Installation and recovery

Steam registry entries and `libraryfolders.vdf` identify libraries;
`appmanifest_4465480.acf`, its installation directory, `csgo.exe`, and Source 1
`csgo/gameinfo.txt` validate the destination. Game launch metadata is not edited.
CS:GO may stay running during installation. The installer never stops processes.
Only files actually locked against replacement require closing the program using them.

Before extraction, the archive listing is validated. Only `materials`, `models`,
`resource`, and `sound` are permitted. Absolute/traversing paths, Windows device
names, alternate streams, links, encrypted entries, and conflicting file aliases
are rejected. The current pack includes directory aliases and identical sound
file aliases differing only by case; these are accepted only when file sizes
and archive CRCs match. Extraction is isolated and the resulting tree is checked
against the listing before any game file is copied. Archive CRCs are checked
during extraction; a separate full decompression pass is unnecessary.

Every pack file replaces its matching destination without comparing contents.
Existing resource files are backed up by Windows as part of atomic replacement,
using same-directory temporary files. Flat backup names avoid long-path failures. Normal copy failures
restore previous contents and remove newly installed files. If rollback itself
fails, keep the `.axe-resource-backup-*` folder inside the game's `csgo` folder;
the diagnostic log identifies it and `journal.jsonl` maps affected paths to flat
backup filenames.
Abrupt power loss or killing the process can leave this recovery folder and
partially installed resources; there is no automatic crash-recovery service.

Logs: `%LOCALAPPDATA%\AXE\ResourceInstaller\logs`.
Temporary downloads/staging: `%LOCALAPPDATA%\AXE\ResourceInstaller\sessions`.
Normal exit cleans up the current session. Forced termination may leave a
session folder, which can be removed after confirming the tool is no longer running.

Most game folders work with normal permissions. For a protected folder, rerun
as administrator only if the error requests it. Linked game
or asset folders are deliberately rejected rather than followed.

The pack is transported over HTTPS with certificate checks and verified with
7-Zip's archive CRCs. There is no published checksum sidecar or pinned pack hash;
these checks detect damaged downloads but do not independently authenticate the
pack publisher. No website or hosting changes are part of this repository.

The executable is currently unsigned. Windows may display an unknown-publisher
warning depending on its security policy. Release signing can reduce this
distribution obstacle; no signing certificate is configured by this project.

Original code: [MIT](LICENSE). Bundled third-party notices: [licenses](licenses).
NSIS source: <https://sourceforge.net/projects/nsis/files/NSIS%203/3.13/>.
