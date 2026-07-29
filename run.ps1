# Reads API keys from .env and runs flutter with --dart-define
$envFile = Join-Path $PSScriptRoot ".env"
if (!(Test-Path $envFile)) {
  Write-Error ".env file not found. Copy .env.example to .env and add your keys."
  exit 1
}

$defines = @()
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*([A-Z_]+)=(.*)$') {
    $defines += "--dart-define=$($matches[1])=$($matches[2])"
  }
}

flutter run $defines $args
