# One command that rebuilds the Escape Reality MSIX package (1.0.1.0 by
# default, see config.psd1), signs it, and installs it.
#
#   powershell -ExecutionPolicy Bypass -File C:\escape-reality\msix\build-and-install.ps1
#
# This replaces the old two-script one-liner:
#
#   powershell -ExecutionPolicy Bypass -Command "& 'C:\escape-reality\msix\build-msix.ps1'; & 'C:\escape-reality\msix\sign-and-install.ps1'"
#
# Why: with ';' the second script runs even if the first one fails, so a
# failed build could still try to sign/install a stale package. This
# orchestrator runs the two steps in order and stops on the first failure
# ($ErrorActionPreference = 'Stop'), so the exit code tells you whether the
# whole thing worked. It also closes a running Escape Reality window for you
# before installing, so you no longer need to close it by hand to avoid
# 0x80073D02 (pass -NoClose to opt out).
#
# It also bundles the local files a command cannot create -- the model
# weights, model key, and policy files under C:\ProgramData\EscapeReality
# (config.psd1: DataSource) -- into the package under data\. See
# msix\README.md. Windows PowerShell 5.1 compatible.

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.psd1'),
    [string]$PayloadDir = (Join-Path $PSScriptRoot 'payload'),
    [string]$LayoutDir  = (Join-Path $PSScriptRoot 'layout'),
    [string]$OutputMsix = '',
    [string]$DataSource = '',
    [string]$PfxPath    = (Join-Path $PSScriptRoot 'out\EscapeReality.pfx'),
    [string]$PfxPassword = $env:ESCAPE_REALITY_PFX_PASSWORD,
    [switch]$SkipLocalData,
    [switch]$NoClose,
    [switch]$SkipTrustInstall,
    [switch]$Launch,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step 'Step 1 of 2: building MSIX package ...'
& (Join-Path $PSScriptRoot 'build-msix.ps1') `
    -ConfigPath $ConfigPath -PayloadDir $PayloadDir -LayoutDir $LayoutDir `
    -OutputMsix $OutputMsix -DataSource $DataSource `
    -SkipLocalData:$SkipLocalData -Force:$Force

Write-Step 'Step 2 of 2: signing and installing ...'
& (Join-Path $PSScriptRoot 'sign-and-install.ps1') `
    -ConfigPath $ConfigPath -MsixPath $OutputMsix -PfxPath $PfxPath `
    -PfxPassword $PfxPassword -NoClose:$NoClose `
    -SkipTrustInstall:$SkipTrustInstall -Launch:$Launch

Write-Step 'Done. Escape Reality is built, signed, and installed.'
