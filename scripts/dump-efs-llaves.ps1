#Requires -Version 5.1
<#
.SYNOPSIS
  Dump EFS de /mnt/tld-llaves (lambda tld-alias-cuenta) en Virginia y Oregon.

.DESCRIPTION
  Lo que esta desplegado, no lo del template.
  Lambda (FileSystemConfigs + VPC), access point, file system, mount targets.

.EXAMPLE
  .\dump-efs-llaves.ps1 -Ambiente Sandbox
  .\dump-efs-llaves.ps1 -Ambiente QA
  .\dump-efs-llaves.ps1 -Ambiente Produccion
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Sandbox', 'QA', 'Produccion')]
  [string]$Ambiente,

  [string]$FunctionName = 'tld-alias-cuenta',
  [string[]]$Regions = @('us-east-1', 'us-west-2')
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

switch ($Ambiente) {
  'Sandbox'    { $Environment = 'sandbox' }
  'QA'         { $Environment = 'qa' }
  'Produccion' { $Environment = 'prod' }
}

function Get-RegionLabel {
  param([string]$Region)
  switch ($Region) {
    'us-east-1' { 'virginia' }
    'us-west-2' { 'oregon' }
    default { $Region }
  }
}

function Invoke-AwsJson {
  param(
    [Parameter(Mandatory)][string]$Region,
    [Parameter(Mandatory)][string]$OutFile,
    [Parameter(Mandatory)][string[]]$AwsArgs
  )
  Write-Host "  -> $OutFile" -ForegroundColor DarkGray
  $json = & aws @AwsArgs --region $Region --output json 2>&1
  if ($LASTEXITCODE -ne 0) {
    $json | Set-Content -Encoding utf8 ($OutFile + '.error.txt')
    throw "aws fallo ($OutFile)"
  }
  if ($json -is [System.Array]) { $json = $json -join "`n" }
  $json | Set-Content -Encoding utf8 $OutFile
  return $json
}

Write-Host "$Ambiente  funcion $FunctionName" -ForegroundColor Cyan

foreach ($Region in $Regions) {
  $label = Get-RegionLabel $Region
  $outDir = Join-Path $RepoRoot "raw\$Environment\$label\efs-llaves"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  Push-Location $outDir
  try {
    Write-Host ""
    Write-Host "$label ($Region)" -ForegroundColor Green

    try {
      $cfgRaw = Invoke-AwsJson $Region '01-lambda.json' @(
        'lambda', 'get-function-configuration', '--function-name', $FunctionName
      )
    }
    catch {
      Write-Warning "$label : no se pudo leer la lambda. Sigue la otra region."
      continue
    }

    $cfg = $cfgRaw | ConvertFrom-Json
    $mounts = @($cfg.FileSystemConfigs)
    if (-not $mounts -or $mounts.Count -eq 0) {
      Write-Warning "$label : la lambda no tiene FileSystemConfigs"
      continue
    }

    $n = 0
    foreach ($mount in $mounts) {
      $arn = $mount.Arn
      $apId = ($arn -split '/')[-1]
      $prefix = ('02-ap-{0:D2}-{1}' -f $n, $apId)
      Set-Content -Encoding utf8 ($prefix + '-arn.txt') $arn

      $apRaw = Invoke-AwsJson $Region ($prefix + '.json') @(
        'efs', 'describe-access-points', '--access-point-id', $apId
      )
      $ap = @(($apRaw | ConvertFrom-Json).AccessPoints) | Select-Object -First 1
      if (-not $ap) {
        Write-Warning "$label : access point $apId sin datos"
        $n++
        continue
      }

      $fsId = $ap.FileSystemId
      Invoke-AwsJson $Region ("03-filesystem-{0}.json" -f $fsId) @(
        'efs', 'describe-file-systems', '--file-system-id', $fsId
      ) | Out-Null
      Invoke-AwsJson $Region ("04-mount-targets-{0}.json" -f $fsId) @(
        'efs', 'describe-mount-targets', '--file-system-id', $fsId
      ) | Out-Null
      $n++
    }
  }
  finally {
    Pop-Location
  }
}

Write-Host ""
Write-Host "Listo: raw/$Environment/*/efs-llaves" -ForegroundColor Green
