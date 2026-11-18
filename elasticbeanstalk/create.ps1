param(
    [string]$EnvironmentName = "sye-lodge-prod",
    [string]$CName = "sye-lodge-prod",
    [string]$Region = "eu-central-1"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command eb -ErrorAction SilentlyContinue)) {
    throw "EB CLI is not installed. Run: pip install awsebcli"
}

Push-Location (Join-Path $PSScriptRoot "..")
try {
    $existing = & eb status $EnvironmentName 2>$null
    if ($LASTEXITCODE -eq 0) {
        throw "Environment '$EnvironmentName' already exists. Use 'eb deploy' to update it."
    }

    $secure = Read-Host "RDS master password (8-16 chars, no / \ @)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $dbPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    if ($dbPassword.Length -lt 8 -or $dbPassword.Length -gt 16 -or $dbPassword -match '[/\\@]') {
        throw "RDS password must be 8-16 characters and must not contain /, \ or @."
    }

    $jwtBytes = New-Object byte[] 48
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($jwtBytes)
    $jwtSecret = [BitConverter]::ToString($jwtBytes).Replace("-", "")

    $appUrl = "http://$CName.elasticbeanstalk.com"
    $envVars = "JWT_SECRET=$jwtSecret,APP_URL=$appUrl"

    Write-Host "Creating $EnvironmentName in $Region with a coupled PostgreSQL database..."
    & eb create $EnvironmentName `
        --platform "Corretto 25 running on 64bit Amazon Linux 2023" `
        --region $Region `
        --instance_type t3.micro `
        --single `
        --cname $CName `
        --database.engine postgres `
        --database.instance db.t3.micro `
        --database.username syelodge `
        --database.password $dbPassword `
        --database.size 5 `
        --envvars $envVars `
        --timeout 30

    if ($LASTEXITCODE -ne 0) {
        throw "eb create failed. Run 'eb events' to see why."
    }

    Write-Host ""
    Write-Host "Site: $appUrl"
    Write-Host "Save the RDS password and JWT secret somewhere private. They are not in this repo."
}
finally {
    Pop-Location
}
