# Spec 315 AC 12b — Cross-platform staging-manifest hash parity (PowerShell side)
# Verifies that the LF-normalize-then-hash protocol in onboarding.md produces
# the same sha256 hex digest as the bash side, when the fixture uses CRLF.
#
# Reference fixture content (LF-normalized): "line one`nline two`nline three`n"
# Expected sha256: bce2aeea9e6fc31f09b164dbaf832b013ee75fbd323262cbee9d42b8b51077b1
#
# This script writes a fixture with CRLF line endings (Windows-native), runs the
# PowerShell hash recipe from onboarding.md, and confirms the hash is identical
# to the LF-fixture hash from the bash side.

$ErrorActionPreference = 'Stop'

$ExpectedHash = "bce2aeea9e6fc31f09b164dbaf832b013ee75fbd323262cbee9d42b8b51077b1"

$WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) "forge-staging-parity-$(Get-Random)"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$Fixture = Join-Path $WorkDir 'fixture-crlf.txt'

try {
    # Write fixture with explicit CRLF byte sequence (0x0D 0x0A)
    # Build bytes manually to avoid encoding-pipeline surprises
    $crlf = [byte[]](0x0D, 0x0A)
    $bytes = [System.Collections.Generic.List[byte]]::new()
    [void]$bytes.AddRange([System.Text.Encoding]::UTF8.GetBytes("line one"))
    [void]$bytes.AddRange($crlf)
    [void]$bytes.AddRange([System.Text.Encoding]::UTF8.GetBytes("line two"))
    [void]$bytes.AddRange($crlf)
    [void]$bytes.AddRange([System.Text.Encoding]::UTF8.GetBytes("line three"))
    [void]$bytes.AddRange($crlf)
    [System.IO.File]::WriteAllBytes($Fixture, $bytes.ToArray())

    # Verify fixture byte size (8 + 2 + 8 + 2 + 10 + 2 = 32 bytes for CRLF)
    $size = (Get-Item $Fixture).Length
    if ($size -ne 32) {
        Write-Error "FAIL: fixture has $size bytes, expected 32 (CRLF-terminated)"
        exit 1
    }

    # Apply the PowerShell hash recipe from onboarding.md § Cross-platform hashing protocol
    $rawBytes = [System.IO.File]::ReadAllBytes($Fixture)
    # Strip BOM if present (none expected on this fixture, but the protocol applies it)
    if ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) {
        $rawBytes = $rawBytes[3..($rawBytes.Length - 1)]
    }
    $text = [System.Text.Encoding]::UTF8.GetString($rawBytes)
    $normalized = $text -replace "`r`n","`n" -replace "`r","`n"
    $normBytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($normBytes)
    } finally {
        $sha.Dispose()
    }
    $ActualHash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })

    if ($ActualHash -eq $ExpectedHash) {
        Write-Host "PASS: PowerShell hash matches reference (cross-platform parity verified)"
        Write-Host "  fixture: 32 bytes, CRLF line endings"
        Write-Host "  hash:    $ActualHash"
        exit 0
    } else {
        Write-Error "FAIL: PowerShell hash mismatch"
        Write-Host "  expected: $ExpectedHash"
        Write-Host "  actual:   $ActualHash"
        exit 1
    }
} finally {
    if (Test-Path $WorkDir) {
        Remove-Item -Recurse -Force $WorkDir
    }
}
