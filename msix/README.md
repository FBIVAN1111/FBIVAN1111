# Escape Reality — MSIX packaging

This folder rebuilds the **1.0.1.0** MSIX package, signs it, and installs it
with **one command**. It also fixes the two gaps in the old two-script
command: the local files a command cannot create are now bundled into the
package, and a running Escape Reality window no longer blocks the install.

## The one command

From the repo root (e.g. `C:\escape-reality`):

```powershell
powershell -ExecutionPolicy Bypass -File C:\escape-reality\msix\build-and-install.ps1
```

That is the whole job: build → sign → install. You do **not** need to close
the Escape Reality window first — the script closes it for you before
installing (pass `-NoClose` to opt out).

The old command still works, but it is weaker:

```powershell
powershell -ExecutionPolicy Bypass -Command "& 'C:\escape-reality\msix\build-msix.ps1'; & 'C:\escape-reality\msix\sign-and-install.ps1'"
```

With `;`, the second script runs even if the first one fails, so a failed
build could still try to sign/install a stale package. `build-and-install.ps1`
runs the same two scripts in order and stops on the first failure, so the
exit code tells you whether the whole thing worked.

## What is in the package vs. what is local

The MSIX package only contains the window/page payload by itself. The whole
app also needs local files that are not in the repo:

| Files | Where they live | What the build does |
|---|---|---|
| Window/page (`EscapeReality.exe` + its files) | `msix\payload\` | Copied to the package root |
| Model weights | `C:\ProgramData\EscapeReality\` | Copied to `data\` in the package |
| Model key | `C:\ProgramData\EscapeReality\` | Copied to `data\` in the package |
| Policy files | `C:\ProgramData\EscapeReality\` | Copied to `data\` in the package |

`build-msix.ps1` copies the entire `DataSource` folder (default
`C:\ProgramData\EscapeReality`, set in `config.psd1`) into `data\` and writes
`data\MANIFEST.txt` listing what was bundled. Pass `-DataSource <path>` to
use a different folder, or `-SkipLocalData` to build without them.

> **App integration note:** a packaged app's install folder is read-only, so
> the app should resolve its data folder as `<install dir>\data` when it
> exists, falling back to `C:\ProgramData\EscapeReality`. Anything the app
> needs to *write* must go to its local state folder or `ProgramData`, not
> the install folder.

> **Security note:** bundling the model key means anyone who gets the
> `.msix` file can extract the key from it. Treat the package like a secret:
> do not publish it or share it outside your machine. If the key must stay
> off the package, keep it in `ProgramData` only and pass `-SkipLocalData`.

## Prerequisites

- Windows 10 (1809+) or Windows 11, with **Developer Mode** on
  (Settings > Privacy & security > For developers > Developer Mode) —
  required to sideload a `runFullTrust` package.
- The **Windows 10/11 SDK**, which provides `MakeAppx.exe` and
  `SignTool.exe`. The scripts find them automatically under
  `Program Files\Windows Kits\10\bin`.
- The built app in `msix\payload\` (`EscapeReality.exe` at the top level).
  See `msix\payload\README.md`.
- The local files in `C:\ProgramData\EscapeReality\` (or `-SkipLocalData`).
- Administrator rights are **not** required, but if you run the script as
  Administrator the signing certificate is trusted in the machine store;
  otherwise it is trusted for your user account only.

## What each script does

- **`build-msix.ps1`** — stages `payload\` into `layout\`, bundles the local
  files into `layout\data\`, generates `AppxManifest.xml` from the template
  + `config.psd1`, copies `Assets\`, and packs with MakeAppx to
  `out\EscapeReality_1.0.1.0_x64.msix`.
- **`sign-and-install.ps1`** — creates/reuses a self-signed certificate whose
  Subject matches `Publisher` in `config.psd1` (so the manifest and the
  signature always agree), trusts it, signs with SignTool (SHA256), closes a
  running Escape Reality process, removes any existing install of the same
  identity, and installs with `Add-AppxPackage` (retrying once on
  `0x80073D02`).
- **`build-and-install.ps1`** — the one-command orchestrator above.
- **`Test-MsixScripts.ps1`** — preflight only (no build/sign/install):
  checks PowerShell, SDK tools, payload, local data, manifest, assets, and
  script syntax, and prints PASS/WARN/FAIL lines.
- **`tests\MsixScripts.Tests.ps1`** — Pester tests for structure and syntax.
  Run with `Invoke-Pester .\msix\tests`.

## Configuration

Edit `config.psd1` — it is the single source of truth:

- `IdentityName`, `Publisher`, `PublisherDisplayName`, `Version` (`1.0.1.0`),
  `ProcessorArchitecture`, `AppExe`, `DataSource`.

`Publisher` must match the signing certificate's Subject exactly (including
`CN=`). The scripts create a matching self-signed certificate automatically,
so the default works for local sideloading. If you use your own certificate,
make its Subject identical to `Publisher`.

The PFX password comes from the `ESCAPE_REALITY_PFX_PASSWORD` environment
variable, `-PfxPassword`, or a prompt when the PFX is first created. The PFX
itself is written to `msix\out\` and is git-ignored — never commit it.

## Troubleshooting

| Symptom | Meaning | Fix |
|---|---|---|
| `0x80073D02` | The app (or another install) is running | The script closes it for you. If it persists, close the window manually and retry without `-NoClose`. |
| `0x800B0109` | The signing certificate is not trusted | Re-run without `-SkipTrustInstall` (as Administrator for the machine store), or import the `.pfx` into Trusted People manually. |
| `0x80073CF0` / publisher mismatch | Certificate Subject ≠ manifest `Publisher` | Make `Publisher` in `config.psd1` identical to the certificate Subject. |
| `MakeAppx.exe` / `SignTool.exe` not found | Windows SDK missing | Install the Windows 10/11 SDK, then re-run `Test-MsixScripts.ps1`. |
| `Local data folder not found` | `C:\ProgramData\EscapeReality` missing | Create it with the weights/key/policies, set `DataSource` in `config.psd1`, or pass `-SkipLocalData`. |
| `App executable not found` | Payload missing | Put `EscapeReality.exe` in `msix\payload\`. |
| Execution policy error | Script blocked | Use `-ExecutionPolicy Bypass` as in the command above. |
| Deployment failed, no code | Generic AppX failure | Check Event Viewer: Application log → Microsoft → Windows → AppXDeployment-Server. |

## Status

These scripts are new and have been syntax- and structure-checked (manifest
XML, token replacement, script parsing, asset sizes), but they have **not**
been run on Windows in this environment — there is no Windows machine here to
build, sign, and install on. Run `Test-MsixScripts.ps1` first; if the real
command fails, paste the error output here and it can be fixed from there.
