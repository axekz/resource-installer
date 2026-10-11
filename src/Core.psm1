#Requires -Version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$script:AppId = '4465480'
$script:AllowedRoots = @('materials', 'models', 'resource', 'sound')

function Stop-Install([string]$Code, [string]$Detail = '') {
    $exception = New-Object System.InvalidOperationException($Detail)
    $exception.Data['InstallCode'] = $Code
    throw $exception
}

function Read-Vdf([string]$Text) {
    $tokens = [regex]::Matches($Text, '//[^\r\n]*|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+')
    $state = @{ Index = 0; Tokens = @($tokens | Where-Object { -not $_.Value.StartsWith('//') } | ForEach-Object { $_.Value }) }
    function Read-Token($s) {
        if ($s.Index -ge $s.Tokens.Count) { Stop-Install 'InvalidSteamData' 'Unexpected end of VDF' }
        $value = $s.Tokens[$s.Index]; $s.Index++
        if ($value.StartsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
            $value = [regex]::Replace($value, '\\([\\"])', '$1')
        }
        return $value
    }
    function Read-Object($s, [bool]$nested) {
        $result = @{}
        while ($s.Index -lt $s.Tokens.Count) {
            $key = Read-Token $s
            if ($key -eq '}') {
                if (-not $nested) { Stop-Install 'InvalidSteamData' 'Unexpected closing brace' }
                return $result
            }
            if ($key -eq '{' -or $result.ContainsKey($key)) { Stop-Install 'InvalidSteamData' 'Invalid or duplicate VDF key' }
            $value = Read-Token $s
            if ($value -eq '{') { $value = Read-Object $s $true }
            elseif ($value -eq '}') { Stop-Install 'InvalidSteamData' 'Missing VDF value' }
            $result[$key] = $value
        }
        if ($nested) { Stop-Install 'InvalidSteamData' 'Unclosed VDF object' }
        return $result
    }
    return Read-Object $state $false
}

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Assert-NoReparse([string]$Path) {
    $current = Get-FullPath $Path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Stop-Install 'UnsafeDestination' ('Linked path: ' + $current) }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Get-GameTarget([string]$Path) {
    if (-not $Path) { Stop-Install 'InvalidTarget' 'No game folder selected' }
    $root = Get-FullPath $Path
    if ([IO.Path]::GetFileName($root) -ieq 'csgo') { $root = [IO.Path]::GetDirectoryName($root) }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'csgo.exe') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $root 'csgo/gameinfo.txt') -PathType Leaf)) {
        Stop-Install 'InvalidTarget' $root
    }
    $common = [IO.Path]::GetDirectoryName($root)
    if ([IO.Path]::GetFileName($common) -ine 'common') { Stop-Install 'InvalidTarget' 'Select a Steam-installed standalone game' }
    $manifest = Join-Path ([IO.Path]::GetDirectoryName($common)) 'appmanifest_4465480.acf'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Stop-Install 'InvalidTarget' 'App 4465480 manifest is missing' }
    $vdf = Read-Vdf ([IO.File]::ReadAllText($manifest))
    if (-not $vdf.ContainsKey('AppState') -or $vdf.AppState.appid -ne $script:AppId -or
        $vdf.AppState.installdir -ine [IO.Path]::GetFileName($root)) { Stop-Install 'InvalidTarget' 'Standalone manifest does not match folder' }
    $info = [IO.File]::ReadAllText((Join-Path $root 'csgo/gameinfo.txt'))
    if ($info -notmatch '(?i)"?GameInfo"?\s*\{') { Stop-Install 'InvalidTarget' 'Source 1 gameinfo is missing' }
    Assert-NoReparse $root
    return [pscustomobject]@{ Root = $root; Game = (Join-Path $root 'csgo'); Manifest = $manifest }
}

function Get-SteamRoots {
    $roots = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($location in @(
        @('HKCU:\Software\Valve\Steam', 'SteamPath'),
        @('HKLM:\SOFTWARE\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath')
    )) {
        $item = Get-ItemProperty -LiteralPath $location[0] -ErrorAction SilentlyContinue
        if ($item -and $item.PSObject.Properties[$location[1]]) { [void]$roots.Add((Get-FullPath $item.($location[1]))) }
    }
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($base) { [void]$roots.Add((Join-Path $base 'Steam')) }
    }
    return @($roots)
}

