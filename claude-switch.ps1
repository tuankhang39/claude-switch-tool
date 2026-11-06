# claude-switch: switch between multiple Claude Code accounts using CLAUDE_CONFIG_DIR.
# The "main" account is the default ~\.claude directory (CLAUDE_CONFIG_DIR unset).
# Other accounts live in ~\.claude-accounts\<name>.

$CsRoot = Join-Path $HOME ".claude-accounts"
$CsMain = Join-Path $HOME ".claude"

function Get-CsDir([string]$Name) {
    if (-not $Name -or $Name -eq "main") { return $CsMain }
    return Join-Path $CsRoot $Name
}

function Get-CsEmail([string]$Name) {
    # main keeps .claude.json in $HOME; other accounts keep it inside their config dir
    $json = if ($Name -eq "main") { Join-Path $HOME ".claude.json" } else { Join-Path (Get-CsDir $Name) ".claude.json" }
    if (-not (Test-Path $json)) { return "(not logged in)" }
    try {
        $email = (Get-Content $json -Raw | ConvertFrom-Json).oauthAccount.emailAddress
        if ($email) { return $email } else { return "(not logged in)" }
    } catch { return "(unreadable)" }
}

function Get-CsNames {
    $names = @("main")
    if (Test-Path $CsRoot) {
        $names += Get-ChildItem $CsRoot -Directory | ForEach-Object { $_.Name }
    }
    return $names
}

function Get-CsNameFromDir([string]$Dir) {
    if (-not $Dir) { return "main" }
    $full = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
    foreach ($n in Get-CsNames) {
        if ([IO.Path]::GetFullPath((Get-CsDir $n)).TrimEnd('\') -ieq $full) { return $n }
    }
    return "(other: $Dir)"
}

function Assert-CsExists([string]$Name) {
    if (-not $Name) { throw "Missing account name. See: claude-switch help" }
    if ($Name -ne "main" -and -not (Test-Path (Get-CsDir $Name))) {
        throw "Account '$Name' does not exist. Create it with: claude-switch add $Name"
    }
}

function Sync-CsShared([string]$Name) {
    # Copy shared config (never credentials) from main to account $Name
    $dst = Get-CsDir $Name
    foreach ($f in @("settings.json", "CLAUDE.md", "keybindings.json")) {
        $src = Join-Path $CsMain $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $dst $f) -Force; Write-Host "  + $f" }
    }
    foreach ($d in @("skills", "agents", "commands")) {
        $src = Join-Path $CsMain $d
        if (Test-Path $src) { Copy-Item $src $dst -Recurse -Force; Write-Host "  + $d\" }
    }
    # Per-project memory
    $projSrc = Join-Path $CsMain "projects"
    if (Test-Path $projSrc) {
        Get-ChildItem $projSrc -Directory | ForEach-Object {
            $mem = Join-Path $_.FullName "memory"
            if (Test-Path $mem) {
                $target = Join-Path $dst "projects\$($_.Name)"
                New-Item -ItemType Directory -Force $target | Out-Null
                Copy-Item $mem $target -Recurse -Force
                Write-Host "  + projects\$($_.Name)\memory\"
            }
        }
    }
}

function claude-switch {
    param(
        [Parameter(Position = 0)][string]$Command = "list",
        [Parameter(Position = 1)][string]$Name,
        [Parameter(ValueFromRemainingArguments = $true)]$Rest
    )

    switch ($Command) {
        { $_ -in "list", "ls" } {
            $session = Get-CsNameFromDir $env:CLAUDE_CONFIG_DIR
            $default = Get-CsNameFromDir ([Environment]::GetEnvironmentVariable("CLAUDE_CONFIG_DIR", "User"))
            Write-Host ""
            foreach ($n in Get-CsNames) {
                $marks = @()
                if ($n -eq $session) { $marks += "active" }
                if ($n -eq $default) { $marks += "default" }
                $prefix = if ($n -eq $session) { "*" } else { " " }
                $tag = if ($marks) { "  [" + ($marks -join ", ") + "]" } else { "" }
                Write-Host ("{0} {1,-12} {2}{3}" -f $prefix, $n, (Get-CsEmail $n), $tag)
            }
            Write-Host ""
        }

        "add" {
            if (-not $Name -or $Name -eq "main") { throw "Provide a valid name, e.g.: claude-switch add work" }
            $dir = Get-CsDir $Name
            if (Test-Path $dir) { throw "Account '$Name' already exists." }
            New-Item -ItemType Directory -Force $dir | Out-Null
            Write-Host "Created $dir. Copying shared config from main:"
            Sync-CsShared $Name
            Write-Host "`nStarting Claude Code for '$Name' - run /login to sign in to the new account."
            $env:CLAUDE_CONFIG_DIR = $dir
            claude
        }

        "use" {
            Assert-CsExists $Name
            if ($Name -eq "main") { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
            else { $env:CLAUDE_CONFIG_DIR = Get-CsDir $Name }
            Write-Host "This terminal now uses: $Name ($(Get-CsEmail $Name))"
        }

        "run" {
            Assert-CsExists $Name
            $old = $env:CLAUDE_CONFIG_DIR
            try {
                if ($Name -eq "main") { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
                else { $env:CLAUDE_CONFIG_DIR = Get-CsDir $Name }
                claude @Rest
            } finally {
                if ($old) { $env:CLAUDE_CONFIG_DIR = $old } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
            }
        }

        "default" {
            Assert-CsExists $Name
            $val = if ($Name -eq "main") { $null } else { Get-CsDir $Name }
            [Environment]::SetEnvironmentVariable("CLAUDE_CONFIG_DIR", $val, "User")
            if ($val) { $env:CLAUDE_CONFIG_DIR = $val } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
            Write-Host "Default account: $Name ($(Get-CsEmail $Name))"
            Write-Host "VS Code: close ALL VS Code windows and reopen for the extension to pick up the new account."
        }

        "sync" {
            Assert-CsExists $Name
            if ($Name -eq "main") { throw "main is the source; it cannot be synced into itself." }
            Write-Host "Copying settings/skills/memory from main -> $Name :"
            Sync-CsShared $Name
        }

        { $_ -in "remove", "rm" } {
            Assert-CsExists $Name
            if ($Name -eq "main") { throw "The main account cannot be removed." }
            $dir = Get-CsDir $Name
            $ok = Read-Host "Delete '$Name' ($dir), including its login and history? (y/N)"
            if ($ok -ne "y") { Write-Host "Cancelled."; return }
            if ((Get-CsNameFromDir ([Environment]::GetEnvironmentVariable("CLAUDE_CONFIG_DIR", "User"))) -eq $Name) {
                [Environment]::SetEnvironmentVariable("CLAUDE_CONFIG_DIR", $null, "User")
                Write-Host "Default reset to main."
            }
            if ($env:CLAUDE_CONFIG_DIR -and (Get-CsNameFromDir $env:CLAUDE_CONFIG_DIR) -eq $Name) {
                Remove-Item Env:CLAUDE_CONFIG_DIR
            }
            Remove-Item $dir -Recurse -Force
            Write-Host "Removed '$Name'."
        }

        default {
            Write-Host @"

claude-switch - manage multiple Claude Code accounts

  claude-switch                  List accounts (* = current terminal)
  claude-switch add <name>       Create an account, copy config from main, start claude to /login
  claude-switch use <name>       Switch the current terminal to <name>
  claude-switch run <name> [...] Run claude as <name> without switching the terminal
  claude-switch default <name>   Set the default account (also VS Code; reopen VS Code)
  claude-switch sync <name>      Re-copy settings/skills/memory from main to <name>
  claude-switch remove <name>    Delete an account

  Alias: cs = claude-switch.  "main" = the original account (~\.claude).

"@
        }
    }
}

Set-Alias cs claude-switch

Register-ArgumentCompleter -CommandName claude-switch, cs -ParameterName Command -ScriptBlock {
    param($cmd, $param, $word)
    "list", "add", "use", "run", "default", "sync", "remove", "help" | Where-Object { $_ -like "$word*" }
}
Register-ArgumentCompleter -CommandName claude-switch, cs -ParameterName Name -ScriptBlock {
    param($cmd, $param, $word)
    Get-CsNames | Where-Object { $_ -like "$word*" }
}
