# FBIVAN1111

Escape Reality — Windows app packaged as an MSIX (1.0.1.0).

The packaging scripts, manifest template, and build docs live in
[`msix/`](msix/README.md). The one command that rebuilds, signs, and installs
the package (including the local model weights, key, and policy files under
`C:\ProgramData\EscapeReality`) is:

```powershell
powershell -ExecutionPolicy Bypass -File C:\escape-reality\msix\build-and-install.ps1
```

See [`msix/README.md`](msix/README.md) for prerequisites, configuration, and
troubleshooting.
