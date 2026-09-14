# Recommended GitHub repo structure (OTC Bus 1.2.6)

Publish these files (this staging folder):

```
otc-bus/
  README.md
  CHANGELOG-1.2.6.md
  OTC-BUS-SPEC.md
  PRODUCT-NOTES.md
  otc-bridge.ps1
  otc-enqueue.ps1
  otc-wait.ps1
  otc-status.ps1
  otc-watch-install.ps1
  otc-events-tail.ps1
  otc-notify-drain.ps1
  otc-notify-install.ps1
  .gitignore
```

## Exclude from GitHub (runtime / secrets / noise)

- pending/, failed/, archive/, logs/, events/, testdata/
- inbox.jsonl, outbox.jsonl, progress.json, state.json
- *.bak*, *.bak-*, otc-bridge.ps1.bak-*, otc-enqueue.ps1.bak-*
- secrets, API keys, tokens, .env
- local install mirrors under %USERPROFILE%\OffTheClock\bus runtime copies

## Suggested .gitignore

```
pending/
failed/
archive/
logs/
events/
testdata/
inbox.jsonl
outbox.jsonl
progress.json
state.json
*.bak*
*.log
.env
*.zip
```

## Notes

- Live runtime: `C:\OffTheClock\bus` (BridgeVersion 1.2.6)
- Release zip mirror: `C:\Users\crisi\OffTheClock\bus\otc-bus-v1.2.6.zip`
- Do not commit job payloads or agent transcripts