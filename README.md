# OllamaChat

Chat clients for [Ollama](https://ollama.com) (local LLM inference).

## Contents

| Folder | What it is |
|---|---|
| `web/` | **Browser-based chat** — single-file HTML app, works on iPhone (Safari), Android, desktop. No build step. |
| `*.swift` + `Info.plist` | **SwiftUI app** (iOS/iPadOS) — needs Xcode on a Mac to build. |

## Quick start: use it on your iPhone (web version)

1. On the machine running Ollama, allow cross-origin requests:
   ```powershell
   # Windows (then restart the Ollama app)
   setx OLLAMA_ORIGINS "*"
   ```
2. Serve the web folder:
   ```bash
   cd web
   python -m http.server 8080
   ```
3. On your iPhone (same Wi-Fi), open in Safari:
   ```
   http://<ollama-machine-ip>:8080
   ```
4. Tap ⚙️ to set the server URL (e.g. `http://192.168.1.192:11434`) and model.

> Note: GitHub Pages serves over HTTPS, which browsers block from calling an `http://` LAN Ollama server (mixed content). Serve the file locally as above instead.

See [web/README.md](web/README.md) for full details.

## Building the SwiftUI app

Requires a Mac with Xcode. Create a new iOS App project, add the `.swift` files, and run on a device/simulator on the same Wi-Fi as your Ollama server.
