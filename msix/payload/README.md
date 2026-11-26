# Payload: the window and page

Put the built Escape Reality app here — `EscapeReality.exe` (the window/page)
plus any DLLs, resources, or config files it needs next to the exe.

`build-msix.ps1` copies this folder verbatim to the root of the MSIX package,
so the exe must be at the top level of this folder, not in a subfolder.

Do **not** put the model weights, model key, or policy files here. Those live
on the machine under `C:\ProgramData\EscapeReality` (see `config.psd1`:
`DataSource`) and are copied into the package under `data\` at build time.
Keeping them out of the repo means secrets and large weight files never get
committed.

App icons live in `msix\Assets`, not here.
