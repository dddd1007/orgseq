#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$DeployScript = Join-Path $RepoRoot 'deploy.ps1'
$BashDeployScript = Join-Path $RepoRoot 'deploy.sh'

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }
    Assert-True -Condition $threw -Message $Message
}

$source = Get-Content -LiteralPath $DeployScript -Raw
Assert-True -Condition ($source -match '\[CmdletBinding\(SupportsShouldProcess\)\]') `
    -Message 'deploy.ps1 must support -WhatIf through SupportsShouldProcess.'
Assert-True -Condition ($source -match 'function Resolve-SafeDeploymentTarget') `
    -Message 'deploy.ps1 must define Resolve-SafeDeploymentTarget.'
Assert-True -Condition ($source.Contains('$MyInvocation.InvocationName -ne ''.''')) `
    -Message 'deploy.ps1 must be safe to dot-source for focused tests.'

. $DeployScript

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("org-seq-deploy-test-{0}" -f [guid]::NewGuid())
try {
    $null = New-Item -ItemType Directory -Path $testRoot -Force
    $safeTarget = Join-Path $testRoot '.emacs.d'
    $resolved = Resolve-SafeDeploymentTarget -Path $safeTarget
    Assert-True -Condition (
        [System.IO.Path]::GetFullPath($resolved) -eq
        [System.IO.Path]::GetFullPath($safeTarget)
    ) -Message 'A nested deployment target should be accepted and normalized.'

    $rootPath = [System.IO.Path]::GetPathRoot($testRoot)
    Assert-Throws -Action { Resolve-SafeDeploymentTarget -Path $rootPath } `
        -Message 'Filesystem root must be rejected.'
    Assert-Throws -Action { Resolve-SafeDeploymentTarget -Path $HOME } `
        -Message 'The user home directory must be rejected.'
    Assert-Throws -Action { Resolve-SafeDeploymentTarget -Path $RepoRoot } `
        -Message 'The org-seq source directory must be rejected.'
    Assert-Throws -Action { Resolve-SafeDeploymentTarget -Path (Join-Path $RepoRoot '.deploy-target') } `
        -Message 'A target inside the org-seq source tree must be rejected.'
    Assert-Throws -Action { Resolve-SafeDeploymentTarget -Path (Split-Path -Parent $RepoRoot) } `
        -Message 'A target containing the org-seq source tree must be rejected.'

    $whatIfTarget = Join-Path $testRoot 'what-if-target'
    $pwsh = (Get-Process -Id $PID -ErrorAction Stop).Path
    & $pwsh -NoLogo -NoProfile -File $DeployScript `
        -Target $whatIfTarget -SkipChecks -WhatIf 2>&1 | Out-Null
    Assert-True -Condition ($LASTEXITCODE -eq 0) `
        -Message 'deploy.ps1 -WhatIf must exit successfully.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $whatIfTarget)) `
        -Message 'deploy.ps1 -WhatIf must not create the target.'

    Assert-Throws -Action {
        Assert-DeploymentCheckResult -ExitCode 1 -Context 'Byte compilation' -Output @('failure')
    } -Message 'A failed deployment verification must terminate deployment.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

$bashSource = Get-Content -LiteralPath $BashDeployScript -Raw
Assert-True -Condition ($bashSource -match 'resolve_safe_target') `
    -Message 'deploy.sh must validate its target before deletion.'
Assert-True -Condition ($bashSource -match '\$resolved" == "\$SCRIPT_DIR/"\*') `
    -Message 'deploy.sh must reject targets inside the source tree.'
Assert-True -Condition ($bashSource -match '\$SCRIPT_DIR" == "\$resolved/"\*') `
    -Message 'deploy.sh must reject targets containing the source tree.'
Assert-True -Condition ($bashSource -match 'return "\$status"') `
    -Message 'deploy.sh verification must propagate a nonzero compiler status.'

[pscustomobject]@{
    Passed = $true
    Checks = 15
}
