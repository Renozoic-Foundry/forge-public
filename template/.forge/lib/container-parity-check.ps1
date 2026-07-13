# FORGE container/host parity gate (Spec 541) — PowerShell parity.
#
# Usage:
#   container-parity-check.ps1 [-SpecFile <path>] [-HostPackageJson <path>]
#
# Catches host-vs-container divergence at /implement Step 1c:
#   1. Container-name drift — every `docker exec <container>` invocation named in the
#      active spec text must correspond to a container in `docker ps`.
#   2. Package-parity — the host package.json is diffed (line count + dependency list)
#      against the package.json inside the first named container.
#
# Advisory only — never auto-remediates. No-ops cleanly (exit 0) when Docker is absent
# or the daemon is unreachable, so non-container consumers see no friction.
#
# Exit 0 on parity or no-Docker no-op. Exit 1 with a diagnostic on mismatch/drift.

param(
  [string]$SpecFile = "",
  [string]$HostPackageJson = "package.json"
)

$ErrorActionPreference = "Stop"

$ContainerAppDir = $env:FORGE_CONTAINER_APP_DIR
if ([string]::IsNullOrEmpty($ContainerAppDir)) { $ContainerAppDir = "/app" }

# --- No-Docker / no-daemon no-op ---
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
  Write-Output "container-parity-check: docker not found — no-op (non-container consumer)."
  exit 0
}

try {
  docker info *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Output "container-parity-check: docker daemon not reachable — no-op."
    exit 0
  }
} catch {
  Write-Output "container-parity-check: docker daemon not reachable — no-op."
  exit 0
}

$exitCode = 0
$namedContainers = @()

# --- Container-name drift: scan spec text for `docker exec <container>` ---
if ($SpecFile -and (Test-Path $SpecFile)) {
  $runningNames = @(docker ps --format '{{.Names}}' 2>$null)
  $specText = Get-Content -Raw $SpecFile
  $matches = [regex]::Matches($specText, 'docker exec ([A-Za-z0-9_.-]+)')
  $namedContainers = $matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

  foreach ($name in $namedContainers) {
    if ($runningNames -notcontains $name) {
      Write-Output "container-parity-check: container '$name' not found in docker ps"
      $exitCode = 1
    }
  }
}

# --- Package parity: diff host package.json against the first named container's copy ---
$firstContainer = $namedContainers | Select-Object -First 1
if ($firstContainer -and (Test-Path $HostPackageJson)) {
  $containerPkg = $null
  try {
    $containerPkg = docker exec $firstContainer sh -c "cat '$ContainerAppDir/package.json'" 2>$null
  } catch {
    $containerPkg = $null
  }
  if ($LASTEXITCODE -eq 0 -and $containerPkg) {
    $hostLines = (Get-Content $HostPackageJson).Count
    $containerLines = ($containerPkg -split "`n").Count
    $depRegex = '"[A-Za-z0-9@/_.-]+"\s*:\s*"[^"]+"'
    $hostDeps = ([regex]::Matches((Get-Content -Raw $HostPackageJson), $depRegex) | ForEach-Object { $_.Value } | Sort-Object -Unique) -join "`n"
    $containerDeps = ([regex]::Matches(($containerPkg -join "`n"), $depRegex) | ForEach-Object { $_.Value } | Sort-Object -Unique) -join "`n"

    if ($hostLines -ne $containerLines -or $hostDeps -ne $containerDeps) {
      Write-Output "container-parity-check: host/container package.json mismatch (host=$hostLines lines, container=$containerLines lines)."
      Write-Output "Remediation: docker exec $firstContainer sh -c 'cd $ContainerAppDir && npm install'"
      $exitCode = 1
    }
  }
}

if ($exitCode -eq 0) {
  Write-Output "container-parity-check: parity OK."
}

exit $exitCode
