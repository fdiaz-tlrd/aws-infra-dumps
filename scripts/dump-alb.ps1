#Requires -Version 5.1
<#
.SYNOPSIS
  Dump Application Load Balancers for sandbox in Virginia and Oregon.

.DESCRIPTION
  Regions default: us-east-1 (virginia), us-west-2 (oregon).
  Finds ALBs whose name matches -NameFilter (default *sandbox*).
  For each ALB: LB, attributes, listeners, rules, target groups,
  TG attributes, target health, security groups, VPC subnets.
  Output: raw/sandbox/<virginia|oregon>/alb/<alb-name>/

.EXAMPLE
  .\dump-alb.ps1
  .\dump-alb.ps1 -Regions us-west-2
  .\dump-alb.ps1 -NameFilter '*sandbox*'
#>
[CmdletBinding()]
param(
  [string[]]$Regions = @('us-east-1', 'us-west-2'),
  [string]$NameFilter = '*sandbox*',
  [string]$Environment = 'sandbox'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-RegionLabel {
  param([string]$Region)
  switch ($Region) {
    'us-east-1' { return 'virginia' }
    'us-west-2' { return 'oregon' }
    default { return ($Region -replace '[^a-zA-Z0-9_-]', '_') }
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
    throw "aws failed ($OutFile). See $($OutFile).error.txt"
  }
  if ($json -is [System.Array]) { $json = $json -join "`n" }
  $json | Set-Content -Encoding utf8 $OutFile
}

function Invoke-AwsText {
  param(
    [Parameter(Mandatory)][string]$Region,
    [Parameter(Mandatory)][string[]]$AwsArgs
  )
  $text = & aws @AwsArgs --region $Region --output text 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "aws failed: $($AwsArgs -join ' ') -> $text"
  }
  return ($text | Out-String).Trim()
}

function Export-OneAlb {
  param(
    [string]$Region,
    [string]$OutDir,
    [object]$Lb
  )

  $albArn = $Lb.LoadBalancerArn
  $albName = $Lb.LoadBalancerName
  $albDir = Join-Path $OutDir $albName
  New-Item -ItemType Directory -Force -Path $albDir | Out-Null
  Push-Location $albDir
  try {
    Write-Host " ALB $albName" -ForegroundColor Cyan

    # Single-LB describe (same shape as list item, kept for consistency)
    Invoke-AwsJson $Region '01-load-balancer.json' @(
      'elbv2', 'describe-load-balancers', '--load-balancer-arns', $albArn
    )
    Invoke-AwsJson $Region '02-load-balancer-attributes.json' @(
      'elbv2', 'describe-load-balancer-attributes', '--load-balancer-arn', $albArn
    )
    Invoke-AwsJson $Region '03-listeners.json' @(
      'elbv2', 'describe-listeners', '--load-balancer-arn', $albArn
    )

    $listenersDoc = Get-Content -Raw '03-listeners.json' | ConvertFrom-Json
    $listenerArns = @($listenersDoc.Listeners | ForEach-Object { $_.ListenerArn })
    $li = 0
    foreach ($listenerArn in $listenerArns) {
      Invoke-AwsJson $Region ("04-rules-listener-{0}.json" -f $li) @(
        'elbv2', 'describe-rules', '--listener-arn', $listenerArn
      )
      $li++
    }

    Invoke-AwsJson $Region '05-target-groups-del-alb.json' @(
      'elbv2', 'describe-target-groups', '--load-balancer-arn', $albArn
    )

    $tgDoc = Get-Content -Raw '05-target-groups-del-alb.json' | ConvertFrom-Json
    $tgs = @($tgDoc.TargetGroups)
    if (-not $tgs) { $tgs = @() }

    $ti = 0
    foreach ($tg in $tgs) {
      $tgArn = $tg.TargetGroupArn
      $tgSafe = ($tg.TargetGroupName -replace '[^a-zA-Z0-9._-]', '_')
      $prefix = ('06-tg-{0:D2}-{1}' -f $ti, $tgSafe)
      Set-Content -Encoding utf8 ($prefix + '-arn.txt') $tgArn
      Invoke-AwsJson $Region ($prefix + '-describe.json') @(
        'elbv2', 'describe-target-groups', '--target-group-arns', $tgArn
      )
      Invoke-AwsJson $Region ($prefix + '-attributes.json') @(
        'elbv2', 'describe-target-group-attributes', '--target-group-arn', $tgArn
      )
      Invoke-AwsJson $Region ($prefix + '-health.json') @(
        'elbv2', 'describe-target-health', '--target-group-arn', $tgArn
      )
      $ti++
    }

    $lbFull = Get-Content -Raw '01-load-balancer.json' | ConvertFrom-Json
    $sgIds = @($lbFull.LoadBalancers[0].SecurityGroups)
    if ($sgIds.Count -gt 0) {
      $sgArgs = @('ec2', 'describe-security-groups', '--group-ids') + $sgIds
      Invoke-AwsJson $Region '09-security-groups-alb.json' $sgArgs
    }
    else {
      Write-Warning "ALB $albName has no SecurityGroups"
    }

    $vpcId = $lbFull.LoadBalancers[0].VpcId
    Invoke-AwsJson $Region '10-subnets-vpc.json' @(
      'ec2', 'describe-subnets',
      '--filters', "Name=vpc-id,Values=$vpcId",
      '--query', 'Subnets[].{SubnetId:SubnetId,Az:AvailabilityZone,Cidr:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}'
    )
  }
  finally {
    Pop-Location
  }
}

Write-Host "Repo: $RepoRoot" -ForegroundColor Cyan
Write-Host "Regions: $($Regions -join ', ') | filter: $NameFilter | env: $Environment"

foreach ($Region in $Regions) {
  $label = Get-RegionLabel $Region
  $outBase = Join-Path $RepoRoot "raw\$Environment\$label\alb"
  New-Item -ItemType Directory -Force -Path $outBase | Out-Null
  Write-Host ""
  Write-Host "=== $label ($Region) ===" -ForegroundColor Green

  $listFile = Join-Path $outBase '00-load-balancers-region.json'
  Invoke-AwsJson $Region $listFile @(
    'elbv2', 'describe-load-balancers'
  )

  $all = (Get-Content -Raw $listFile | ConvertFrom-Json).LoadBalancers
  if (-not $all) { $all = @() }
  $matched = @($all | Where-Object { $_.LoadBalancerName -like $NameFilter })

  $summary = [pscustomobject]@{
    Region       = $Region
    Label        = $label
    NameFilter   = $NameFilter
    TotalInRegion = @($all).Count
    MatchedCount  = $matched.Count
    MatchedNames  = @($matched | ForEach-Object { $_.LoadBalancerName })
  }
  ($summary | ConvertTo-Json) | Set-Content -Encoding utf8 (Join-Path $outBase '00-summary.json')

  if ($matched.Count -eq 0) {
    Write-Warning "No ALB matched '$NameFilter' in $Region. See 00-load-balancers-region.json"
    continue
  }

  foreach ($lb in $matched) {
    Export-OneAlb -Region $Region -OutDir $outBase -Lb $lb
  }
}

Write-Host ""
Write-Host "Done. From repo root:" -ForegroundColor Green
Write-Host "  git add raw/$Environment"
Write-Host "  git commit -m `"alb dump $Environment virginia+oregon`""
Write-Host "  git push"
