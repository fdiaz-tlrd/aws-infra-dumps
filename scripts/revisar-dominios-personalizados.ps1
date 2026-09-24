#Requires -Version 5.1
<#
.SYNOPSIS
  Baja custom domains de API Gateway (Virginia y Oregon) y sus mappings.

.EXAMPLE
  .\revisar-dominios-personalizados.ps1 -Environment sandbox
#>
[CmdletBinding()]
param(
  [ValidateSet('sandbox', 'qa', 'prod')]
  [string]$Environment = 'sandbox',
  [string[]]$Regions = @('us-east-1', 'us-west-2')
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-RegionLabel {
  param([string]$Region)
  switch ($Region) {
    'us-east-1' { 'virginia' }
    'us-west-2' { 'oregon' }
    default { $Region }
  }
}

function Get-SafeFileName {
  param([string]$Name)
  ($Name -replace '[^a-zA-Z0-9._-]', '_')
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

function Export-Region {
  param([string]$Region, [string]$OutDir)

  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  Push-Location $OutDir
  try {
    $restRaw = Invoke-AwsJson $Region '01-domain-names.json' @('apigateway', 'get-domain-names')
    $restItems = @(($restRaw | ConvertFrom-Json).items)
    if (-not $restItems) { $restItems = @() }

    $i = 0
    foreach ($d in $restItems) {
      $file = ('02-mappings-{0:D2}-{1}.json' -f $i, (Get-SafeFileName $d.domainName))
      try {
        Invoke-AwsJson $Region $file @(
          'apigateway', 'get-base-path-mappings', '--domain-name', $d.domainName
        ) | Out-Null
      }
      catch {
        Write-Warning "$($d.domainName): $_"
      }
      $i++
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($d in $restItems) {
      $safe = Get-SafeFileName $d.domainName
      $mapFile = Get-ChildItem -Filter ("02-mappings-*-{0}.json" -f $safe) | Select-Object -First 1
      $maps = @()
      if ($mapFile) {
        $maps = @((Get-Content -Raw $mapFile.FullName | ConvertFrom-Json).items)
        if (-not $maps) { $maps = @() }
      }
      $txt = @(foreach ($m in $maps) {
          $bp = if ($m.basePath) { $m.basePath } else { '(none)' }
          '{0} -> {1}/{2}' -f $bp, $m.restApiId, $m.stage
        }) -join '; '
      $rows.Add([pscustomobject]@{
          DomainName   = $d.domainName
          MappingCount = $maps.Count
          SinMapping   = ($maps.Count -eq 0)
          Mappings     = $txt
        })
    }

    $rows | Export-Csv -Path '05-resumen.csv' -NoTypeInformation -Encoding UTF8

    $ruleFiles = @(Get-Item (Join-Path $RepoRoot "raw\$Environment\$(Get-RegionLabel $Region)\alb\*\04-rules-listener-*.json") -ErrorAction SilentlyContinue)
    if ($ruleFiles.Count -gt 0) {
      $hosts = @()
      foreach ($rf in $ruleFiles) {
        $doc = Get-Content -Raw $rf.FullName | ConvertFrom-Json
        foreach ($rule in @($doc.Rules)) {
          foreach ($cond in @($rule.Conditions)) {
            if ($cond.Field -eq 'host-header') {
              $vals = @($cond.HostHeaderConfig.Values)
              if (-not $vals -or -not $vals[0]) { $vals = @($cond.Values) }
              foreach ($h in $vals) { if ($h) { $hosts += $h } }
            }
          }
        }
      }
      $hosts = @($hosts | Select-Object -Unique | Sort-Object)
      $byName = @{}
      foreach ($r in $rows) { $byName[$r.DomainName] = $r }
      $cruce = foreach ($h in $hosts) {
        if ($byName.ContainsKey($h)) {
          [pscustomobject]@{ Host = $h; EnApigw = $true; SinMapping = [bool]$byName[$h].SinMapping; Mappings = $byName[$h].Mappings }
        }
        else {
          [pscustomobject]@{ Host = $h; EnApigw = $false; SinMapping = $true; Mappings = '' }
        }
      }
      $cruce | Export-Csv -Path '07-cruce-alb.csv' -NoTypeInformation -Encoding UTF8
    }

    $sin = @($rows | Where-Object { $_.SinMapping })
    Write-Host "  dominios: $($rows.Count)  sin mapping: $($sin.Count)"
  }
  finally {
    Pop-Location
  }
}

Write-Host "Salida: raw/$Environment" -ForegroundColor Cyan
foreach ($Region in $Regions) {
  Write-Host ""
  Write-Host "$(Get-RegionLabel $Region) ($Region)" -ForegroundColor Green
  Export-Region $Region (Join-Path $RepoRoot "raw\$Environment\$(Get-RegionLabel $Region)\dominios")
}
Write-Host ""
Write-Host "Listo: raw/$Environment" -ForegroundColor Green
