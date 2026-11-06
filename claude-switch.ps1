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

function Get-CsClaude {
    # Prefer the claude CLI on PATH; fall back to the binary bundled with the VS Code extension
    $cmd = Get-Command claude -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($ext in @("$HOME\.vscode\extensions", "$HOME\.vscode-insiders\extensions", "$HOME\.cursor\extensions")) {
        $exe = Get-ChildItem $ext -Directory -Filter "anthropic.claude-code-*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { Join-Path $_.FullName "resources\native-binary\claude.exe" } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($exe) { return $exe }
    }
    throw "Claude Code not found. Install the CLI (https://docs.anthropic.com/en/docs/claude-code) or the VS Code extension."
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
    # Per-project memory (skipped when projects\ is a junction to main's: already shared)
    $projSrc = Join-Path $CsMain "projects"
    $projDst = Join-Path $dst "projects"
    if ((Test-Path $projDst) -and (Get-Item $projDst).LinkType) {
        Write-Host "  = projects\ shared with main (history + memory)"
    } elseif (Test-Path $projSrc) {
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

$CsEditors = @{
    cursor = Join-Path $env:APPDATA "Cursor\User\settings.json"
    code   = Join-Path $env:APPDATA "Code\User\settings.json"
}
$CsEnvKeyPattern = '"claudeCode\.environmentVariables"\s*:\s*\[[^\]]*\]\s*,?'

function Get-CsEditorDir([string]$Editor) {
    # CLAUDE_CONFIG_DIR the editor's Claude Code extension launches with ($null = main)
    $file = $CsEditors[$Editor]
    if (-not (Test-Path $file)) { return $null }
    $m = [regex]::Match((Get-Content $file -Raw), $CsEnvKeyPattern)
    if (-not $m.Success) { return $null }
    $v = [regex]::Match($m.Value, '"name"\s*:\s*"CLAUDE_CONFIG_DIR"\s*,\s*"value"\s*:\s*"([^"]*)"')
    if ($v.Success) { return $v.Groups[1].Value.Replace('\\', '\') }
    return $null
}

function Set-CsEditor([string]$Editor, [string]$Name) {
    # Point the editor's Claude Code extension at an account via claudeCode.environmentVariables.
    # settings.json is JSONC (comments, trailing commas), so only that one key is rewritten as text.
    $file = $CsEditors[$Editor]
    if (-not (Test-Path $file)) {
        New-Item -ItemType File -Force $file | Out-Null
        Set-Content $file "{`n}" -NoNewline
    }
    $text = Get-Content $file -Raw
    Copy-Item $file "$file.bak" -Force

    # Keep any other variables already set in the array
    $others = @()
    $m = [regex]::Match($text, $CsEnvKeyPattern)
    if ($m.Success) {
        $arr = [regex]::Match($m.Value, '\[[^\]]*\]').Value -replace ',(\s*[\]}])', '$1'
        # PowerShell 5.1 emits a parsed JSON array as one object; enumerate it in a second step
        try { $parsed = $arr | ConvertFrom-Json; $others = @($parsed | Where-Object { $_.name -ne "CLAUDE_CONFIG_DIR" }) }
        catch { throw "Could not read claudeCode.environmentVariables in $file. Fix it by hand, then retry." }
        $text = $text.Remove($m.Index, $m.Length)
    }

    $vars = @($others | ForEach-Object { @{ name = $_.name; value = $_.value } })
    if ($Name -ne "main") { $vars += @{ name = "CLAUDE_CONFIG_DIR"; value = (Get-CsDir $Name) } }

    if ($vars.Count -gt 0) {
        $items = $vars | ForEach-Object {
            '{{ "name": "{0}", "value": "{1}" }}' -f $_.name, ($_.value -replace '\\', '\\' -replace '"', '\"')
        }
        $entry = "`n  `"claudeCode.environmentVariables`": [" + ($items -join ", ") + "],"
        $brace = $text.IndexOf("{")
        if ($brace -lt 0) { throw "$file does not look like a settings file." }
        $text = $text.Insert($brace + 1, $entry)
    }
    # Drop blank lines left where the old key was
    $text = [regex]::Replace($text, '(\r?\n)[ \t]*\r?\n', '$1')
    [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($false)))
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
            $inEditor = @{}
            foreach ($e in $CsEditors.Keys) {
                if (Test-Path $CsEditors[$e]) { $inEditor[$e] = Get-CsNameFromDir (Get-CsEditorDir $e) }
            }
            Write-Host ""
            foreach ($n in Get-CsNames) {
                $marks = @()
                if ($n -eq $session) { $marks += "active" }
                if ($n -eq $default) { $marks += "default" }
                foreach ($e in $inEditor.Keys | Sort-Object) { if ($inEditor[$e] -eq $n) { $marks += $e } }
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
            & (Get-CsClaude)
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
                & (Get-CsClaude) @Rest
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

        { $_ -in "cursor", "code" } {
            Assert-CsExists $Name
            Set-CsEditor $Command $Name
            $app = if ($Command -eq "cursor") { "Cursor" } else { "VS Code" }
            Write-Host "$app Claude Code extension -> $Name ($(Get-CsEmail $Name))"
            Write-Host "In $app run 'Developer: Reload Window' (Ctrl+Shift+P) to apply. Backup: $($CsEditors[$Command]).bak"
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
            # Windows PowerShell 5.1 Remove-Item -Recurse can follow junctions and delete the
            # target's files (e.g. main's shared history); unlink junctions with rmdir first.
            Get-ChildItem $dir -Force -Recurse -Attributes ReparsePoint -ErrorAction SilentlyContinue |
                Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object { cmd /c rmdir "$($_.FullName)" | Out-Null; Write-Host "  unlinked $($_.FullName)" }
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
  claude-switch cursor <name>    Switch the Cursor extension to <name> (then Reload Window)
  claude-switch code <name>      Switch the VS Code extension to <name> (then Reload Window)
  claude-switch default <name>   Set the default account (also VS Code; reopen VS Code)
  claude-switch sync <name>      Re-copy settings/skills/memory from main to <name>
  claude-switch remove <name>    Delete an account

  Alias: cs = claude-switch.  "main" = the original account (~\.claude).

"@
        }
    }
}

Set-Alias cs claude-switch

# No claude CLI on PATH: expose the VS Code extension's bundled binary as `claude`
if (-not (Get-Command claude -CommandType Application, ExternalScript -ErrorAction SilentlyContinue)) {
    function claude { & (Get-CsClaude) @args }
}

Register-ArgumentCompleter -CommandName claude-switch, cs -ParameterName Command -ScriptBlock {
    param($cmd, $param, $word)
    "list", "add", "use", "run", "cursor", "code", "default", "sync", "remove", "help" | Where-Object { $_ -like "$word*" }
}
Register-ArgumentCompleter -CommandName claude-switch, cs -ParameterName Name -ScriptBlock {
    param($cmd, $param, $word)
    Get-CsNames | Where-Object { $_ -like "$word*" }
}
