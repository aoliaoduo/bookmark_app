param(
  [switch]$NoPubGet
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

if (-not $NoPubGet) {
  flutter pub get
}

dart run msix:create

$msixFiles = Get-ChildItem -Path (Join-Path $repoRoot 'build/windows') -Recurse -Filter *.msix -ErrorAction SilentlyContinue
if ($msixFiles.Count -eq 0) {
  throw 'MSIX package was not found under build/windows.'
}

Write-Host 'MSIX packages:'
$msixFiles | ForEach-Object { Write-Host $_.FullName }
