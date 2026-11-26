# Pester tests for the Escape Reality MSIX scripts.
# Run on Windows with:  Invoke-Pester .\msix\tests
# (Install-Module Pester -Scope CurrentUser -Force if Pester is missing.)
# These tests check structure and syntax only; they never build, sign, or
# install anything.

$MsixRoot = Split-Path -Parent $PSScriptRoot

Describe 'AppxManifest.xml template' {
    It 'is valid XML' {
        $path = Join-Path $MsixRoot 'AppxManifest.xml'
        { [xml]$null = Get-Content -LiteralPath $path -Raw -Encoding UTF8 } | Should -Not -Throw
    }

    It 'contains every token that build-msix.ps1 replaces' {
        $text = Get-Content -LiteralPath (Join-Path $MsixRoot 'AppxManifest.xml') -Raw -Encoding UTF8
        foreach ($token in @('__IDENTITY_NAME__', '__PUBLISHER__', '__PUBLISHER_DISPLAY_NAME__', '__VERSION__', '__ARCHITECTURE__')) {
            $text | Should -Match ([regex]::Escape($token))
        }
    }

    It 'declares the runFullTrust capability for the packaged Win32 app' {
        $text = Get-Content -LiteralPath (Join-Path $MsixRoot 'AppxManifest.xml') -Raw -Encoding UTF8
        $text | Should -Match 'runFullTrust'
    }
}

Describe 'config.psd1' {
    It 'loads as a hashtable with a valid MSIX version' {
        $config = . (Join-Path $MsixRoot 'config.psd1')
        $config | Should -BeOfType [hashtable]
        $config.Version | Should -Match '^\d+\.\d+\.\d+\.0$'
    }

    It 'has a Publisher starting with CN= (must match the signing certificate)' {
        $config = . (Join-Path $MsixRoot 'config.psd1')
        $config.Publisher | Should -BeLike 'CN=*'
    }
}

Describe 'PowerShell scripts' {
    It 'parse without syntax errors' {
        foreach ($name in @('Common.ps1', 'build-msix.ps1', 'sign-and-install.ps1', 'build-and-install.ps1', 'Test-MsixScripts.ps1')) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $MsixRoot $name), [ref]$tokens, [ref]$errors)
            $errors | Should -BeNullOrEmpty -Because "$name should parse cleanly"
        }
    }

    It 'Common.ps1 defines the shared helpers' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $MsixRoot 'Common.ps1'), [ref]$tokens, [ref]$errors)
        $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            ForEach-Object { $_.Name }
        foreach ($expected in @('Write-Step', 'Get-EscapeConfig', 'Find-WindowsSdkTool', 'Assert-ToolFound', 'Close-EscapeRealityApp')) {
            $functions | Should -Contain $expected
        }
    }

    It 'build-and-install.ps1 runs both steps in order' {
        $text = Get-Content -LiteralPath (Join-Path $MsixRoot 'build-and-install.ps1') -Raw -Encoding UTF8
        $buildIndex = $text.IndexOf('build-msix.ps1')
        $signIndex = $text.IndexOf('sign-and-install.ps1')
        $buildIndex | Should -BeGreaterThan -1
        $signIndex | Should -BeGreaterThan -1
        $buildIndex | Should -BeLessThan $signIndex
    }

    It 'sign-and-install.ps1 closes the running app before installing (0x80073D02)' {
        $text = Get-Content -LiteralPath (Join-Path $MsixRoot 'sign-and-install.ps1') -Raw -Encoding UTF8
        $text | Should -Match 'Close-EscapeRealityApp'
        $text | Should -Match '0x80073D02'
    }

    It 'build-msix.ps1 bundles the local data folder into data\' {
        $text = Get-Content -LiteralPath (Join-Path $MsixRoot 'build-msix.ps1') -Raw -Encoding UTF8
        $text | Should -Match 'DataSource'
        $text | Should -Match "'data'"
    }
}

Describe 'Assets' {
    It 'contains every logo referenced by the manifest' {
        foreach ($asset in @('StoreLogo.png', 'Square44x44Logo.png', 'Square71x71Logo.png', 'Square150x150Logo.png', 'Square310x310Logo.png', 'Wide310x150Logo.png')) {
            Test-Path -LiteralPath (Join-Path $MsixRoot "Assets\$asset") | Should -BeTrue -Because "$asset is referenced by AppxManifest.xml"
        }
    }
}
