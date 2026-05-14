# test-spec-387-no-prompt-on-unrelated-diff (PS parity) — AC3.
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ForgeDir  = Split-Path -Parent (Split-Path -Parent $ScriptDir)
. (Join-Path $ForgeDir 'lib/safety-config.ps1')

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $yaml = Join-Path $tmp 'registry.yaml'
    @"
patterns:
  - AGENTS.md
  - .forge/safety-config-paths.yaml
"@ | Set-Content -LiteralPath $yaml

    $unrelated = @('docs/specs/123-foo.md','README.md','src/foo.py')
    $matches = Get-SafetyConfigMatches -YamlFile $yaml -DiffPaths $unrelated
    if ($matches.Count -eq 0) {
        Write-Output 'PASS: unrelated diff produces empty match set (no prompt fires)'
        exit 0
    }
    [Console]::Error.WriteLine("FAIL: matched $($matches -join ',')")
    exit 1
} finally { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }
