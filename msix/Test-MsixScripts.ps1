# Preflight checks for the Escape Reality MSIX scripts. Does NOT build,
# sign, or install anything -- it only reports what is ready and what is
# missing, so you can paste the output here if the real command fails.
#
#   powershell -ExecutionPolicy Bypass -File C:\escape-reality\msix\Test-MsixScripts.ps1
#
# Windows PowerShell 5.1 compatible.

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.psd1'),
    [string]$PayloadDir = (Join-Path $PSScriptRoot 'payload')
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Common.ps1')

$failures = @()
$warnings = @()

function Report-Pass { param([string]$Message) Write-Host "PASS  $Message" -ForegroundColor Green }
function Report-Warn { param([string]$Message) Write-Host "WARN  $Message" -ForegroundColor Yellow; $script:warnings += $Message }
function Report-Fail { param([string]$Message) Write-Host "FAIL  $Message" -ForegroundColor Red; $script:failures += $Message }

Write-Host 'Escape Reality MSIX preflight'
Write-Host '-----------------------------'

# PowerShell version
if ($PSVersionTable.PSVersion -ge [version]'5.1') {
    Report-Pass "PowerShell $($PSVersionTable.PSVersion) (5.1+)"
} else {
    Report-Fail "PowerShell $($PSVersionTable.PSVersion) is too old; use Windows PowerShell 5.1 or newer."
}

# Config
$config = Get-EscapeConfig -ConfigPath $ConfigPath
if ([string]$config.Version -match '^\d+\.\d+\.\d+\.0$') {
    Report-Pass "Config version $($config.Version)"
} else {
    Report-Fail "Config version '$($config.Version)' must be four numbers ending in .0 (e.g. 1.0.1.0)."
}
if ([string]$config.Publisher -like 'CN=*') {
    Report-Pass "Publisher $($config.Publisher)"
} else {
    Report-Warn "Publisher '$($config.Publisher)' does not start with CN=; the signing certificate Subject must match it exactly."
}

# SDK tools
$makeAppx = Find-WindowsSdkTool -ToolName 'MakeAppx.exe'
if ($makeAppx) { Report-Pass "MakeAppx.exe: $makeAppx" } else { Report-Fail 'MakeAppx.exe not found. Install the Windows SDK.' }
$signTool = Find-WindowsSdkTool -ToolName 'SignTool.exe'
if ($signTool) { Report-Pass "SignTool.exe: $signTool" } else { Report-Fail 'SignTool.exe not found. Install the Windows SDK.' }

# Payload
$appExePath = Join-Path $PayloadDir ([string]$config.AppExe)
if (Test-Path -LiteralPath $appExePath) {
    Report-Pass "Payload exe: $appExePath"
} else {
    Report-Fail "Payload exe missing: $appExePath. Put the built window/page exe in msix\payload (see msix\payload\README.md)."
}

# Local data (weights, key, policies)
$dataSource = [string]$config.DataSource
if (Test-Path -LiteralPath $dataSource) {
    $count = (Get-ChildItem -LiteralPath $dataSource -Recurse -File -ErrorAction SilentlyContinue).Count
    if ($count -gt 0) {
        Report-Pass "Local data: $dataSource ($count file(s) will be bundled into data\)"
    } else {
        Report-Warn "Local data folder exists but is empty: $dataSource"
    }
} else {
    Report-Fail "Local data folder missing: $dataSource. The model weights, model key, and policy files must live there (or set DataSource in config.psd1)."
}

# Manifest template
$templatePath = Join-Path $PSScriptRoot 'AppxManifest.xml'
try {
    [xml]$null = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
    Report-Pass 'AppxManifest.xml template is valid XML'
} catch {
    Report-Fail "AppxManifest.xml template is not valid XML: $($_.Exception.Message)"
}

# Assets
$requiredAssets = @('StoreLogo.png', 'Square44x44Logo.png', 'Square71x71Logo.png', 'Square150x150Logo.png', 'Square310x310Logo.png', 'Wide310x150Logo.png')
foreach ($asset in $requiredAssets) {
    $assetPath = Join-Path $PSScriptRoot "Assets\$asset"
    if (Test-Path -LiteralPath $assetPath) {
        Report-Pass "Asset: $asset"
    } else {
        Report-Fail "Asset missing: $assetPath"
    }
}

# Script syntax (parse only, does not run them)
foreach ($scriptName in @('Common.ps1', 'build-msix.ps1', 'sign-and-install.ps1', 'build-and-install.ps1')) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Report-Fail "$scriptName has $($errors.Count) syntax error(s): $($errors[0].Message)"
    } else {
        Report-Pass "$scriptName parses cleanly"
    }
}

# Developer Mode (needed to sideload a runFullTrust package)
$devModePath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$devMode = $null
try { $devMode = (Get-ItemProperty -LiteralPath $devModePath -Name DeveloperModeEnabled -ErrorAction Stop).DeveloperModeEnabled } catch { }
if ($devMode -eq 1) {
    Report-Pass 'Developer Mode is on (required for sideloading)'
} else {
    Report-Warn 'Developer Mode appears off. Enable it: Settings > Privacy & security > For developers > Developer Mode.'
}

Write-Host '-----------------------------'
Write-Host "Result: $($failures.Count) failure(s), $($warnings.Count) warning(s)."
if ($failures.Count -gt 0) {
    throw "Preflight failed with $($failures.Count) failure(s). Fix the FAIL lines above, then run build-and-install.ps1."
}
Write-Host 'Preflight passed. You can run build-and-install.ps1 now.'
