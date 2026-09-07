# Ollama Chat (Web)

A single-file, mobile-friendly chat UI for [Ollama](https://ollama.com). No build step — just open `index.html` in a browser.

## Features
- Streaming responses (token-by-token)
- Stop generation mid-stream
- Server URL + model configurable in-app (⚙️), saved in localStorage
- Conversation history persisted in the browser
- Works on iPhone (Safari), Android, and desktop

## Quick start (use on your iPhone)

The app must be served over **HTTP from the same machine running Ollama** (or any machine on your LAN). This avoids browser mixed-content blocking — a page served over HTTPS (e.g. GitHub Pages) cannot call an `http://` Ollama server.

### 1. Allow cross-origin requests in Ollama

Ollama only allows CORS from localhost by default. Allow all origins:

**Windows** (PowerShell, then restart the Ollama app):
```powershell
setx OLLAMA_ORIGINS "*"
```

**Linux (systemd)**:
```bash
sudo systemctl edit ollama.service
# add:
# [Service]
# Environment="OLLAMA_ORIGINS=*"
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

**macOS**:
```bash
launchctl setenv OLLAMA_ORIGINS "*"
# then quit & reopen the Ollama app
```

### 2. Serve this folder

On the machine running Ollama (e.g. `192.168.1.192`):

```bash
cd web
python -m http.server 8080
```
(or `npx serve` if you prefer Node)

### 3. Open on your iPhone

Make sure the phone is on the **same Wi-Fi** as the Ollama machine, then open in Safari:

```
http://192.168.1.192:8080
```

Tap ⚙️ to set the server URL (`http://192.168.1.192:11434`) and model (e.g. `qwen3.8-vision`) if the defaults don't match.

## Optional: GitHub Pages

You can enable GitHub Pages (repo Settings → Pages → Deploy from branch), but note:
- Pages serves over **HTTPS**, and browsers block HTTPS pages from calling `http://` LAN servers (mixed content). So the Pages URL will **not** be able to reach your Ollama server directly.
- Use Pages as a convenient place to grab the file, then serve it locally as above.

## API used

`POST {server}/api/chat` with `{"model": "...", "messages": [...], "stream": true}` — standard Ollama chat endpoint, NDJSON streaming.
