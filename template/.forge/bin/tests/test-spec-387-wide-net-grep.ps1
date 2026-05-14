# test-spec-387-wide-net-grep (PS parity) — AC12.
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ForgeDir  = Split-Path -Parent (Split-Path -Parent $ScriptDir)
. (Join-Path $ForgeDir 'lib/safety-config.ps1')

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Push-Location $tmp
    try {
        New-Item -ItemType Directory -Path '.forge' | Out-Null
        New-Item -ItemType Directory -Path 'docs/specs' -Force | Out-Null
        New-Item -ItemType Directory -Path 'scripts' | Out-Null

        @"
patterns:
  - AGENTS.md
  - .forge/onboarding.yaml
"@ | Set-Content -LiteralPath '.forge/safety-config-paths.yaml'

        @"
multi_agent:
  require_confirmation_at: critical
"@ | Set-Content -LiteralPath 'AGENTS.md'

        @"
require_human_approval=true
echo done
"@ | Set-Content -LiteralPath 'scripts/lonely.sh'

        $regex = '(safe|safety|enforce|require|validate|guard|prevent|reject)_[a-zA-Z_]+'
        $hits = Get-ChildItem -Recurse -Include '*.sh','*.md','*.yaml' -File `
                  | ForEach-Object {
                        $f = $_.FullName.Substring($PWD.Path.Length + 1) -replace '\\','/'
                        Get-Content -LiteralPath $_.FullName | Select-String -Pattern $regex `
                          | ForEach-Object { "${f}:$($_.LineNumber):$($_.Line)" }
                    }

        $patterns = Get-SafetyConfigPatterns -YamlFile '.forge/safety-config-paths.yaml'
        $regexes = foreach ($p in $patterns) {
            $rx = [regex]::Escape($p)
            $rx = $rx -replace '\\\*\\\*', '.*' -replace '\\\*', '[^/]*' -replace '\\\?', '.'
            "^${rx}$"
        }

        $unflaggedRegistered = 0
        $flaggedUnregistered = 0
        foreach ($h in $hits) {
            $file = ($h -split ':',3)[0]
            $isReg = $false
            foreach ($rx in $regexes) {
                if ($file -match $rx) { $isReg = $true; break }
            }
            if ($isReg) { $unflaggedRegistered++ }
            else { $flaggedUnregistered++ }
        }

        if ($unflaggedRegistered -lt 1) {
            [Console]::Error.WriteLine('FAIL: registered file token should be detected'); exit 1
        }
        if ($flaggedUnregistered -lt 1) {
            [Console]::Error.WriteLine('FAIL: non-registered file token should be flagged'); exit 1
        }
        Write-Output "PASS: wide-net flagged $flaggedUnregistered hit(s) in non-registered file(s); ignored $unflaggedRegistered hit(s) in registered file(s)"
        exit 0
    } finally { Pop-Location }
} finally { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }
