# Add claude-switch to your PowerShell profile (only once).
$script = Join-Path $PSScriptRoot "claude-switch.ps1"
$line = ". `"$script`""

if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Force $PROFILE | Out-Null
}

if (Select-String -Path $PROFILE -SimpleMatch "claude-switch.ps1" -Quiet) {
    Write-Host "Profile already loads claude-switch, skipping: $PROFILE"
} else {
    Add-Content -Path $PROFILE -Encoding utf8 -Value "`n# Claude Code account switcher`n$line"
    Write-Host "Added to $PROFILE"
}

Write-Host "Restart your terminal (or run: . `$PROFILE), then type: cs help"
