param(
  [switch]$NoPubGet
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

if (-not $NoPubGet) {
  flutter pub get
}

flutter build windows --release

Write-Host "Windows release build completed."
