# Contributing

Thanks for your interest in improving Company News Monitor.

## Ways to Contribute

- **Bug reports** — open an issue with reproduction steps
- **Feature requests** — open an issue describing the use case
- **Pull requests** — bug fixes, documentation, new sources
- **Source suggestions** — if you know an RSS feed that should be added

## Development Setup

### Requirements

- Windows 10/11
- PowerShell 5.1 (built-in)
- Git
- Visual Studio Code with [PowerShell extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell) — recommended

### Local Development

1. Fork the repository
2. Clone your fork:
   ```powershell
   git clone https://github.com/YOUR_USERNAME/company-news-monitor.git
   cd company-news-monitor
   ```
3. Create `_bin\secrets.ps1` with a **test** DaData API key:
   ```powershell
   $dadataKey = "YOUR_TEST_KEY"
   ```
4. Add `_config\counterparties.xlsx` (gitignored) or use `samples\counterparties.template.xlsx`.

## Code Style

### PowerShell

- **No Russian characters in `.ps1` code** — use `[char]0x0418` for Cyrillic literals
- **UTF-8 with BOM** for all `.ps1` files
- **Comment-based help** at the top of every function
- **No hardcoded paths** — use `paths.ps1`
- **Prefer `[System.IO.File]::ReadAllLines`** over `Get-Content` for UTF-8 safety
- **Wrap side effects** in `try/catch` and log to `_results\sources_log.txt`

### Batch files

- **ANSI or UTF-8 without BOM** for `.bat` files
- Always `cd /d "%~dp0"` at the top
- Use `set PARSER_NO_PAUSE=1` when calling scripts from batch

### Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short description>
```

Types: `feat:`, `fix:`, `docs:`, `refactor:`, `perf:`, `chore:`.

Examples:
```
feat: add Telegram bot notifications
fix: crash on empty RSS description field
docs: update architecture diagram
perf: replace .Contains() with compiled regex
```

## Pull Request Process

1. Create a branch: `git checkout -b feat/my-feature`
2. Make changes with clear commits
3. Test on a real dataset (at least 10 companies)
4. Update `README.md` if user-facing behavior changed
5. Update `CHANGELOG.md` under `[Unreleased]`
6. Push and open a PR against `main`

### PR Checklist

- [ ] Scripts run without errors on PowerShell 5.1
- [ ] No secrets, real INNs, or personal data in commits
- [ ] `.gitignore` covers new sensitive files
- [ ] Cyrillic text handled correctly
- [ ] Commit messages follow conventional format

## Reporting Bugs

Include:

1. **Environment**: Windows version, PowerShell version
2. **Steps to reproduce**: exact commands
3. **Expected vs. actual behavior**
4. **Logs**: `_results\sources_log.txt` (redact sensitive data)
5. **Screenshots** if applicable

## Adding a New News Source

1. Verify the source is RSS or has stable HTML structure
2. Add to `$sources` array in `_bin\parser.ps1`:
   ```powershell
   @{ Name = "Source Name"; Url = "https://example.com/rss" }
   ```
3. Test on 2–3 runs
4. Update source count in `README.md`
5. Mention in PR description

## Code of Conduct

Be respectful. This is a personal tool shared publicly — no corporate politics, no spam, no self-promotion.

## License

By contributing, you agree your contribution is licensed under the MIT License.