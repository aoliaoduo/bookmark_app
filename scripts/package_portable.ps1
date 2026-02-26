param(
  [ValidateSet('x64', 'arm64')]
  [string]$Arch,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

if (-not $SkipBuild) {
  & (Join-Path $PSScriptRoot 'build_windows_release.ps1')
}

$runnerRoot = Join-Path $repoRoot 'build/windows'
if (-not (Test-Path $runnerRoot)) {
  throw "Build output not found: $runnerRoot"
}

$candidateArchDirs = Get-ChildItem -Path $runnerRoot -Directory
$releaseDirs = @()
foreach ($archDir in $candidateArchDirs) {
  $releasePath = Join-Path $archDir.FullName 'runner/Release'
  if (Test-Path $releasePath) {
    $releaseDirs += [pscustomobject]@{
      Arch = $archDir.Name
      Path = $releasePath
    }
  }
}

if ($releaseDirs.Count -eq 0) {
  throw "No Release output found under $runnerRoot"
}

$selected = $null
if ($Arch) {
  $selected = $releaseDirs | Where-Object { $_.Arch -eq $Arch } | Select-Object -First 1
  if (-not $selected) {
    throw "Release output for arch '$Arch' not found."
  }
} else {
  $selected = $releaseDirs | Select-Object -First 1
}

$pubspecRaw = Get-Content -Raw -Path (Join-Path $repoRoot 'pubspec.yaml')
$versionMatch = [regex]::Match($pubspecRaw, '(?m)^version:\s*(.+)$')
if (-not $versionMatch.Success) {
  throw 'Failed to read version from pubspec.yaml'
}
$versionFull = $versionMatch.Groups[1].Value.Trim()
$version = $versionFull.Split('+')[0]

$distRoot = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

$stageDir = Join-Path $distRoot "AIOS-$version-$($selected.Arch)-portable"
if (Test-Path $stageDir) {
  Remove-Item -Recurse -Force $stageDir
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
Copy-Item -Path (Join-Path $selected.Path '*') -Destination $stageDir -Recurse -Force

$zipPath = Join-Path $distRoot "AIOS-$version-$($selected.Arch)-portable.zip"
if (Test-Path $zipPath) {
  Remove-Item -Force $zipPath
}
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -Force

Write-Host "Portable package generated: $zipPath"
