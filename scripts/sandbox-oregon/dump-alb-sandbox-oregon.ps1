#Requires -Version 5.1
<#
.SYNOPSIS
  Dump ALB sandbox Oregon (us-west-2) via AWS CLI.

.DESCRIPTION
  Default output: <repo>/raw/sandbox-oregon/alb/
  On the RDP machine: run, then git add/commit/push this repo.

.EXAMPLE
  .\dump-alb-sandbox-oregon.ps1
#>
[CmdletBinding()]
param(
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $OutDir) {
  $OutDir = Join-Path $RepoRoot 'raw\sandbox-oregon\alb'
}

$Region = 'us-west-2'
$AlbArn = 'arn:aws:elasticloadbalancing:us-west-2:807262913923:loadbalancer/app/alb-sandbox-oregon/bc8e26a049c22e57'
$TgName = 'vpc-endpoint-apis-oregon'

$env:AWS_DEFAULT_REGION = $Region

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Set-Location $OutDir
Write-Host "Salida: $OutDir" -ForegroundColor Cyan

function Invoke-AwsJson {
  param(
    [Parameter(Mandatory)][string]$OutFile,
    [Parameter(Mandatory)][string[]]$AwsArgs
  )
  Write-Host "-> $OutFile" -ForegroundColor DarkGray
  $json = & aws @AwsArgs --output json 2>&1
  if ($LASTEXITCODE -ne 0) {
    $json | Set-Content -Encoding utf8 ($OutFile + '.error.txt')
    throw "aws failed ($OutFile). See $($OutFile).error.txt"
  }
  if ($json -is [System.Array]) { $json = $json -join "`n" }
  $json | Set-Content -Encoding utf8 $OutFile
}

function Invoke-AwsText {
  param([Parameter(Mandatory)][string[]]$AwsArgs)
  $text = & aws @AwsArgs --output text 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "aws failed: $($AwsArgs -join ' ') -> $text"
  }
  return ($text | Out-String).Trim()
}

Invoke-AwsJson '01-load-balancer.json' @(
  'elbv2', 'describe-load-balancers', '--load-balancer-arns', $AlbArn
)
Invoke-AwsJson '02-load-balancer-attributes.json' @(
  'elbv2', 'describe-load-balancer-attributes', '--load-balancer-arn', $AlbArn
)

Invoke-AwsJson '03-listeners.json' @(
  'elbv2', 'describe-listeners', '--load-balancer-arn', $AlbArn
)

$listenersDoc = Get-Content -Raw '03-listeners.json' | ConvertFrom-Json
$listenerArns = @($listenersDoc.Listeners | ForEach-Object { $_.ListenerArn })

$i = 0
foreach ($listenerArn in $listenerArns) {
  Invoke-AwsJson ("04-rules-listener-{0}.json" -f $i) @(
    'elbv2', 'describe-rules', '--listener-arn', $listenerArn
  )
  $i++
}

Invoke-AwsJson '05-target-groups-del-alb.json' @(
  'elbv2', 'describe-target-groups', '--load-balancer-arn', $AlbArn
)

try {
  Invoke-AwsJson '06-target-group-vpc-endpoint-apis-oregon.json' @(
    'elbv2', 'describe-target-groups', '--names', $TgName
  )
  $tgArn = Invoke-AwsText @(
    'elbv2', 'describe-target-groups',
    '--names', $TgName,
    '--query', 'TargetGroups[0].TargetGroupArn'
  )
  Set-Content -Encoding utf8 '06-target-group-arn.txt' $tgArn

  Invoke-AwsJson '07-target-group-attributes.json' @(
    'elbv2', 'describe-target-group-attributes', '--target-group-arn', $tgArn
  )
  Invoke-AwsJson '08-target-health.json' @(
    'elbv2', 'describe-target-health', '--target-group-arn', $tgArn
  )
}
catch {
  Write-Warning "TG by name '$TgName' failed: $_. Keep file 05 and any .error.txt."
}

$lb = Get-Content -Raw '01-load-balancer.json' | ConvertFrom-Json
$sgIds = @($lb.LoadBalancers[0].SecurityGroups)
if ($sgIds.Count -gt 0) {
  $sgArgs = @('ec2', 'describe-security-groups', '--group-ids') + $sgIds
  Invoke-AwsJson '09-security-groups-alb.json' $sgArgs
}
else {
  Write-Warning 'ALB has no SecurityGroups in 01-load-balancer.json'
}

$vpcId = $lb.LoadBalancers[0].VpcId
Invoke-AwsJson '10-subnets-vpc.json' @(
  'ec2', 'describe-subnets',
  '--filters', "Name=vpc-id,Values=$vpcId",
  '--query', 'Subnets[].{SubnetId:SubnetId,Az:AvailabilityZone,Cidr:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}'
)

Write-Host ''
Write-Host "Done. Commit and push from repo root:" -ForegroundColor Green
Write-Host "  $RepoRoot"
Write-Host "  git add raw/sandbox-oregon/alb"
Write-Host "  git commit -m `"ALB dump sandbox oregon`""
Write-Host "  git push"
Get-ChildItem | Sort-Object Name | Format-Table Name, Length -AutoSize
