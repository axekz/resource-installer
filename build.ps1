#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cache = Join-Path $root '.cache'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $cache, $dist -Force | Out-Null
$dependencies = Get-Content -LiteralPath (Join-Path $root 'dependencies.json') -Raw | ConvertFrom-Json
foreach ($entry in $dependencies.PSObject.Properties) {
    $dep = $entry.Value
    $file = Join-Path $cache $dep.file
    if (-not (Test-Path -LiteralPath $file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $dep.sha256) {
        Write-Host ('Downloading ' + $entry.Name + ' ' + $dep.version)
        # curl is built into supported Windows; SourceForge sometimes returns HTML to other clients.
        & curl.exe --fail --location --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 30 --output $file $dep.url
        if ($LASTEXITCODE -ne 0) { throw ('Dependency download failed: ' + $entry.Name) }
    }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $dep.sha256) {
        throw ('SHA-256 mismatch: ' + $dep.file + '. Do not use this download.')
    }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($name in @('nsis', 'inetc')) {
    $destination = Join-Path $cache $name
    $marker = Join-Path $destination '.verified-sha256'
    $dep = $dependencies.$name
    if (-not (Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne $dep.sha256) {
        if (Test-Path -LiteralPath $destination) {
            $resolved = [IO.Path]::GetFullPath($destination)
            if (-not $resolved.StartsWith($cache + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cache path' }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
        [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $cache $dep.file), $destination)
        [IO.File]::WriteAllText($marker, $dep.sha256)
    }
}
# Windows PowerShell needs a BOM for Chinese source text. Keep source files UTF-8,
# generate the BOM-bearing payload here so checkout encoding cannot break the UI.
$payload = Join-Path $cache 'payload'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $cache '7zr.exe') -Destination (Join-Path $payload '7zr.exe') -Force
foreach ($name in @('Core.psm1', 'Worker.ps1')) {
    $text = [IO.File]::ReadAllText((Join-Path $root ('src/' + $name)))
    [IO.File]::WriteAllText((Join-Path $payload $name), $text, (New-Object Text.UTF8Encoding($true)))
}
# NSIS freezes LangString tables at startup. Runtime variables allow the entire
# interface to switch language in place without launching another executable.
$strings = [IO.File]::ReadAllText((Join-Path $root 'src/strings.json')) | ConvertFrom-Json
$keys = @($strings.en.PSObject.Properties.Name)
if ((($keys | Sort-Object) -join ',') -ne (($strings.zh.PSObject.Properties.Name | Sort-Object) -join ',')) { throw 'Language keys must match' }
$languageSource = New-Object 'System.Collections.Generic.List[string]'
foreach ($key in $keys) { $languageSource.Add('Var Text_' + $key) }
$languageSource.Add('Function LoadLanguage')
$languageSource.Add('  ${If} $UiLanguage == "zh"')
foreach ($locale in @('zh', 'en')) {
    if ($locale -eq 'en') { $languageSource.Add('  ${Else}') }
    foreach ($key in $keys) {
        $value = ([string]$strings.$locale.$key).Replace('$', '$$').Replace('"', '$\"').Replace("`r", '').Replace("`n", '$\r$\n')
        $languageSource.Add('    StrCpy $Text_' + $key + ' "' + $value + '"')
    }
}
$languageSource.Add('  ${EndIf}')
$languageSource.Add('FunctionEnd')
[IO.File]::WriteAllLines((Join-Path $cache 'RuntimeLanguage.nsh'), $languageSource, (New-Object Text.UTF8Encoding($true)))
$compiler = Join-Path $cache 'nsis/nsis-3.13/Bin/makensis.exe'
Push-Location $root
try {
    & $compiler /V3 /INPUTCHARSET UTF8 src/Installer.nsi
    if ($LASTEXITCODE -ne 0) { throw 'NSIS compilation failed' }
} finally { Pop-Location }
$output = Join-Path $dist 'AXE-Resource-Installer.exe'
Get-Item -LiteralPath $output | Select-Object FullName, Length
Get-FileHash -LiteralPath $output -Algorithm SHA256
