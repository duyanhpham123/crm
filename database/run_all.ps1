<#
  Run all MyERP database scripts in order.

  Usage:
    .\run_all.ps1                         # localhost, Windows Authentication
    .\run_all.ps1 -Server ".\SQLEXPRESS"  # another instance
    .\run_all.ps1 -Recreate               # DROP database MyERP then create again (MyERP only)
    .\run_all.ps1 -NoSeed                 # schema only, no initial data
    .\run_all.ps1 -Demo                   # also load demo data (40_demo_data.sql) - never on production
#>
param(
    [string]$Server   = "localhost",
    [string]$Database = "MyERP",
    [switch]$Recreate,
    [switch]$NoSeed,
    [switch]$Demo
)

$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-Sql([string]$file, [string]$db) {
    Write-Host ">> $([IO.Path]::GetFileName($file))" -ForegroundColor Cyan
    & sqlcmd -S $Server -E -d $db -b -I -f 65001 -v DatabaseName=$Database -i $file
    if ($LASTEXITCODE -ne 0) { throw "Failed: $file" }
}

if ($Recreate) {
    Write-Host "Dropping database $Database..." -ForegroundColor Yellow
    & sqlcmd -S $Server -E -d master -b -Q "IF DB_ID(N'$Database') IS NOT NULL BEGIN ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Database]; END"
    if ($LASTEXITCODE -ne 0) { throw "Could not drop database" }
}

Invoke-Sql (Join-Path $dir "00_create_database.sql") "master"

$files = Get-ChildItem $dir -Filter "*.sql" |
         Where-Object { $_.Name -match '^\d{2}_' -and $_.Name -ne '00_create_database.sql' } |
         Sort-Object Name
if ($NoSeed) { $files = $files | Where-Object { $_.Name -notlike '30_*' } }
if ($NoSeed -or -not $Demo) { $files = $files | Where-Object { $_.Name -notlike '40_*' } }

foreach ($f in $files) { Invoke-Sql $f.FullName $Database }

Write-Host "Done. Database $Database on $Server" -ForegroundColor Green
