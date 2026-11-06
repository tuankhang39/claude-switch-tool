# claude-switch

Switch between multiple Claude Code accounts on Windows (PowerShell).

Each account gets its own config directory, and claude-switch points the `CLAUDE_CONFIG_DIR` environment variable at it. That variable is Claude Code's own supported mechanism; claude-switch never edits or swaps credential files.

## Requirements

- Windows PowerShell 5.1 or later
- Claude Code installed (`claude` runs in your terminal)

## Install

```powershell
git clone https://github.com/tuankhang39/claude-switch-tool.git "$HOME\.claude-switch"
cd "$HOME\.claude-switch"
.\install.ps1
```

`install.ps1` adds one line to your `$PROFILE` so `claude-switch.ps1` loads in every new terminal. It is safe to run more than once.

If PowerShell refuses to run the script, allow local scripts first:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Restart your terminal and run `cs help`.

## Usage

`cs` is an alias for `claude-switch`. Commands and account names tab-complete.

| Command | What it does |
|---|---|
| `cs` | List accounts with their email. `*` marks the one this terminal uses |
| `cs add <name>` | Create an account, copy shared config from `main`, and start Claude Code so you can `/login` |
| `cs use <name>` | Switch the current terminal to that account |
| `cs run <name> [args]` | Run `claude` as that account without switching the terminal |
| `cs default <name>` | Set the default account for new terminals and the VS Code extension |
| `cs sync <name>` | Re-copy settings, skills and memory from `main` |
| `cs remove <name>` | Delete an account (asks for confirmation) |

Example:

```powershell
cs add work          # first time: create the account, then /login
cs use work          # this terminal now uses work
claude
cs run main -c       # open main and continue its most recent session
cs default work      # VS Code and new terminals default to work
```

## Where accounts are stored

| Account | Directory |
|---|---|
| `main` | `~\.claude`, Claude Code's default. claude-switch never modifies it |
| Others | `~\.claude-accounts\<name>` |

`add` and `sync` copy these from `main`: `settings.json`, `CLAUDE.md`, `keybindings.json`, `skills\`, `agents\`, `commands\`, and each project's `memory\` folder. They **never** copy `.credentials.json`.

## Notes

- **VS Code:** the extension reads environment variables only when VS Code starts. After `cs default <name>`, close **all** VS Code windows and reopen.
- **Parallel sessions:** each terminal can use a different account at the same time.
- **No automatic sync:** after an account is created, changes to settings or memory in `main` do not carry over on their own. Run `cs sync <name>` when you want them.
- **Uninstall:** remove the `claude-switch.ps1` line from `$PROFILE`, run `cs default main`, then delete `~\.claude-switch`. Delete `~\.claude-accounts` only if you no longer need the extra accounts.

## License

MIT