function Find-GameTargets([string[]]$SteamRoots = (Get-SteamRoots)) {
    $libraries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($steam in $SteamRoots) {
        [void]$libraries.Add((Get-FullPath $steam))
        $vdfPath = Join-Path $steam 'steamapps/libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $vdfPath)) { continue }
        try {
            $vdf = Read-Vdf ([IO.File]::ReadAllText($vdfPath))
            foreach ($entry in $vdf.libraryfolders.Values) {
                if ($entry -is [hashtable] -and $entry.ContainsKey('path')) { [void]$libraries.Add((Get-FullPath $entry.path)) }
                elseif ($entry -is [string] -and [IO.Path]::IsPathRooted($entry)) { [void]$libraries.Add((Get-FullPath $entry)) }
            }
        } catch { Write-Verbose ('Ignoring invalid library list: ' + $vdfPath) }
    }
    $found = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($library in $libraries) {
        $manifest = Join-Path $library 'steamapps/appmanifest_4465480.acf'
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        try {
            $vdf = Read-Vdf ([IO.File]::ReadAllText($manifest))
            $name = $vdf.AppState.installdir
            if ($name -match '[\\/:]' -or $name -eq '.' -or $name -eq '..') { continue }
            $target = Get-GameTarget (Join-Path $library ('steamapps/common/' + $name))
            if ($found.Add($target.Root)) { $target }
        } catch { Write-Verbose ('Ignoring invalid game: ' + $manifest) }
    }
}

function Assert-WritableDirectory([string]$Path) {
    Assert-NoReparse $Path
    $probe = Join-Path $Path ('.axe-write-check-' + [guid]::NewGuid().ToString('N'))
    try {
        $stream = [IO.File]::Open($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
    } catch { Stop-Install 'AccessDenied' $Path }
    finally { if ([IO.File]::Exists($probe)) { [IO.File]::Delete($probe) } }
}

function Assert-FreeSpace([string]$Path, [long]$RequiredBytes) {
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot((Get-FullPath $Path)))
    if ($RequiredBytes -lt 0 -or $drive.AvailableFreeSpace -lt ($RequiredBytes + 64MB)) {
        Stop-Install 'InsufficientSpace' ('Required bytes: ' + $RequiredBytes + '; volume: ' + $drive.Name)
    }
}

function ConvertTo-NativeArgument([string]$Value) {
    # CommandLineToArgvW quoting, including trailing backslashes.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-SevenZip([string]$SevenZip, [string[]]$Arguments) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $SevenZip
    $start.WorkingDirectory = (Get-Location).ProviderPath
    $start.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output = $stdout.Result
        $errorOutput = $stderr.Result
        if ($process.ExitCode -ne 0) { Stop-Install 'ArchiveError' ($errorOutput + $output) }
        return $output
    } finally { $process.Dispose() }
}

