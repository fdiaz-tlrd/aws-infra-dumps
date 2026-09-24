#Requires -Version 5.1
<#
.SYNOPSIS
  ALB + dominios de un ambiente (Virginia y Oregon).

.DESCRIPTION
  Usa la cuenta AWS que tenga activa la consola/CLI.
  Baja todos los ALB de esa cuenta. No hay que buscar nombres.

.EXAMPLE
  .\dump-por-ambiente.ps1 -Ambiente Sandbox
  .\dump-por-ambiente.ps1 -Ambiente QA
  .\dump-por-ambiente.ps1 -Ambiente Produccion
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Sandbox', 'QA', 'Produccion')]
  [string]$Ambiente
)

$ErrorActionPreference = 'Stop'

switch ($Ambiente) {
  'Sandbox'    { $Environment = 'sandbox' }
  'QA'         { $Environment = 'qa' }
  'Produccion' { $Environment = 'prod' }
}

$dir = $PSScriptRoot
Write-Host $Ambiente -ForegroundColor Cyan

& (Join-Path $dir 'dump-alb.ps1') -Environment $Environment
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "dump-alb fallo" }

& (Join-Path $dir 'revisar-dominios-personalizados.ps1') -Environment $Environment
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "dominios fallo" }

Write-Host ""
Write-Host "Listo: raw/$Environment" -ForegroundColor Green
