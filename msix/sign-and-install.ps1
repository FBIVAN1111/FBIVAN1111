# Signs the Escape Reality MSIX package and installs it.
#
# What it does:
#   1. Ensures a signing certificate whose Subject matches config.psd1
#      Publisher (creates a self-signed one if needed) and exports it to a
#      PFX, so the certificate Subject always matches the manifest Publisher.
#   2. Trusts the certificate (TrustedPeople store) so Add-AppxPackage
#      accepts the sideloaded package instead of failing with 0x800B0109.
#   3. Signs the package with SignTool (SHA256).
#   4. Closes a running Escape Reality window/process first, so the install
#      does not fail with 0x80073D02 ("another package with the same name is
#      being installed / app is running"). You no longer need to close the
#      window by hand; pass -NoClose to opt out.
#   5. Removes any existing install of the same identity, then installs with
#      Add-AppxPackage (retrying once after re-closing the app on 0x80073D02).
#
# Run it directly, or via build-and-install.ps1 (recommended).
# Windows PowerShell 5.1 compatible.

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.psd1'),
    [string]$MsixPath   = '',
    [string]$PfxPath    = (Join-Path $PSScriptRoot 'out\EscapeReality.pfx'),
    [string]$PfxPassword = $env:ESCAPE_REALITY_PFX_PASSWORD,
    [switch]$NoClose,
    [switch]$SkipTrustInstall,
    [switch]$Launch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')

$config = Get-EscapeConfig -ConfigPath $ConfigPath

if (-not $MsixPath) {
    $MsixPath = Join-Path $PSScriptRoot "out\EscapeReality_$($config.Version)_$($config.ProcessorArchitecture).msix"
}
if (-not (Test-Path -LiteralPath $MsixPath)) {
    throw "MSIX package not found: $MsixPath. Run build-msix.ps1 first, or pass -MsixPath <path>."
}

$publisher = [string]$config.Publisher
$signTool = Find-WindowsSdkTool -ToolName 'SignTool.exe'
Assert-ToolFound -ToolPath $signTool -ToolName 'SignTool.exe'

# --- Certificate -----------------------------------------------------------
Write-Step "Looking for a certificate with Subject '$publisher' ..."
$cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $publisher } |
    Select-Object -First 1

if (-not $cert) {
    Write-Step 'Creating a self-signed certificate for local sideloading ...'
    $cert = New-SelfSignedCertificate -Type Custom -Subject $publisher `
        -KeyUsage DigitalSignature -CertStoreLocation 'Cert:\CurrentUser\My' `
        -HashAlgorithm SHA256 -KeyExportPolicy Exportable -KeyLength 2048
}

if (-not (Test-Path -LiteralPath $PfxPath)) {
    if (-not $PfxPassword) {
        $PfxPassword = Read-Host 'Enter a password for the new PFX file'
    }
    $pfxDir = Split-Path -Parent $PfxPath
    if ($pfxDir -and -not (Test-Path -LiteralPath $pfxDir)) {
        New-Item -ItemType Directory -Path $pfxDir -Force | Out-Null
    }
    Write-Step "Exporting certificate to $PfxPath ..."
    $securePassword = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $securePassword | Out-Null
}

# --- Trust the certificate -------------------------------------------------
if (-not $SkipTrustInstall) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    $store = 'Cert:\CurrentUser\TrustedPeople'
    if ($isAdmin) { $store = 'Cert:\LocalMachine\TrustedPeople' }

    $alreadyTrusted = Get-ChildItem -Path $store -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
    if ($alreadyTrusted) {
        Write-Step "Certificate is already trusted in $store."
    } else {
        try {
            Import-Certificate -FilePath $PfxPath -CertStoreLocation $store | Out-Null
            Write-Step "Trusted the certificate in $store."
        } catch {
            Write-Warning "Could not import the certificate into $store : $($_.Exception.Message)"
            Write-Warning 'Import it manually (right-click the .pfx/.cer > Install certificate > Trusted People), or re-run this script as Administrator. Without this, install fails with 0x800B0109.'
        }
    }
} else {
    Write-Warning 'Skipping certificate trust install (-SkipTrustInstall).'
}

# --- Sign ------------------------------------------------------------------
Write-Step "Signing $MsixPath with SignTool ..."
& $signTool sign /fd SHA256 /f $PfxPath /p $PfxPassword $MsixPath
if ($LASTEXITCODE -ne 0) {
    throw "SignTool sign failed with exit code $LASTEXITCODE. Check that the PFX password is correct and that the certificate Subject matches the manifest Publisher ('$publisher')."
}

# --- Close running app (prevents 0x80073D02) -------------------------------
$processName = [System.IO.Path]::GetFileNameWithoutExtension([string]$config.AppExe)
if (-not $NoClose) {
    $closed = Close-EscapeRealityApp -ProcessName $processName
    if (-not $closed) {
        throw 'Escape Reality is still running, which blocks the install (0x80073D02). Close the window manually and retry, or omit -NoClose.'
    }
}

# --- Install ---------------------------------------------------------------
$identityName = [string]$config.IdentityName
$existing = Get-AppxPackage -Name $identityName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Step "Removing existing package $($existing.PackageFullName) so the new version can install cleanly ..."
    Remove-AppxPackage -Package $existing.PackageFullName
}

$addParams = @{ Path = $MsixPath }
if ((Get-Command Add-AppxPackage).Parameters.ContainsKey('ForceApplicationShutdown')) {
    $addParams['ForceApplicationShutdown'] = $true
}

Write-Step "Installing $MsixPath ..."
try {
    Add-AppxPackage @addParams
} catch {
    $message = $_.Exception.Message
    if ($message -match '0x80073D02' -and -not $NoClose) {
        Write-Warning 'Install hit 0x80073D02 (app still running). Closing Escape Reality and retrying once ...'
        Close-EscapeRealityApp -ProcessName $processName | Out-Null
        Start-Sleep -Seconds 2
        Add-AppxPackage @addParams
    } else {
        throw
    }
}

$installed = Get-AppxPackage -Name $identityName -ErrorAction SilentlyContinue
if (-not $installed) {
    throw "Add-AppxPackage finished but $identityName is not installed. Check the output above and Windows Event Viewer (Application log, Microsoft > Windows > AppXDeployment-Server)."
}
Write-Step "Installed $($installed.Name) version $($installed.Version) from $($installed.InstallLocation)."

if ($Launch) {
    Write-Step 'Launching Escape Reality ...'
    Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$($installed.PackageFamilyName)!EscapeReality"
}
