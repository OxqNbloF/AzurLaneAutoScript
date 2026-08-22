# Contributing

The desktop shell is implemented in `native/main.m` with AppKit and WKWebView. Keep application lifecycle code in the native shell and business/UI behavior in the existing Python WebUI.

Before submitting a change, run:

```bash
npm run compile
npm test
```

The build must remain free of third-party runtime frameworks. Build-only changes belong in `scripts/build-macos-app.js`.
