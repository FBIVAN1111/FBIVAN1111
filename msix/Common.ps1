# Shared helpers for the Escape Reality MSIX scripts.
# Dot-sourced by build-msix.ps1, sign-and-install.ps1, and
# build-and-install.ps1. Contains function definitions only (no side effects).
# Written for Windows PowerShell 5.1 (powershell.exe) compatibility.

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-EscapeConfig {
    param([string]$ConfigPath)

    $config = @{
        IdentityName          = 'EscapeReality.App'
        Publisher             = 'CN=Escape Reality'
        PublisherDisplayName  = 'Escape Reality'
        Version               = '1.0.1.0'
        ProcessorArchitecture = 'x64'
        AppExe                = 'EscapeReality.exe'
        DataSource            = 'C:\ProgramData\EscapeReality'
    }

    if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
        $loaded = $null
        if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
            $loaded = Import-PowerShellDataFile -LiteralPath $ConfigPath
        } else {
            # Windows PowerShell 5.1 fallback: a .psd1 containing a single
            # hashtable literal returns that hashtable when dot-sourced.
            $loaded = . $ConfigPath
        }
        if ($loaded -is [hashtable]) {
            foreach ($key in $loaded.Keys) {
                $config[$key] = $loaded[$key]
            }
        }
    }

    return $config
}

function Find-WindowsSdkTool {
    param([Parameter(Mandatory = $true)][string]$ToolName)

    $roots = @()
    if ($env:ProgramFiles) {
        $roots += Join-Path $env:ProgramFiles 'Windows Kits\10\bin'
    }
    if (${env:ProgramFiles(x86)}) {
        $roots += Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    }

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hits = Get-ChildItem -LiteralPath $root -Recurse -Filter $ToolName -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\' } |
            Sort-Object FullName -Descending
        if ($hits) { return $hits[0].FullName }
    }

    return $null
}

function Assert-ToolFound {
    param(
        [string]$ToolPath,
        [Parameter(Mandatory = $true)][string]$ToolName
    )
    if (-not $ToolPath) {
        throw "$ToolName was not found. Install the Windows 10/11 SDK (which provides MakeAppx.exe and SignTool.exe) from https://developer.microsoft.com/windows/downloads/windows-sdk/ and retry."
    }
}

function Close-EscapeRealityApp {
    param(
        [Parameter(Mandatory = $true)][string]$ProcessName,
        [int]$TimeoutSeconds = 10
    )

    $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if (-not $procs) {
        Write-Step 'Escape Reality is not running; nothing to close.'
        return $false
    }

    Write-Step "Closing running Escape Reality process(es): $($procs.Id -join ', ') ..."
    foreach ($proc in $procs) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not stop process $($proc.Id): $($_.Exception.Message)"
        }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $stillRunning = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if (-not $stillRunning) {
            Write-Step 'Escape Reality closed.'
            return $true
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Warning "Escape Reality is still running after ${TimeoutSeconds}s. Close it manually, then retry."
    return $false
}
