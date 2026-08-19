# Migration wrapper: preview then ask to migrate SQLite -> MySQL
# Usage: run from backend folder: .\migrate_wrapper.ps1

$cfg = Join-Path $PSScriptRoot 'mysql_config.json'
if (-not (Test-Path $cfg)) {
  Write-Host "mysql_config.json not found in $PSScriptRoot" -ForegroundColor Red
  exit 1
}

Write-Host "Previewing migration (will not modify DB) ..."
python migrate_with_config.py --preview

$yn = Read-Host "Run actual migration now? (y/N)"
if ($yn -match '^[Yy]') {
  Write-Host "Running migration..."
  python migrate_with_config.py --migrate
  Write-Host "Migration finished."
} else {
  Write-Host "Migration cancelled."
}
