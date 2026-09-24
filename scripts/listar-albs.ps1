#Requires -Version 5.1
<#
.SYNOPSIS
  Lista los ALB de Virginia y Oregon. No entra a la consola web.

.EXAMPLE
  .\listar-albs.ps1
#>
[CmdletBinding()]
param(
  [string[]]$Regions = @('us-east-1', 'us-west-2')
)

$ErrorActionPreference = 'Stop'

function Get-RegionLabel {
  param([string]$Region)
  switch ($Region) {
    'us-east-1' { 'virginia' }
    'us-west-2' { 'oregon' }
    default { $Region }
  }
}

foreach ($Region in $Regions) {
  Write-Host ""
  Write-Host "$(Get-RegionLabel $Region) ($Region)" -ForegroundColor Green
  $json = & aws elbv2 describe-load-balancers --region $Region --output json
  if ($LASTEXITCODE -ne 0) { throw "aws fallo en $Region" }
  if ($json -is [System.Array]) { $json = $json -join "`n" }
  $lbs = @(($json | ConvertFrom-Json).LoadBalancers)
  if (-not $lbs -or $lbs.Count -eq 0) {
    Write-Host "  (ninguno)"
    continue
  }
  foreach ($lb in $lbs) {
    Write-Host ("  {0}  {1}" -f $lb.LoadBalancerName, $lb.Scheme)
  }
}