function ConvertFrom-ArchiveListing([string]$Listing) {
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    [long]$total = 0
    foreach ($block in [regex]::Split($Listing.Trim(), '\r?\n\s*\r?\n')) {
        if (-not $block) { continue }
        $properties = @{}
        foreach ($line in ($block -split '\r?\n')) {
            if ($line -notmatch '^([^=]+?) = (.*)$') { Stop-Install 'UnsafeArchive' 'Malformed archive listing' }
            if ($properties.ContainsKey($matches[1])) { Stop-Install 'UnsafeArchive' 'Duplicate archive property' }
            $properties[$matches[1]] = $matches[2]
        }
        $path = [string]$properties['Path']
        $path = $path.Replace('/', '\')
        if (-not $path -or $path -match '^[\\/]' -or $path -match '[:\x00-\x1f<>"|?*]' -or $path.Length -gt 200) {
            Stop-Install 'UnsafeArchive' ('Invalid path: ' + $path)
        }
        $parts = $path -split '\\'
        foreach ($part in $parts) {
            if (-not $part -or $part -eq '.' -or $part -eq '..' -or $part -match '[. ]$' -or
                $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { Stop-Install 'UnsafeArchive' ('Invalid component: ' + $path) }
        }
        if ($parts[0] -cnotin $script:AllowedRoots) { Stop-Install 'UnsafeArchive' ('Unexpected root: ' + $path) }
        if ($properties.ContainsKey('Symbolic Link') -or $properties.ContainsKey('Hard Link') -or
            $properties.ContainsKey('Reparse') -or $properties['Attributes'] -match '(?i)(^|\s)l[rwx-]{9}' -or
            $properties['Encrypted'] -eq '+') { Stop-Install 'UnsafeArchive' ('Link or encrypted entry: ' + $path) }
        $directory = $properties['Attributes'] -match '^D|\s[dD][rwx-]{9}' -or $properties['Folder'] -eq '+'
        [long]$size = 0
        if (-not [long]::TryParse([string]$properties['Size'], [ref]$size) -or $size -lt 0) { Stop-Install 'UnsafeArchive' 'Invalid size' }
        if (-not $directory -and $parts.Count -lt 2) { Stop-Install 'UnsafeArchive' 'Root must be a directory' }
        if ($seen.ContainsKey($path)) {
            if ($directory -and $seen[$path].Directory) { continue }
            # The published pack contains case variants of identical sound files.
            # Windows has one destination for these; permit matching size/CRC only.
            if (-not $directory -and -not $seen[$path].Directory -and $size -eq $seen[$path].Size -and
                $properties['CRC'] -match '^[0-9A-Fa-f]{8}$' -and $properties['CRC'] -eq $seen[$path].CRC) { continue }
            Stop-Install 'UnsafeArchive' ('Conflicting file: ' + $path)
        }
        $entry = [pscustomobject]@{ Path = $path; Directory = [bool]$directory; Size = $size; CRC = $properties['CRC'] }
        $seen[$path] = $entry
        $entries.Add($entry)
        $total += $size
        if ($total -gt 32GB -or $entries.Count -gt 100000) { Stop-Install 'UnsafeArchive' 'Pack exceeds installation limits' }
    }
    if (-not @($entries | Where-Object { -not $_.Directory }).Count) { Stop-Install 'UnsafeArchive' 'No resource files' }
    foreach ($entry in $entries) {
        $parent = [IO.Path]::GetDirectoryName($entry.Path)
        while ($parent) {
            if ($seen.ContainsKey($parent) -and -not $seen[$parent].Directory) { Stop-Install 'UnsafeArchive' 'File used as parent directory' }
            $parent = [IO.Path]::GetDirectoryName($parent)
        }
    }
    return [pscustomobject]@{ Entries = @($entries.ToArray()); Bytes = $total }
}

function Get-ArchivePlan([string]$SevenZip, [string]$Archive) {
    $listing = Invoke-SevenZip $SevenZip @('l', '-slt', '-ba', '-sccUTF-8', '-p-', '--', $Archive)
    return ConvertFrom-ArchiveListing $listing
}

function Assert-StagingTree([string]$Staging, $Plan) {
    Assert-NoReparse $Staging
    $expected = @{}
    foreach ($entry in $Plan.Entries) { if (-not $entry.Directory) { $expected[$entry.Path] = $entry } }
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($Staging)
    $count = 0
    while ($queue.Count) {
        foreach ($item in (Get-ChildItem -LiteralPath $queue.Dequeue() -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Stop-Install 'UnsafeArchive' 'Extracted link' }
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName); continue }
            $relative = $item.FullName.Substring($Staging.Length + 1)
            if (-not $expected.ContainsKey($relative) -or $expected[$relative].Size -ne $item.Length) { Stop-Install 'UnsafeArchive' ('Unexpected extracted file: ' + $relative) }
            $count++
        }
    }
    if ($count -ne $expected.Count) { Stop-Install 'ArchiveError' 'Missing extracted files' }
}

function Get-CopyPlan($Target, $Plan) {
    $files = @($Plan.Entries | Where-Object { -not $_.Directory })
    $checked = @{}
    [long]$backupBytes = 0
    foreach ($entry in $files) {
        $path = Join-Path $Target.Game $entry.Path
        if ($path.Length -gt 240) { Stop-Install 'UnsafeDestination' 'Destination path is too long' }
        Assert-NoReparse $path
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            if ($item.PSIsContainer) { Stop-Install 'UnsafeDestination' ('Directory conflicts with file: ' + $path) }
            if ($item.IsReadOnly) { Stop-Install 'AccessDenied' $path }
            $backupBytes += $item.Length
            try { $stream = [IO.File]::Open($path, 'Open', 'Write', 'Read'); $stream.Dispose() }
            catch {
                $native = $_.Exception
                while ($native.InnerException) { $native = $native.InnerException }
                if (($native.HResult -band 65535) -in @(32, 33)) { Stop-Install 'FileLocked' $path }
                Stop-Install 'AccessDenied' $path
            }
        }
        $parent = [IO.Path]::GetDirectoryName($path)
        while (-not (Test-Path -LiteralPath $parent)) { $parent = [IO.Path]::GetDirectoryName($parent) }
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { Stop-Install 'UnsafeDestination' 'File blocks destination directory' }
        if (-not $checked.ContainsKey($parent)) { Assert-WritableDirectory $parent; $checked[$parent] = $true }
    }
    Assert-FreeSpace $Target.Game ($Plan.Bytes + $backupBytes)
    return $files
}

