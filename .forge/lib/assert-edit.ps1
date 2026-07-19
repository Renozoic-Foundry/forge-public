# assert-edit.ps1 — verify-after-scripted-edit helpers (Spec 483, PowerShell parity).
# Dot-source for the functions; no main execution. Output (ASSERT-EDIT FAIL lines)
# and exit/return semantics match assert-edit.sh after path/encoding normalization.
#
# Closes the silent-no-op-edit failure mode (see assert-edit.sh header):
# a scripted edit that matched NOTHING but reported success.
#
# Convention (capture-before, assert-after):
#     $before = Get-AssertEditSha $file        # capture baseline
#     # ... the scripted edit (e.g. (Get-Content $file) -replace 'old','new' | Set-Content $file) ...
#     Assert-Changed  -File $file -BeforeSha $before   # FAIL if no-op
#     Assert-Contains -File $file -Expected 'new'      # FAIL if string absent
#
# Public functions:
#   Get-AssertEditSha <file>            -> string hash (sha256, sentinel if absent)
#   Assert-Changed  -File -BeforeSha    -> 0 if changed; writes FAIL + returns non-zero if unchanged
#   Assert-Contains -File -Expected     -> 0 if present; writes FAIL + returns non-zero if absent
#
# Each Assert-* returns an integer exit-style code (0 = pass, non-zero = fail) AND
# writes the FAIL line to the error stream. Advisory by default — the caller
# decides whether a non-zero return halts the surrounding flow.
#
# See docs/process-kit/scripted-edit-conventions.md.
# forge:path-literal-ok (comment)

$ErrorActionPreference = 'Continue'

function Write-AssertEditFail {
    param([string]$Message)
    [Console]::Error.WriteLine("ASSERT-EDIT FAIL: $Message")
}

# Print a content hash of a file. Capture BEFORE a scripted edit.
function Get-AssertEditSha {
    param([Parameter(Mandatory = $true)][string]$File)
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        # Missing file hashes to a sentinel so a create-then-assert still works.
        return '__assert_edit_absent__'
    }
    return (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Assert-Changed -File <path> -BeforeSha <sha>
# Returns 0 if the file's current hash differs from the baseline; else writes a
# FAIL line and returns non-zero. Catches the EA-425 silent-no-op class.
function Assert-Changed {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string]$BeforeSha = ''
    )
    if ([string]::IsNullOrEmpty($BeforeSha)) {
        Write-AssertEditFail "$File — no baseline sha passed to Assert-Changed (capture with Get-AssertEditSha BEFORE the edit)"
        return 2
    }
    $after = Get-AssertEditSha -File $File
    if ($after -eq $BeforeSha) {
        Write-AssertEditFail "$File — unchanged (scripted edit was a silent no-op; the pattern matched nothing)"
        return 1
    }
    return 0
}

# Assert-Contains -File <path> -Expected <literal-string>
# Returns 0 if the expected literal string is present post-edit; else writes a
# FAIL line and returns non-zero. Catches the SIG-460-B verbatim-string class.
function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string]$Expected = ''
    )
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        Write-AssertEditFail "$File — file does not exist (expected to contain: $Expected)"
        return 1
    }
    if ([string]::IsNullOrEmpty($Expected)) {
        Write-AssertEditFail "$File — no expected string passed to Assert-Contains"
        return 2
    }
    # Literal (non-regex) substring match over the whole file content.
    $content = Get-Content -LiteralPath $File -Raw
    if ($null -ne $content -and $content.Contains($Expected)) {
        return 0
    }
    Write-AssertEditFail "$File — missing expected string after edit: $Expected"
    return 1
}
