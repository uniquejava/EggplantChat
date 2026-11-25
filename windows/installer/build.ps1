param(
    [string]$IsccPath,
    [string]$RuntimeDir,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Push-Location $repoRoot
try {
    if (-not $SkipBuild) {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build failed.' }
    }
    if (-not $IsccPath) {
        $candidates = @(
            (Join-Path $repoRoot 'build\installer-tools\inno\ISCC.exe'),
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 7\ISCC.exe"
        )
        $IsccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $IsccPath) { throw 'Install Inno Setup 6 or 7, or supply -IsccPath.' }
    if (-not $RuntimeDir) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path -LiteralPath $vswhere) {
            $vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
            if ($vsRoot) {
                $RuntimeDir = Get-ChildItem "$vsRoot\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT" -Directory |
                    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
            }
        }
    }
    if (-not $RuntimeDir -or -not (Test-Path "$RuntimeDir\vcruntime140.dll")) {
        throw 'Visual C++ x64 runtime not found. Supply -RuntimeDir pointing to Microsoft.VC143.CRT.'
    }
    $releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
    if (-not (Test-Path "$releaseDir\eggplant_chat.exe")) { throw 'Release executable not found.' }
    $outputDir = Join-Path $repoRoot 'build\installer'
    $stagingDir = Join-Path $outputDir ('staging-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    Copy-Item "$releaseDir\*" -Destination $stagingDir -Recurse
    Copy-Item "$RuntimeDir\*.dll" -Destination $stagingDir
    $versionMatch = Select-String -Path pubspec.yaml -Pattern '^version:\s*([^+\s]+)'
    $appVersion = $versionMatch.Matches[0].Groups[1].Value
    $revision = & git rev-parse --short HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot determine Git revision.' }
    & $IsccPath "/DAppVersion=$appVersion" "/DBuildRevision=$revision" "/DSourceDir=$stagingDir" "/DOutputDir=$outputDir" (Join-Path $PSScriptRoot 'eggplant_chat.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
    $installer = Join-Path $outputDir "EggplantChat-$appVersion-$revision-windows-x64-setup.exe"
    $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($installer))" | Set-Content -LiteralPath "$installer.sha256" -Encoding ascii
    Get-Item -LiteralPath $installer
} finally {
    Pop-Location
}
