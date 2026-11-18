param(
    [string]$AppUrl,
    [string]$JwtSecret
)

$ErrorActionPreference = "Stop"

$pairs = @()
if ($AppUrl) { $pairs += "APP_URL=$AppUrl" }
if ($JwtSecret) { $pairs += "JWT_SECRET=$JwtSecret" }

if (-not $pairs.Count) {
    throw "Provide -AppUrl and/or -JwtSecret."
}

Push-Location (Join-Path $PSScriptRoot "..")
try {
    & eb setenv ($pairs -join ",")
    if ($LASTEXITCODE -ne 0) {
        throw "eb setenv failed."
    }
    Write-Host "Environment variables updated. The application will restart."
}
finally {
    Pop-Location
}
