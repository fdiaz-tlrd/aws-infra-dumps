#Requires -Version 5.1
<#
.SYNOPSIS
  Baja todos los ALB de Virginia y Oregon (cuenta AWS activa).

.EXAMPLE
  .\dump-alb.ps1 -Environment sandbox
  .\dump-alb.ps1 -Environment qa
  .\dump-alb.ps1 -Environment prod
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
}

function Export-OneAlb {
  param([string]$Region, [string]$OutDir, [object]$Lb)

  $albArn = $Lb.LoadBalancerArn
  $albDir = Join-Path $OutDir $Lb.LoadBalancerName
  New-Item -ItemType Directory -Force -Path $albDir | Out-Null
  Push-Location $albDir
  try {
    Write-Host " ALB $($Lb.LoadBalancerName)" -ForegroundColor Cyan

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
    $li = 0
    $certArns = @()
    foreach ($listener in @($listenersDoc.Listeners)) {
      Invoke-AwsJson $Region ("04-rules-listener-{0}.json" -f $li) @(
        'elbv2', 'describe-rules', '--listener-arn', $listener.ListenerArn
      )
      foreach ($c in @($listener.Certificates)) {
        if ($c.CertificateArn) { $certArns += $c.CertificateArn }
      }
      $li++
    }

    foreach ($certArn in @($certArns | Select-Object -Unique)) {
      $id = ($certArn -split '/')[-1]
      try {
        Invoke-AwsJson $Region ("03c-acm-{0}.json" -f $id) @(
          'acm', 'describe-certificate', '--certificate-arn', $certArn
        )
      }
      catch {
        Write-Warning "ACM ${id}: $_"
      }
    }

    Invoke-AwsJson $Region '05-target-groups.json' @(
      'elbv2', 'describe-target-groups', '--load-balancer-arn', $albArn
    )
    $tgs = @((Get-Content -Raw '05-target-groups.json' | ConvertFrom-Json).TargetGroups)
    if (-not $tgs) { $tgs = @() }
    $ti = 0
    foreach ($tg in $tgs) {
      $safe = ($tg.TargetGroupName -replace '[^a-zA-Z0-9._-]', '_')
      $prefix = ('06-tg-{0:D2}-{1}' -f $ti, $safe)
      Invoke-AwsJson $Region ($prefix + '-describe.json') @(
        'elbv2', 'describe-target-groups', '--target-group-arns', $tg.TargetGroupArn
      )
      Invoke-AwsJson $Region ($prefix + '-health.json') @(
        'elbv2', 'describe-target-health', '--target-group-arn', $tg.TargetGroupArn
      )
      $ti++
    }

    $lbFull = Get-Content -Raw '01-load-balancer.json' | ConvertFrom-Json
    $sgIds = @($lbFull.LoadBalancers[0].SecurityGroups)
    if ($sgIds.Count -gt 0) {
      Invoke-AwsJson $Region '09-security-groups.json' (@('ec2', 'describe-security-groups', '--group-ids') + $sgIds)
    }
  }
  finally {
    Pop-Location
  }
}

Write-Host "Salida: raw/$Environment" -ForegroundColor Cyan

foreach ($Region in $Regions) {
  $label = Get-RegionLabel $Region
  $outBase = Join-Path $RepoRoot "raw\$Environment\$label\alb"
  New-Item -ItemType Directory -Force -Path $outBase | Out-Null
  Write-Host ""
  Write-Host "$label ($Region)" -ForegroundColor Green

  $listFile = Join-Path $outBase '00-load-balancers.json'
  Invoke-AwsJson $Region $listFile @('elbv2', 'describe-load-balancers')

  $all = @((Get-Content -Raw $listFile | ConvertFrom-Json).LoadBalancers)
  if (-not $all) { $all = @() }
  Write-Host "  ALBs: $($all.Count)"
  foreach ($lb in $all) {
    Export-OneAlb -Region $Region -OutDir $outBase -Lb $lb
  }
}

Write-Host ""
Write-Host "Listo: raw/$Environment" -ForegroundColor Green