function Copy-Resources($Target, [string]$Staging, $Plan, [scriptblock]$OnProgress = {}) {
    $files = @(Get-CopyPlan $Target $Plan)
    $transaction = Join-Path $Target.Game ('.axe-resource-backup-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($transaction)
    $journal = New-Object 'System.Collections.Generic.List[object]'
    $createdDirectories = New-Object 'System.Collections.Generic.List[string]'
    $writer = New-Object IO.StreamWriter((Join-Path $transaction 'journal.jsonl'), $false, (New-Object Text.UTF8Encoding($false)))
    $writer.AutoFlush = $true
    $keepBackup = $false
    $inflight = $null
    try {
        foreach ($entry in $files) {
            $destination = Join-Path $Target.Game $entry.Path
            Assert-NoReparse $destination
            $parent = [IO.Path]::GetDirectoryName($destination)
            $missing = New-Object 'System.Collections.Generic.List[string]'
            $ancestor = $parent
            while (-not [IO.Directory]::Exists($ancestor)) { $missing.Add($ancestor); $ancestor = [IO.Path]::GetDirectoryName($ancestor) }
            for ($i = $missing.Count - 1; $i -ge 0; $i--) { [void][IO.Directory]::CreateDirectory($missing[$i]); $createdDirectories.Add($missing[$i]) }
            $existed = [IO.File]::Exists($destination)
            $backup = Join-Path $transaction $entry.Path
            if ($existed) {
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup))
                [IO.File]::Copy($destination, $backup, $false)
            }
            $record = [pscustomobject]@{ Path = $entry.Path; Existed = $existed }
            $writer.WriteLine(($record | ConvertTo-Json -Compress))
            $journal.Add($record)
            $inflight = Join-Path $parent ('.axe-copy-' + [guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Copy((Join-Path $Staging $entry.Path), $inflight, $false)
            if ($existed) { [IO.File]::Replace($inflight, $destination, [NullString]::Value) }
            else { [IO.File]::Move($inflight, $destination) }
            $inflight = $null
            & $OnProgress $journal.Count $files.Count
        }
    } catch {
        $original = $_
        $rollbackErrors = New-Object 'System.Collections.Generic.List[string]'
        for ($i = $journal.Count - 1; $i -ge 0; $i--) {
            $record = $journal[$i]
            $destination = Join-Path $Target.Game $record.Path
            try {
                Assert-NoReparse $destination
                if ($record.Existed) { [IO.File]::Copy((Join-Path $transaction $record.Path), $destination, $true) }
                elseif ([IO.File]::Exists($destination)) { [IO.File]::Delete($destination) }
            } catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        for ($i = $createdDirectories.Count - 1; $i -ge 0; $i--) {
            try { if ([IO.Directory]::Exists($createdDirectories[$i]) -and [IO.Directory]::GetFileSystemEntries($createdDirectories[$i]).Length -eq 0) { [IO.Directory]::Delete($createdDirectories[$i]) } }
            catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        if ($rollbackErrors.Count) {
            $keepBackup = $true
            Stop-Install 'RollbackFailed' ('Backup: ' + $transaction + '; ' + ($rollbackErrors -join '; '))
        }
        throw $original
    } finally {
        $writer.Dispose()
        if ($inflight -and [IO.File]::Exists($inflight)) { [IO.File]::Delete($inflight) }
        if (-not $keepBackup) {
            Assert-NoReparse $transaction
            if (-not $transaction.StartsWith($Target.Game + '\.axe-resource-backup-', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe backup cleanup' }
            Remove-Item -LiteralPath $transaction -Recurse -Force
        }
    }
}

Export-ModuleMember -Function *
