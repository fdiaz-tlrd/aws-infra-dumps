#Requires -Version 5.1
<#
.SYNOPSIS
  List API Gateway custom domain names and their mappings.

.DESCRIPTION
  REST (apigateway) + HTTP/WebSocket (apigatewayv2).
  Default output: <repo>/raw/sandbox-oregon/dominios/
  Optional cross-check vs ALB host-header rules.

.EXAMPLE
  .\revisar-dominios-personalizados.ps1

.EXAMPLE
  .\revisar-dominios-personalizados.ps1 -AlbRulesJson ..\..\raw\sandbox-oregon\alb\04-rules-listener-0.json
#>
[CmdletBinding()]
param(
  [string]$Region = 'us-west-2',
  [string]$OutDir = '',
  [string]$AlbRulesJson = ''
)

$ErrorActionPreference = 'Stop'
$env:AWS_DEFAULT_REGION = $Region

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $OutDir) {
  $OutDir = Join-Path $RepoRoot 'raw\sandbox-oregon\dominios'
}
if (-not $AlbRulesJson) {
  $defaultRules = Join-Path $RepoRoot 'raw\sandbox-oregon\alb\04-rules-listener-0.json'
  if (Test-Path -LiteralPath $defaultRules) { $AlbRulesJson = $defaultRules }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Set-Location $OutDir
Write-Host "Region: $Region" -ForegroundColor Cyan
Write-Host "OutDir: $OutDir" -ForegroundColor Cyan

function Invoke-AwsJson {
  param(
    [Parameter(Mandatory)][string]$OutFile,
    [Parameter(Mandatory)][string[]]$AwsArgs
  )
  Write-Host "-> $OutFile" -ForegroundColor DarkGray
  $json = & aws @AwsArgs --region $Region --output json 2>&1
  if ($LASTEXITCODE -ne 0) {
    $json | Set-Content -Encoding utf8 ($OutFile + '.error.txt')
    throw "aws failed ($OutFile). See $($OutFile).error.txt"
  }
  if ($json -is [System.Array]) { $json = $json -join "`n" }
  $json | Set-Content -Encoding utf8 $OutFile
  return $json
}

function Get-SafeFileName {
  param([string]$Name)
  ($Name -replace '[^a-zA-Z0-9._-]', '_')
}

$restDomainsRaw = Invoke-AwsJson '01-apigateway-domain-names.json' @(
  'apigateway', 'get-domain-names'
)
$restDomains = $restDomainsRaw | ConvertFrom-Json
$restItems = @($restDomains.items)
if (-not $restItems) { $restItems = @() }

$i = 0
foreach ($d in $restItems) {
  $name = $d.domainName
  $safe = Get-SafeFileName $name
  $file = ('02-rest-mappings-{0:D2}-{1}.json' -f $i, $safe)
  try {
    Invoke-AwsJson $file @(
      'apigateway', 'get-base-path-mappings',
      '--domain-name', $name
    ) | Out-Null
  }
  catch {
    Write-Warning "REST mappings failed for ${name}: $_"
  }
  $i++
}

try {
  $v2DomainsRaw = Invoke-AwsJson '03-apigatewayv2-domain-names.json' @(
    'apigatewayv2', 'get-domain-names'
  )
  $v2Domains = $v2DomainsRaw | ConvertFrom-Json
  $v2Items = @($v2Domains.Items)
  if (-not $v2Items) { $v2Items = @() }
}
catch {
  Write-Warning "apigatewayv2 get-domain-names failed: $_"
  $v2Items = @()
}

$j = 0
foreach ($d in $v2Items) {
  $name = $d.DomainName
  if (-not $name) { $name = $d.domainName }
  $safe = Get-SafeFileName $name
  $file = ('04-v2-mappings-{0:D2}-{1}.json' -f $j, $safe)
  try {
    Invoke-AwsJson $file @(
      'apigatewayv2', 'get-api-mappings',
      '--domain-name', $name
    ) | Out-Null
  }
  catch {
    Write-Warning "v2 mappings failed for ${name}: $_"
  }
  $j++
}

$rows = New-Object System.Collections.Generic.List[object]

foreach ($d in $restItems) {
  $name = $d.domainName
  $safe = Get-SafeFileName $name
  $mapFile = Get-ChildItem -Filter ("02-rest-mappings-*-{0}.json" -f $safe) -ErrorAction SilentlyContinue |
    Select-Object -First 1
  $mappings = @()
  $sinMapping = $true
  if ($mapFile) {
    $mapDoc = Get-Content -Raw $mapFile.FullName | ConvertFrom-Json
    $mappings = @($mapDoc.items)
    if (-not $mappings) { $mappings = @() }
    $sinMapping = ($mappings.Count -eq 0)
  }
  $mapParts = foreach ($m in $mappings) {
    $bp = if ($m.basePath) { $m.basePath } else { '(none)' }
    '{0} -> {1}/{2}' -f $bp, $m.restApiId, $m.stage
  }
  $mapSummary = @($mapParts) -join '; '
  $rows.Add([pscustomobject]@{
      ApiKind       = 'REST'
      DomainName    = $name
      DomainStatus  = $d.domainNameStatus
      EndpointType  = (@($d.endpointConfiguration.types) -join ',')
      MappingCount  = $mappings.Count
      SinMapping    = $sinMapping
      Mappings      = $mapSummary
      RegionalDomainName = $d.regionalDomainName
    })
}

foreach ($d in $v2Items) {
  $name = $d.DomainName
  if (-not $name) { $name = $d.domainName }
  $safe = Get-SafeFileName $name
  $mapFile = Get-ChildItem -Filter ("04-v2-mappings-*-{0}.json" -f $safe) -ErrorAction SilentlyContinue |
    Select-Object -First 1
  $mappings = @()
  $sinMapping = $true
  if ($mapFile) {
    $mapDoc = Get-Content -Raw $mapFile.FullName | ConvertFrom-Json
    $mappings = @($mapDoc.Items)
    if (-not $mappings) { $mappings = @($mapDoc.items) }
    if (-not $mappings) { $mappings = @() }
    $sinMapping = ($mappings.Count -eq 0)
  }
  $mapParts = foreach ($m in $mappings) {
    $bp = if ($m.ApiMappingKey) { $m.ApiMappingKey } elseif ($m.apiMappingKey) { $m.apiMappingKey } else { '(none)' }
    $api = if ($m.ApiId) { $m.ApiId } else { $m.apiId }
    $stage = if ($m.Stage) { $m.Stage } else { $m.stage }
    '{0} -> {1}/{2}' -f $bp, $api, $stage
  }
  $mapSummary = @($mapParts) -join '; '
  $regional = ''
  if ($d.DomainNameConfigurations -and $d.DomainNameConfigurations.Count -gt 0) {
    $regional = $d.DomainNameConfigurations[0].ApiGatewayDomainName
  }
  $rows.Add([pscustomobject]@{
      ApiKind       = 'HTTP/v2'
      DomainName    = $name
      DomainStatus  = $d.DomainNameStatus
      EndpointType  = ''
      MappingCount  = $mappings.Count
      SinMapping    = $sinMapping
      Mappings      = $mapSummary
      RegionalDomainName = $regional
    })
}

($rows | ConvertTo-Json -Depth 6) | Set-Content -Encoding utf8 (Join-Path $OutDir '05-resumen-dominios.json')
$rows | Export-Csv -Path (Join-Path $OutDir '05-resumen-dominios.csv') -NoTypeInformation -Encoding UTF8

$albHosts = @()
if ($AlbRulesJson -and (Test-Path -LiteralPath $AlbRulesJson)) {
  Write-Host "ALB rules cross-check: $AlbRulesJson" -ForegroundColor Cyan
  $rulesDoc = Get-Content -Raw -LiteralPath $AlbRulesJson | ConvertFrom-Json
  foreach ($rule in @($rulesDoc.Rules)) {
    foreach ($cond in @($rule.Conditions)) {
      if ($cond.Field -eq 'host-header') {
        $vals = @($cond.Values)
        if ($cond.HostHeaderConfig -and $cond.HostHeaderConfig.Values) {
          $vals = @($cond.HostHeaderConfig.Values)
        }
        foreach ($h in $vals) { $albHosts += $h }
      }
    }
  }
  $albHosts = $albHosts | Select-Object -Unique | Sort-Object
  $albHosts | Set-Content -Encoding utf8 (Join-Path $OutDir '06-alb-hosts.txt')

  $domainSet = @{}
  foreach ($r in $rows) { $domainSet[$r.DomainName] = $r }

  $cruce = foreach ($h in $albHosts) {
    if (-not $domainSet.ContainsKey($h)) {
      [pscustomobject]@{
        AlbHost = $h
        EnApigw = $false
        SinMapping = $true
        Mappings = ''
        Nota = 'Host on ALB; domain not in get-domain-names for this region'
      }
    }
    else {
      $r = $domainSet[$h]
      [pscustomobject]@{
        AlbHost = $h
        EnApigw = $true
        SinMapping = [bool]$r.SinMapping
        Mappings = $r.Mappings
        Nota = $(if ($r.SinMapping) { 'Domain exists WITHOUT mapping' } else { 'OK' })
      }
    }
  }

  ($cruce | ConvertTo-Json -Depth 5) | Set-Content -Encoding utf8 (Join-Path $OutDir '07-cruce-alb-vs-dominios.json')
  $cruce | Export-Csv -Path (Join-Path $OutDir '07-cruce-alb-vs-dominios.csv') -NoTypeInformation -Encoding UTF8

  Write-Host ''
  Write-Host 'ALB hosts missing mapping or domain:' -ForegroundColor Yellow
  $cruce | Where-Object { $_.SinMapping -or -not $_.EnApigw } | Format-Table -AutoSize
}
elseif ($AlbRulesJson) {
  Write-Warning "AlbRulesJson not found: $AlbRulesJson"
}

Write-Host ''
Write-Host 'APIGW domains WITHOUT mapping:' -ForegroundColor Yellow
$rows | Where-Object { $_.SinMapping } | Format-Table DomainName, ApiKind, MappingCount -AutoSize

Write-Host ''
Write-Host "Done. Commit and push from repo root:" -ForegroundColor Green
Write-Host "  $RepoRoot"
Write-Host "  git add raw/sandbox-oregon/dominios"
Write-Host "  git commit -m `"domains dump sandbox oregon`""
Write-Host "  git push"
Write-Host ''
Write-Host 'Open 05-resumen-dominios.csv (and 07-cruce-*.csv if cross-check ran).'
Get-ChildItem | Sort-Object Name | Format-Table Name, Length -AutoSize
