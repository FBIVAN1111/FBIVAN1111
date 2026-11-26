# Builds the Escape Reality MSIX package (version from config.psd1, default 1.0.1.0).
#
# What it does:
#   1. Stages the payload (msix\payload: the window/page exe + its files)
#      into msix\layout.
#   2. Copies the local files that are NOT in the repo and NOT in the payload
#      -- model weights, model key, and policy files -- from
#      C:\ProgramData\EscapeReality (config.psd1: DataSource) into
#      layout\data, so the installed app finds them next to the exe.
#   3. Generates AppxManifest.xml from the template + config.psd1.
#   4. Copies Assets\ and packs the package with MakeAppx.
#
# Run it directly, or via build-and-install.ps1 (recommended: one command
# that also signs and installs). Windows PowerShell 5.1 compatible.

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.psd1'),
    [string]$PayloadDir = (Join-Path $PSScriptRoot 'payload'),
    [string]$LayoutDir  = (Join-Path $PSScriptRoot 'layout'),
    [string]$OutputMsix = '',
    [string]$DataSource = '',
    [switch]$SkipLocalData,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')

$config = Get-EscapeConfig -ConfigPath $ConfigPath

if (-not $OutputMsix) {
    $OutputMsix = Join-Path $PSScriptRoot "out\EscapeReality_$($config.Version)_$($config.ProcessorArchitecture).msix"
}
if (-not $DataSource) {
    $DataSource = [string]$config.DataSource
}

# --- Preflight -------------------------------------------------------------
if ([string]$config.Version -notmatch '^\d+\.\d+\.\d+\.0$') {
    throw "Config Version '$($config.Version)' is invalid. MSIX versions must be four numbers with the last one 0, e.g. 1.0.1.0."
}
if (-not (Test-Path -LiteralPath $PayloadDir)) {
    throw "Payload folder not found: $PayloadDir. Put the built EscapeReality.exe (window/page) and its files in msix\payload first. See msix\payload\README.md."
}
$appExePath = Join-Path $PayloadDir ([string]$config.AppExe)
if (-not (Test-Path -LiteralPath $appExePath)) {
    throw "App executable not found: $appExePath. The payload must contain $($config.AppExe) at its root."
}
$manifestTemplate = Join-Path $PSScriptRoot 'AppxManifest.xml'
if (-not (Test-Path -LiteralPath $manifestTemplate)) {
    throw "Manifest template not found: $manifestTemplate"
}
$assetsDir = Join-Path $PSScriptRoot 'Assets'
if (-not (Test-Path -LiteralPath $assetsDir)) {
    throw "Assets folder not found: $assetsDir"
}
if (-not $SkipLocalData -and -not (Test-Path -LiteralPath $DataSource)) {
    throw "Local data folder not found: $DataSource. The model weights, model key, and policy files must live there, or pass -DataSource <path> / -SkipLocalData. See msix\README.md."
}

$makeAppx = Find-WindowsSdkTool -ToolName 'MakeAppx.exe'
Assert-ToolFound -ToolPath $makeAppx -ToolName 'MakeAppx.exe'

# Safety: only ever clean a layout folder inside this msix folder.
$root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$layoutFull = [System.IO.Path]::GetFullPath($LayoutDir)
if ($layoutFull -eq $root -or -not $layoutFull.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use layout folder outside the msix folder: $layoutFull"
}

# --- Stage layout ----------------------------------------------------------
Write-Step "Staging package layout in $layoutFull ..."
if (Test-Path -LiteralPath $layoutFull) {
    if (-not $Force) {
        Write-Warning "Layout folder already exists and will be cleaned: $layoutFull (pass -Force to skip this prompt)."
        $answer = Read-Host 'Delete it and continue? (y/N)'
        if ($answer -ne 'y') { throw 'Aborted by user.' }
    }
    Remove-Item -LiteralPath $layoutFull -Recurse -Force
}
New-Item -ItemType Directory -Path $layoutFull -Force | Out-Null

Write-Step "Copying payload from $PayloadDir ..."
Copy-Item -Path (Join-Path $PayloadDir '*') -Destination $layoutFull -Recurse -Force

# --- Bundle local files (weights, key, policies) ---------------------------
if (-not $SkipLocalData) {
    Write-Step "Bundling local files from $DataSource into layout\data ..."
    $dataDest = Join-Path $layoutFull 'data'
    New-Item -ItemType Directory -Path $dataDest -Force | Out-Null
    Copy-Item -Path (Join-Path $DataSource '*') -Destination $dataDest -Recurse -Force

    $dataFiles = Get-ChildItem -LiteralPath $dataDest -Recurse -File
    if (-not $dataFiles) {
        Write-Warning "No files were copied from $DataSource. The package will be built without model weights/key/policies."
    } else {
        $listing = @('Bundled from: ' + $DataSource, 'Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), '')
        foreach ($file in $dataFiles) {
            $relative = $file.FullName.Substring($dataDest.Length + 1)
            $listing += ('{0}  ({1} bytes)' -f $relative, $file.Length)
        }
        Set-Content -LiteralPath (Join-Path $dataDest 'MANIFEST.txt') -Value $listing -Encoding UTF8
        Write-Step "Bundled $($dataFiles.Count) local file(s) into data\ (see data\MANIFEST.txt)."
    }
} else {
    Write-Warning 'Skipping local data bundling (-SkipLocalData). The package will contain only the window/page payload.'
}

# --- Generate manifest -----------------------------------------------------
Write-Step 'Generating AppxManifest.xml from template + config ...'
$manifest = Get-Content -LiteralPath $manifestTemplate -Raw -Encoding UTF8
$manifest = $manifest.Replace('__IDENTITY_NAME__', [string]$config.IdentityName)
$manifest = $manifest.Replace('__PUBLISHER__', [string]$config.Publisher)
$manifest = $manifest.Replace('__PUBLISHER_DISPLAY_NAME__', [string]$config.PublisherDisplayName)
$manifest = $manifest.Replace('__VERSION__', [string]$config.Version)
$manifest = $manifest.Replace('__ARCHITECTURE__', [string]$config.ProcessorArchitecture)
if ($manifest -match '__[A-Z_]+__') {
    throw "Manifest still contains an unreplaced token: $($Matches[0]). Check AppxManifest.xml and config.psd1."
}
try {
    [xml]$null = $manifest
} catch {
    throw "Generated AppxManifest.xml is not valid XML: $($_.Exception.Message)"
}
Set-Content -LiteralPath (Join-Path $layoutFull 'AppxManifest.xml') -Value $manifest -Encoding UTF8

Write-Step 'Copying Assets ...'
Copy-Item -Path (Join-Path $assetsDir '*.png') -Destination (Join-Path $layoutFull 'Assets') -Recurse -Force

# --- Pack ------------------------------------------------------------------
$outDir = Split-Path -Parent $OutputMsix
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Write-Step "Packing MSIX with MakeAppx ($makeAppx) ..."
& $makeAppx pack /d $layoutFull /p $OutputMsix /o
if ($LASTEXITCODE -ne 0) {
    throw "MakeAppx pack failed with exit code $LASTEXITCODE. See the MakeAppx output above."
}

$hash = Get-FileHash -LiteralPath $OutputMsix -Algorithm SHA256
$size = (Get-Item -LiteralPath $OutputMsix).Length
Write-Step "Built $OutputMsix ($size bytes, SHA256 $($hash.Hash))."
Write-Step 'Next: sign and install with sign-and-install.ps1, or run build-and-install.ps1 for both steps.'
