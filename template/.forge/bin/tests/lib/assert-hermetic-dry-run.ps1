# assert-hermetic-dry-run.ps1 — Spec 404
#
# Asserts that running a command does not mutate the contents of a staging
# directory. PowerShell parity of assert-hermetic-dry-run.sh.
#
# Calling convention:
#   . .forge/bin/tests/lib/assert-hermetic-dry-run.ps1
#   Assert-HermeticDryRun -StagingDir <path> -Command { <scriptblock> }
#
# Returns: $true if hermetic, $false if the command mutated the dir.
#
# Byte-identity definition: SHA-256 over a sorted manifest of
#   "<sha256-of-file>  <relative-path>"
# for every file under the staging dir. Excludes mtime, ownership, empty dirs.

function Get-HermeticManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $Dir
    )
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        throw "Not a directory: $Dir"
    }
    $resolved = (Resolve-Path -LiteralPath $Dir).Path
    $files = Get-ChildItem -LiteralPath $resolved -Recurse -File -Force -ErrorAction SilentlyContinue
    $lines = foreach ($f in $files) {
        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
        $rel = $f.FullName.Substring($resolved.Length).TrimStart('\', '/').Replace('\', '/')
        "$hash  $rel"
    }
    $sorted = $lines | Sort-Object -CaseSensitive
    $joined = ($sorted -join "`n")
    if ($null -eq $joined) { $joined = '' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
}

function Assert-HermeticDryRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $StagingDir,
        [Parameter(Mandatory = $true)] [scriptblock] $Command
    )
    $before = Get-HermeticManifest -Dir $StagingDir
    & $Command | Out-Null
    $rc = $LASTEXITCODE
    $after = Get-HermeticManifest -Dir $StagingDir

    if ($before -ne $after) {
        # Use the warning stream so callers with $ErrorActionPreference='Stop'
        # are not terminated — non-hermetic detection is a return value, not an error.
        Write-Warning "NON-HERMETIC: staging dir changed during command run"
        Write-Warning "  dir:    $StagingDir"
        Write-Warning "  before: $before"
        Write-Warning "  after:  $after"
        Write-Warning "  cmd-rc: $rc"
        return $false
    }
    return $true
}
