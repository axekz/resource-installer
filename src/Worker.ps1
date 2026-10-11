#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Discover', 'Check', 'Install', 'Cleanup')][string]$Action,
    [Parameter(Mandatory = $true)][string]$StateFile
)
$ErrorActionPreference = 'Stop'
# nsExec detects Unicode output. Preserve Chinese phase/progress messages on
# English Windows, whose default console encoding cannot represent them.
[Console]::OutputEncoding = [Text.Encoding]::Unicode
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -Force -DisableNameChecking
$state = @{}
if (Test-Path -LiteralPath $StateFile) {
    foreach ($line in [IO.File]::ReadAllLines($StateFile)) {
        if ($line -match '^([^=\[\]]+)=(.*)$') { $state[$matches[1]] = $matches[2] }
    }
}
$script:UseChinese = $state['Locale'] -eq 'zh'
function Say([string]$English, [string]$ChineseText) {
    $message = if ($script:UseChinese) { $ChineseText } else { $English }
    Write-Output $message
    if ($state['Log']) { [IO.File]::AppendAllText($state.Log, $message + [Environment]::NewLine, [Text.Encoding]::UTF8) }
}
function Save-State {
    $lines = @('[State]') + @($state.Keys | Sort-Object | ForEach-Object { $_ + '=' + ([string]$state[$_] -replace '[\r\n]', ' ') })
    [IO.File]::WriteAllLines($StateFile, [string[]]$lines, [Text.Encoding]::Unicode)
}
function Get-ErrorMessage([string]$Code) {
    $messages = @{
        InvalidTarget = @('Select the standalone CS:GO Legacy installation (Steam app 4465480).', '请选择独立版 CS:GO Legacy 的安装文件夹（Steam 应用 4465480）。')
        InvalidSteamData = @('Steam installation information is invalid. Rescan or select the game folder.', 'Steam 安装信息无效，请重新扫描或选择游戏文件夹。')
        AccessDenied = @('The game folder is not writable. Right-click the installer and choose Run as administrator if this folder is protected.', '游戏文件夹无法写入。如果此文件夹受权限保护，请右键安装程序并选择“以管理员身份运行”。')
        FileLocked = @('A resource file is locked by another program. Close the program using that file and retry. CS:GO may otherwise remain running.', '资源文件被其他程序锁定，请关闭占用该文件的程序后重试。没有文件锁定时可以保持 CS:GO 运行。')
        InsufficientSpace = @('There is not enough free disk space for extraction, installation, and backups. Free some space and retry.', '磁盘空间不足，无法完成解压、安装和备份。请释放空间后重试。')
        UnsafeDestination = @('The selected folder contains a linked, conflicting, or unsupported path. Select a regular Steam installation.', '所选文件夹包含链接、冲突或不受支持的路径，请选择常规 Steam 安装文件夹。')
        UnsafeArchive = @('The pack contains unsupported or conflicting entries. Nothing has been installed. Contact AXE GOKZ support.', '资源包包含不受支持或冲突的文件，尚未安装任何资源。请联系 AXE GOKZ 管理员。')
        ArchiveError = @('The resource pack is incomplete or damaged. Run the installer again to download a fresh copy.', '资源包不完整或已损坏，请重新运行安装程序以重新下载。')
        RollbackFailed = @('Installation and automatic recovery could not finish. Keep the backup folder shown in the diagnostic log and contact AXE GOKZ support.', '安装及自动恢复未能完成。请保留诊断日志中注明的备份文件夹，并联系 AXE GOKZ 管理员。')
        InstallFailed = @('Installation failed. See the diagnostic log for details and retry.', '安装失败，详情请查看诊断日志。请重试。')
    }
    if (-not $messages.ContainsKey($Code)) { $Code = 'InstallFailed' }
    $index = if ($script:UseChinese) { 1 } else { 0 }
    return $messages[$Code][$index]
}
$exitCode = 0
try {
    $base = Join-Path $env:LOCALAPPDATA 'AXE/ResourceInstaller'
    if ($Action -eq 'Discover') {
        $sessionId = [guid]::NewGuid().ToString('N')
        $state.WorkDir = Join-Path $base ('sessions/' + $sessionId)
        $state.Log = Join-Path $base ('logs/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $sessionId + '.log')
        [void][IO.Directory]::CreateDirectory($state.WorkDir)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($state.Log))
        $targets = @(Find-GameTargets)
        $state.Count = $targets.Count
        for ($i = 0; $i -lt $targets.Count; $i++) { $state['Path' + $i] = $targets[$i].Root }
        Say 'Standalone CS:GO Legacy discovery complete.' '独立版 CS:GO Legacy 扫描完成。'
    } elseif ($Action -eq 'Cleanup') {
        $sessions = Get-FullPath (Join-Path $base 'sessions')
        $work = Get-FullPath $state.WorkDir
        if ([IO.Path]::GetDirectoryName($work) -ine $sessions -or [IO.Path]::GetFileName($work) -notmatch '^[0-9a-f]{32}$') { throw 'Unsafe session cleanup path' }
        if (Test-Path -LiteralPath $work) {
            Assert-NoReparse $work
            # Walk without following links before using recursive cleanup.
            $queue = New-Object 'System.Collections.Generic.Queue[string]'
            $queue.Enqueue($work)
            while ($queue.Count) {
                foreach ($item in (Get-ChildItem -LiteralPath $queue.Dequeue() -Force)) {
                    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing cleanup through a link' }
                    if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
                }
            }
            Remove-Item -LiteralPath $work -Recurse -Force
        }
    } else {
        $target = Get-GameTarget $state.Target
        $state.Target = $target.Root
        Assert-WritableDirectory $target.Game
        if ($Action -eq 'Check') {
            Assert-FreeSpace $state.WorkDir 512MB
            Say ('Destination: ' + $target.Game) ('安装位置：' + $target.Game)
        } else {
            $archive = Join-Path $state.WorkDir 'ResourcesPack.7z'
            $sevenZip = Join-Path $PSScriptRoot '7zr.exe'
            $staging = Join-Path $state.WorkDir 'staging'
            Say 'Verifying resource pack paths and available space...' '正在检查资源包路径和可用磁盘空间……'
            $plan = Get-ArchivePlan $sevenZip $archive
            $null = Get-CopyPlan $target $plan
            [long]$required = $plan.Bytes
            if ([IO.Path]::GetPathRoot($staging) -ieq [IO.Path]::GetPathRoot($target.Game)) {
                $required += $plan.Bytes
                foreach ($entry in $plan.Entries) {
                    if (-not $entry.Directory) {
                        $existing = [IO.Path]::Combine($target.Game, $entry.Path)
                        if ([IO.File]::Exists($existing)) { $required += ([IO.FileInfo]$existing).Length }
                    }
                }
            }
            Assert-FreeSpace $state.WorkDir $required
            # Extraction validates archive/data CRCs itself. A separate `t` pass
            # decompresses the whole solid archive twice without adding safety.
            Say 'Extracting and verifying resource checksums...' '正在解压并校验资源包完整性……'
            if (Test-Path -LiteralPath $staging) { Stop-Install 'UnsafeDestination' 'Staging directory already exists' }
            $null = Invoke-SevenZip $sevenZip @('x', '-y', '-bd', '-bsp0', '-sccUTF-8', '-p-', ('-o' + $staging), '--', $archive)
            Assert-StagingTree $staging $plan
            Say 'Installing resources. Please keep this window open...' '正在安装资源，请勿关闭此窗口……'
            Copy-Resources $target $staging $plan -OnProgress {
                param($done, $total)
                if ($done % 100 -eq 0 -or $done -eq $total) { Say ("Installed $done / $total files") ("已安装 $done / $total 个文件") }
            }
            Say 'Installation complete.' '安装完成。'
        }
    }
    $state.Code = 'OK'
    $state.Message = ''
} catch {
    $exitCode = 1
    $code = [string]$_.Exception.Data['InstallCode']
    if (-not $code) { $code = 'InstallFailed' }
    $state.Code = $code
    $state.Message = Get-ErrorMessage $code
    $details = ($_ | Out-String) + $_.ScriptStackTrace
    if ($state['Log']) { [IO.File]::AppendAllText($state.Log, $details + [Environment]::NewLine, [Text.Encoding]::UTF8) }
    Write-Output $state.Message
} finally { Save-State }
exit $exitCode
