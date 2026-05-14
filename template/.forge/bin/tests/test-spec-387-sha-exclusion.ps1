# test-spec-387-sha-exclusion (PowerShell parity) — AC6.
# ## Safety Enforcement section is excluded from Approved-SHA hash input.
$ErrorActionPreference = 'Stop'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $specV1 = Join-Path $tmp 'spec-v1.md'
    @'
# Spec 999 — Test fixture for SHA exclusion

## Scope

In scope: testing.

## Requirements

R1. Do the thing.

## Acceptance Criteria

1. The thing is done.

## Test Plan

Run a fixture.

## Safety Enforcement

Enforcement code path: src/foo.sh::do_thing
Negative-path test: tests/test-foo.sh::test_rejects_unsafe
Validates that the unsafe condition is rejected.

## Implementation Summary

(empty)
'@ | Set-Content -LiteralPath $specV1 -NoNewline

    function Get-ProtectedSections {
        param([string]$File)
        $lines = Get-Content -LiteralPath $File
        $out = New-Object System.Collections.Generic.List[string]
        $inProtected = $false
        foreach ($line in $lines) {
            if ($line -match '^## Scope|^## Requirements|^## Acceptance Criteria|^## Test Plan') {
                $inProtected = $true
                $out.Add($line) | Out-Null
                continue
            }
            if ($line -match '^## ') { $inProtected = $false; continue }
            if ($inProtected) { $out.Add($line) | Out-Null }
        }
        return $out -join "`n"
    }

    function Get-Sha256 {
        param([string]$Text)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
    }

    $shaV1 = Get-Sha256 (Get-ProtectedSections -File $specV1)

    # Edit only the Safety Enforcement section.
    $specV2 = Join-Path $tmp 'spec-v2.md'
    (Get-Content -Raw -LiteralPath $specV1) `
        -replace 'src/foo.sh::do_thing', 'src/bar.sh::do_thing' `
        -replace 'tests/test-foo.sh', 'tests/test-bar.sh' `
        | Set-Content -LiteralPath $specV2 -NoNewline

    $shaV2 = Get-Sha256 (Get-ProtectedSections -File $specV2)

    if ($shaV1 -eq $shaV2) {
        Write-Output 'PASS: Safety Enforcement section edits do not change Approved-SHA over protected sections'
        Write-Output "      sha_v1 = $($shaV1.Substring(0,16))..."
        Write-Output "      sha_v2 = $($shaV2.Substring(0,16))..."
    } else {
        [Console]::Error.WriteLine('FAIL: SHA changed when only Safety Enforcement section edited')
        exit 1
    }

    # Sanity: v1 vs v2 are actually different
    $v1Bytes = [System.IO.File]::ReadAllBytes($specV1)
    $v2Bytes = [System.IO.File]::ReadAllBytes($specV2)
    if ($v1Bytes.Length -eq $v2Bytes.Length -and ($v1Bytes -join '') -eq ($v2Bytes -join '')) {
        [Console]::Error.WriteLine('FAIL: fixture setup error — v1 and v2 are byte-identical')
        exit 1
    }

    # Control: edit a protected section → SHA changes
    $specV3 = Join-Path $tmp 'spec-v3.md'
    (Get-Content -Raw -LiteralPath $specV1) `
        -replace 'R1\. Do the thing\.', 'R1. Do the thing differently.' `
        | Set-Content -LiteralPath $specV3 -NoNewline
    $shaV3 = Get-Sha256 (Get-ProtectedSections -File $specV3)
    if ($shaV1 -eq $shaV3) {
        [Console]::Error.WriteLine('FAIL: control case — protected-section edit did NOT change SHA')
        exit 1
    } else {
        Write-Output "PASS: control — protected-section edit DOES change SHA (sha_v3 = $($shaV3.Substring(0,16))...)"
    }

    Write-Output 'RESULT: SHA exclusion verified'
    exit 0
} finally {
    Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}
