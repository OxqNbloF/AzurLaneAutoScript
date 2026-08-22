# Alas native macOS app

This directory builds the native macOS shell for AzurLaneAutoScript. The app uses AppKit and WKWebView and has no bundled browser or third-party runtime dependency.

The native shell preserves the previous desktop behavior:

- starts `gui.py` with the Python executable and WebUI port from `config/deploy.yaml`;
- binds the embedded WebUI to `127.0.0.1` so the local control surface is not exposed to the LAN;
- displays the existing Alas WebUI in a native window;
- keeps automation running when the window is closed or hidden;
- reopens from the Dock, enforces a single app instance, and supports reload/full-screen shortcuts;
- prevents automatic system sleep with `caffeinate` while the Python service is running;
- terminates the Python process group when the app quits.

## Requirements

- macOS 12 or newer;
- Apple Command Line Tools (`xcode-select --install`);
- a working Alas Python environment configured in `../config/deploy.yaml`;
- Node.js 20.19+ or 22.12+ only for running the small build script.

## Build

```bash
npm ci
npm run compile
```

The local, ad-hoc signed application is generated at `dist/Alas.app`. It locates the AzurLaneAutoScript checkout by walking upward from the app bundle. When the bundle is moved elsewhere, set `ALAS_PATH` to the repository root before launching it.

```bash
ALAS_PATH=/path/to/AzurLaneAutoScript open dist/Alas.app
```

Run `npm test` after building to verify the bundle, signature metadata, property list, and linked system frameworks.
