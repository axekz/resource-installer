#Requires -Version 5.1
[CmdletBinding()]
param([string]$RealPack, [switch]$Network)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repo 'src/Core.psm1') -Force -DisableNameChecking
$sevenZip = Join-Path $repo '.cache/7zr.exe'
if (-not (Test-Path -LiteralPath $sevenZip)) { throw 'Run build.ps1 first.' }
$testRoot = Join-Path $repo ('.cache/t-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:passed = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Expect-Code([string]$Code, [scriptblock]$Body) {
    try { & $Body; throw ('Expected failure: ' + $Code) }
    catch { if ($_.Exception.Data['InstallCode'] -ne $Code) { throw } }
}
function Test([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Host ('PASS ' + $Name)
}
function Write-Text([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function New-Game([string]$Library, [string]$Name = 'csgo legacy', [string]$AppId = '4465480') {
    $root = Join-Path $Library ('steamapps/common/' + $Name)
    Write-Text (Join-Path $root 'csgo.exe') 'fixture executable, never run'
    Write-Text (Join-Path $root 'csgo/gameinfo.txt') '"GameInfo" { "game" "Counter-Strike: Global Offensive" }'
    Write-Text (Join-Path $Library ('steamapps/appmanifest_' + $AppId + '.acf')) ('"AppState" { "appid" "' + $AppId + '" "installdir" "' + $Name + '" }')
    return $root
}
function Entry([string]$Path, [long]$Size = 3, [string]$CRC = '11223344', [string]$Attributes = 'A') {
    return "Path = $Path`nSize = $Size`nAttributes = $Attributes`nCRC = $CRC`nEncrypted = -`n"
}
$library = Join-Path $testRoot 'Library A'
$game = New-Game $library
$target = Get-GameTarget $game
$source = Join-Path $testRoot 'source'
Write-Text (Join-Path $source 'materials/axe/test.vmt') 'first material'
Write-Text (Join-Path $source 'sound/axe/test.txt') 'first sound'
$archive = Join-Path $testRoot 'fixture.7z'
Push-Location $source
try { $null = Invoke-SevenZip $sevenZip @('a', '-t7z', $archive, 'materials', 'sound') }
finally { Pop-Location }
$plan = Get-ArchivePlan $sevenZip $archive
$staging = Join-Path $testRoot 'staging'
$null = Invoke-SevenZip $sevenZip @('x', '-y', ('-o' + $staging), $archive)

Test 'VDF parses comments, nested objects, spaces and escaped paths' {
    $vdf = Read-Vdf '// comment
"libraryfolders" { "0" { "path" "D:\\Steam Library" "apps" { "4465480" "1" } } }'
    Assert ($vdf.libraryfolders.'0'.path -eq 'D:\Steam Library') 'Escaped path mismatch'
    Assert ($vdf.libraryfolders.'0'.apps.'4465480' -eq '1') 'Nested app missing'
    Expect-Code InvalidSteamData { Read-Vdf '"root" { "key" }' }
}
Test 'Finds custom Steam root and multiple libraries; deduplicates paths' {
    $steam = Join-Path $testRoot 'Custom Steam'
    $unicodeName = 'Legacy ' + [char]0x6e38 + [char]0x620f
    $other = Join-Path $testRoot 'Library B'
    $otherGame = New-Game $other $unicodeName
    $escapedA = $library.Replace('\', '\\')
    $escapedB = $other.Replace('\', '\\')
    Write-Text (Join-Path $steam 'steamapps/libraryfolders.vdf') ('"libraryfolders" { "0" { "path" "' + $escapedA + '" } "1" { "path" "' + $escapedB + '" } "2" { "path" "' + $escapedA + '" } }')
    $found = @(Find-GameTargets @($steam))
    Assert ($found.Count -eq 2) 'Expected two distinct installations'
    Assert ($otherGame -in $found.Root) 'Unicode installation missing'
}
Test 'Accepts game root or csgo folder' {
    Assert ((Get-GameTarget (Join-Path $game 'csgo')).Root -eq $game) 'csgo folder normalization failed'
}
Test 'Rejects app 730, mismatched manifests, missing manifests and missing Source 1 files' {
    $oldLibrary = Join-Path $testRoot 'App 730'
    $old = New-Game $oldLibrary 'Counter-Strike Global Offensive' '730'
    Assert (@(Find-GameTargets @($oldLibrary)).Count -eq 0) 'Discovered app 730'
    Expect-Code InvalidTarget { Get-GameTarget $old }
    $badLibrary = Join-Path $testRoot 'Bad Manifest'
    $bad = New-Game $badLibrary
    Write-Text (Join-Path $badLibrary 'steamapps/appmanifest_4465480.acf') '"AppState" { "appid" "730" "installdir" "csgo legacy" }'
    Expect-Code InvalidTarget { Get-GameTarget $bad }
    Write-Text (Join-Path $badLibrary 'steamapps/appmanifest_4465480.acf') '"AppState" { "appid" "4465480" "installdir" "different" }'
    Expect-Code InvalidTarget { Get-GameTarget $bad }
    $emptyLibrary = Join-Path $testRoot 'Missing Executable'
    $missing = New-Game $emptyLibrary
    [IO.File]::Delete((Join-Path $missing 'csgo.exe'))
    Expect-Code InvalidTarget { Get-GameTarget $missing }
}
Test 'Finds standalone alongside app 730 without selecting app 730' {
    $bothLibrary = Join-Path $testRoot 'Both Games'
    $null = New-Game $bothLibrary 'CS2' '730'
    $standalone = New-Game $bothLibrary 'Standalone'
    $found = @(Find-GameTargets @($bothLibrary))
    Assert ($found.Count -eq 1 -and $found[0].Root -eq $standalone) 'Selected wrong game'
}
Test 'Archive parser rejects traversal, absolute paths, ADS, reserved names and unexpected roots' {
    foreach ($path in @('..\sound\x', 'sound\..\x', '\sound\x', 'C:\sound\x', 'sound\x:stream', 'cfg\autoexec.cfg', 'models\CON.mdl', 'sound\bad.\x', 'sound\\x')) {
        Expect-Code UnsafeArchive { ConvertFrom-ArchiveListing (Entry $path) }
    }
}
Test 'Archive parser rejects links, encryption and conflicting case-insensitive file names' {
    Expect-Code UnsafeArchive { ConvertFrom-ArchiveListing ((Entry 'sound\test') + 'Symbolic Link = elsewhere') }
    Expect-Code UnsafeArchive { ConvertFrom-ArchiveListing ((Entry 'sound\test') + 'Hard Link = sound\other') }
    Expect-Code UnsafeArchive { ConvertFrom-ArchiveListing ((Entry 'sound\test').Replace('Encrypted = -', 'Encrypted = +')) }
    Expect-Code UnsafeArchive { ConvertFrom-ArchiveListing ((Entry 'sound\Foo') + "`n" + (Entry 'sound\foo' 3 '99887766')) }
    Expect-Code UnsafeArchive { ConvertFrom-ArchiveListing ((Entry 'sound\Foo') + "`n" + (Entry 'sound\foo' 4)) }
    Expect-Code UnsafeArchive { ConvertFrom-ArchiveListing ((Entry 'sound\parent') + "`n" + (Entry 'sound\parent\child')) }
}
Test 'Allows directory case variants and matching size/CRC file aliases from the published pack' {
    $listing = (Entry 'sound' 0 '' 'D') + "`n" + (Entry 'sound\Folder' 0 '' 'D') + "`n" + (Entry 'sound\folder' 0 '' 'D') + "`n" + (Entry 'sound\Folder\Foo') + "`n" + (Entry 'sound\folder\foo')
    $result = ConvertFrom-ArchiveListing $listing
    Assert ($result.Entries.Count -eq 3 -and $result.Bytes -eq 3) 'Aliases not normalized'
}
Test 'Bundled extractor verifies and extracts fixture; staging tree matches listing' {
    $null = Invoke-SevenZip $sevenZip @('t', $archive)
    Assert-StagingTree $staging $plan
    Write-Text (Join-Path $staging 'sound/unexpected.txt') 'unexpected'
    Expect-Code UnsafeArchive { Assert-StagingTree $staging $plan }
    [IO.File]::Delete((Join-Path $staging 'sound/unexpected.txt'))
}
Test 'Corrupt archive is rejected' {
    $corrupt = Join-Path $testRoot 'corrupt.7z'
    Write-Text $corrupt 'not a 7z archive'
    Expect-Code ArchiveError { Get-ArchivePlan $sevenZip $corrupt }
}
Test 'Insufficient space is rejected' {
    Expect-Code InsufficientSpace { Assert-FreeSpace $game 1000000000000000 }
}
Test 'Installation does not query or require game processes to close' {
    $module = Get-Module Core
    & $module { function script:Get-CimInstance { throw 'Installation must not query processes' } }
    try { Copy-Resources $target $staging $plan }
    finally { & $module { Remove-Item Function:Get-CimInstance } }
}
Test 'First install and repeated install preserve unrelated files' {
    Write-Text (Join-Path $target.Game 'cfg/autoexec.cfg') 'personal settings'
    Write-Text (Join-Path $target.Game 'materials/personal.vmt') 'personal material'
    Copy-Resources $target $staging $plan
    Copy-Resources $target $staging $plan
    Assert ([IO.File]::ReadAllText((Join-Path $target.Game 'materials/axe/test.vmt')) -eq 'first material') 'Installed contents mismatch'
    Assert ([IO.File]::ReadAllText((Join-Path $target.Game 'cfg/autoexec.cfg')) -eq 'personal settings') 'Personal config changed'
    Assert ([IO.File]::ReadAllText((Join-Path $target.Game 'materials/personal.vmt')) -eq 'personal material') 'Unrelated asset changed'
    Assert (@(Get-ChildItem -LiteralPath $target.Game -Force -Filter '.axe-*').Count -eq 0) 'Backup leaked after success'
}
Test 'Replacement installs new bytes' {
    Write-Text (Join-Path $target.Game 'materials/axe/test.vmt') 'old material'
    Copy-Resources $target $staging $plan
    Assert ([IO.File]::ReadAllText((Join-Path $target.Game 'materials/axe/test.vmt')) -eq 'first material') 'Replacement failed'
}
Test 'Read-only destination is rejected before copying' {
    $path = Join-Path $target.Game 'materials/axe/test.vmt'
    [IO.File]::SetAttributes($path, [IO.FileAttributes]::ReadOnly)
    try { Expect-Code AccessDenied { Copy-Resources $target $staging $plan } }
    finally { [IO.File]::SetAttributes($path, [IO.FileAttributes]::Normal) }
}
Test 'Exclusive resource lock is reported before any copying' {
    $path = Join-Path $target.Game 'materials/axe/test.vmt'
    $lock = [IO.File]::Open($path, 'Open', 'Read', 'None')
    try { Expect-Code FileLocked { Copy-Resources $target $staging $plan } }
    finally { $lock.Dispose() }
    Assert ([IO.File]::ReadAllText($path) -eq 'first material') 'Locked resource changed'
}
Test 'Read-sharing resource handles permit installation while the game uses resources' {
    $path = Join-Path $target.Game 'materials/axe/test.vmt'
    $handle = [IO.File]::Open($path, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { Copy-Resources $target $staging $plan }
    finally { $handle.Dispose() }
    Assert ([IO.File]::ReadAllText($path) -eq 'first material') 'Shared resource replacement failed'
}
Test 'Copy failure rolls back overwritten files and newly created files' {
    $rollbackLibrary = Join-Path $testRoot 'Rollback'
    $rollbackGame = New-Game $rollbackLibrary
    $rollbackTarget = Get-GameTarget $rollbackGame
    Write-Text (Join-Path $rollbackTarget.Game 'materials/axe/test.vmt') 'original material'
    try { Copy-Resources $rollbackTarget $staging $plan -OnProgress { param($done, $total); if ($done -eq $total) { throw 'Injected copy failure' } }; throw 'Expected injected failure' }
    catch { Assert ($_.Exception.Message -eq 'Injected copy failure') 'Unexpected rollback error' }
    Assert ([IO.File]::ReadAllText((Join-Path $rollbackTarget.Game 'materials/axe/test.vmt')) -eq 'original material') 'Original bytes not restored'
    Assert (-not [IO.File]::Exists((Join-Path $rollbackTarget.Game 'sound/axe/test.txt'))) 'New file survived rollback'
    Assert (@(Get-ChildItem -LiteralPath $rollbackTarget.Game -Force -Filter '.axe-*').Count -eq 0) 'Rollback temporary files leaked'
}
Test 'Destination junction is rejected without touching its target' {
    $linkedLibrary = Join-Path $testRoot 'Linked'
    $linkedGame = New-Game $linkedLibrary
    $linkedTarget = Get-GameTarget $linkedGame
    $outside = Join-Path $testRoot 'outside-link-target'
    [void][IO.Directory]::CreateDirectory($outside)
    $link = Join-Path $linkedTarget.Game 'materials'
    New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    try { Expect-Code UnsafeDestination { Get-CopyPlan $linkedTarget $plan } }
    finally { [IO.Directory]::Delete($link) }
    Assert ([IO.Directory]::GetFileSystemEntries($outside).Count -eq 0) 'Wrote through junction'
}
Test 'Worker reports localized validation errors and logs details' {
    foreach ($locale in @('en', 'zh')) {
        $stateFile = Join-Path $testRoot ('worker-' + $locale + '.ini')
        [IO.File]::WriteAllText($stateFile, "[State]`r`nLocale=$locale`r`n", [Text.Encoding]::Unicode)
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repo '.cache/payload/Worker.ps1') -Action Discover -StateFile $stateFile | Out-Null
        Assert ($LASTEXITCODE -eq 0) 'Discovery worker failed'
        [IO.File]::AppendAllText($stateFile, "Target=$testRoot`r`n", [Text.Encoding]::Unicode)
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repo '.cache/payload/Worker.ps1') -Action Check -StateFile $stateFile | Out-Null
        Assert ($LASTEXITCODE -eq 1) 'Worker accepted invalid target'
        $stateText = [IO.File]::ReadAllText($stateFile)
        Assert ($stateText -match 'Code=InvalidTarget') 'Missing structured error'
        if ($locale -eq 'zh') { Assert ($stateText.Contains([string][char]0x8bf7)) 'Chinese message missing' }
        else { Assert ($stateText.Contains('Select the standalone')) 'English message missing' }
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repo '.cache/payload/Worker.ps1') -Action Cleanup -StateFile $stateFile | Out-Null
        Assert ($LASTEXITCODE -eq 0) 'Worker session cleanup failed'
    }
}
Test 'Worker performs the complete install pipeline against a fixture' {
    $worker = Join-Path $repo '.cache/payload/Worker.ps1'
    $stateFile = Join-Path $testRoot 'worker-install.ini'
    [IO.File]::WriteAllText($stateFile, "[State]`r`nLocale=en`r`n", [Text.Encoding]::Unicode)
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -Action Discover -StateFile $stateFile | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Worker discovery failed'
    $stateText = [IO.File]::ReadAllText($stateFile)
    $work = [regex]::Match($stateText, '(?m)^WorkDir=(.*)\r?$').Groups[1].Value.Trim()
    Assert ([IO.Directory]::Exists($work)) 'Worker session missing'
    $workerGame = New-Game (Join-Path $testRoot 'Worker Game')
    [IO.File]::AppendAllText($stateFile, "Target=$workerGame`r`n", [Text.Encoding]::Unicode)
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -Action Check -StateFile $stateFile | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Worker preflight failed'
    [IO.File]::Copy($archive, (Join-Path $work 'ResourcesPack.7z'))
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -Action Install -StateFile $stateFile | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Worker install failed'
    $log = [regex]::Match([IO.File]::ReadAllText($stateFile), '(?m)^Log=(.*)\r?$').Groups[1].Value.Trim()
    Assert ([IO.File]::ReadAllText($log).Contains('Installation complete.')) 'English progress incorrectly translated'
    Assert ([IO.File]::ReadAllText((Join-Path $workerGame 'csgo/materials/axe/test.vmt')) -eq 'first material') 'Worker did not install bytes'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -Action Cleanup -StateFile $stateFile | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and -not [IO.Directory]::Exists($work)) 'Worker cleanup failed'
}
if ($Network) {
    Test 'INetC reports failed downloads and deletes incomplete output' {
        $compiler = Join-Path $repo '.cache/nsis/nsis-3.13/Bin/makensis.exe'
        & $compiler /V2 (Join-Path $PSScriptRoot 'DownloadProbe.nsi')
        Assert ($LASTEXITCODE -eq 0) 'Download probe compilation failed'
        $output = Join-Path $testRoot 'failed-download.7z'
        $args = '/URL=https://missing-installer-test.invalid/pack.7z /OUTPUT="' + $output + '"'
        $process = Start-Process -FilePath (Join-Path $repo '.cache/DownloadProbe.exe') -ArgumentList $args -WindowStyle Hidden -PassThru
        $null = $process.Handle
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Download failure probe timed out' }
        Assert ($process.ExitCode -eq 1) 'Download failure was not reported'
        Assert (-not [IO.File]::Exists($output)) 'Incomplete download survived'
        Assert ([IO.File]::Exists($output + '.ini')) 'Download result missing'
    }
}
if ($RealPack) {
    Test 'Real pack integrity, extraction and installation into temporary standalone fixture' {
        $realPlan = Get-ArchivePlan $sevenZip (Get-FullPath $RealPack)
        Write-Host ('Real pack: ' + $realPlan.Entries.Count + ' unique entries, ' + $realPlan.Bytes + ' bytes unpacked')
        $null = Invoke-SevenZip $sevenZip @('t', '-bd', '-bsp0', $RealPack)
        $realStaging = Join-Path $testRoot 'real-staging'
        $null = Invoke-SevenZip $sevenZip @('x', '-y', '-bd', '-bsp0', ('-o' + $realStaging), $RealPack)
        Assert-StagingTree $realStaging $realPlan
        $realGame = New-Game (Join-Path $testRoot 'Real Pack Game')
        $realTarget = Get-GameTarget $realGame
        Write-Text (Join-Path $realTarget.Game 'cfg/autoexec.cfg') 'untouched'
        Copy-Resources $realTarget $realStaging $realPlan -OnProgress { param($done, $total); if ($done % 1000 -eq 0) { Write-Host ("Real pack copied $done / $total") } }
        foreach ($entry in $realPlan.Entries) {
            if ($entry.Directory) { continue }
            $sourceHash = (Get-FileHash -LiteralPath (Join-Path $realStaging $entry.Path) -Algorithm SHA256).Hash
            $installedHash = (Get-FileHash -LiteralPath (Join-Path $realTarget.Game $entry.Path) -Algorithm SHA256).Hash
            Assert ($sourceHash -eq $installedHash) ('Installed hash mismatch: ' + $entry.Path)
        }
        Assert ([IO.File]::ReadAllText((Join-Path $realTarget.Game 'cfg/autoexec.cfg')) -eq 'untouched') 'Config changed'
    }
}
Write-Host ("All $script:passed tests passed. Fixtures: $testRoot")
