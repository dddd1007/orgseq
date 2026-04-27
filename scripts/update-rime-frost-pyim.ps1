[CmdletBinding()]
param(
    [string]$RepoUrl = "https://github.com/gaboolic/rime-frost.git",
    [string]$RimeFrostDir = "",
    [string]$OutputPath = "",
    [string]$EntryDictionary = "rime_frost.dict.yaml",
    [string]$PythonCommand = "python",
    [switch]$SkipGitUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Sync-RimeFrostRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoUrl,

        [Parameter(Mandatory = $true)]
        [string]$RimeFrostDir,

        [switch]$SkipGitUpdate
    )

    if ($SkipGitUpdate) {
        if (-not (Test-Path -LiteralPath $RimeFrostDir -PathType Container)) {
            throw "RimeFrostDir does not exist: $RimeFrostDir"
        }
        return
    }

    if (Test-Path -LiteralPath (Join-Path $RimeFrostDir ".git") -PathType Container) {
        git -C $RimeFrostDir pull --ff-only
        if ($LASTEXITCODE -ne 0) {
            throw "git pull failed for $RimeFrostDir."
        }
        return
    }

    if (Test-Path -LiteralPath $RimeFrostDir) {
        throw "RimeFrostDir exists but is not a git checkout: $RimeFrostDir"
    }

    $parent = Split-Path -Parent $RimeFrostDir
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }

    git clone --depth 1 $RepoUrl $RimeFrostDir
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed for $RepoUrl."
    }
}

function Invoke-PythonRimeFrostConverter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonCommand,

        [Parameter(Mandatory = $true)]
        [string]$RimeFrostDir,

        [Parameter(Mandatory = $true)]
        [string]$EntryDictionary,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $converter = Join-Path $PSScriptRoot "convert_rime_frost_pyim.py"
    & $PythonCommand $converter --root $RimeFrostDir --entry $EntryDictionary --output $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Python rime-frost converter failed. Check that Python 3 is available as '$PythonCommand'."
    }
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

if ($RimeFrostDir -eq "") {
    $RimeFrostDir = ".cache\rime-frost"
}
if ($OutputPath -eq "") {
    $OutputPath = "pyim\rime-frost.pyim"
}

$sourceDir = [System.IO.Path]::GetFullPath((Join-Path $root $RimeFrostDir))
$targetPath = [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))

if ([System.IO.Path]::IsPathRooted($RimeFrostDir)) {
    $sourceDir = [System.IO.Path]::GetFullPath($RimeFrostDir)
}

if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $targetPath = [System.IO.Path]::GetFullPath($OutputPath)
}

Sync-RimeFrostRepo -RepoUrl $RepoUrl -RimeFrostDir $sourceDir -SkipGitUpdate:$SkipGitUpdate
Invoke-PythonRimeFrostConverter `
    -PythonCommand $PythonCommand `
    -RimeFrostDir $sourceDir `
    -EntryDictionary $EntryDictionary `
    -OutputPath $targetPath
