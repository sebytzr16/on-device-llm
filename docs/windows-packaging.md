# Windows release packaging

Run commands from the repository root in Windows PowerShell 5.1. Requirements:
Flutter on PATH, Visual Studio Build Tools with Desktop development with C++, and
the native sources required by `scripts/build-windows-native.ps1`. CUDA builds
also need the NVIDIA CUDA Toolkit with `CUDA_PATH` set. Install Inno Setup 6.3
or later to produce an installer; without it the ZIP is still produced.

Vulkan builds use the local `.tools/Vulkan-Headers` and `.tools/SPIRV-Headers`
plus the newest NDK with Windows `glslc` under `%LOCALAPPDATA%\Android\Sdk\ndk`.
No Vulkan SDK is needed. The build generates an import library from the installed
System32 loader in `build/native-windows/x64-vulkan`; `vulkan-1.dll` comes from
the graphics driver and is never bundled.

## Build

```powershell
powershell -NoProfile -File scripts/package-windows.ps1 -DryRun
powershell -NoProfile -File scripts/package-windows.ps1 -All
powershell -NoProfile -File scripts/package-windows.ps1
powershell -NoProfile -File scripts/package-windows.ps1 -Cuda
powershell -NoProfile -File scripts/package-windows.ps1 -Vulkan
powershell -NoProfile -File scripts/package-windows.ps1 -Cuda -Vulkan
```

If the machine's execution policy blocks local scripts, use the process-only
option `powershell -NoProfile -ExecutionPolicy Bypass -File` with the same script
and switches. This does not change the machine's execution policy.

`-DryRun` can be combined with `-All`, `-Cuda` and/or `-Vulkan`. It parses the version,
discovers ISCC, prints the plan, and creates no files or builds. ISCC discovery checks Inno Setup
folders under Program Files and Program Files (x86), then PATH.

`-All` builds CPU, SSE4.2 compat, CUDA and Vulkan in one portable ZIP named
`ondevice-llm-<VERSION>-windows-x64.zip`, without a variant suffix. This is the
tester release command. Every ZIP also gets a `.zip.sha256` checksum file,
created after any signing, and includes [tester instructions](windows-testers.md)
as `README.md`.

The real run always builds the CPU and compat bridges, additionally builds CUDA with `-Cuda`
and Vulkan with `-Vulkan`, then runs `flutter build windows --release`. It copies the complete Release
directory into a fresh `build/windows-packaging/<BUNDLE_ID>/bundle` directory.
Packages exclude unrequested Vulkan and CUDA DLLs even if an earlier GPU build
left them in Release. CUDA packages require the GPU bridge and all three runtime DLL families.
Vulkan packages require `ondevice_llm_vulkan.dll`. Combined builds use the
`cuda-vulkan` filename suffix; Vulkan-only builds use `vulkan`.
The prepared bundle is retained for inspection and for manual signing when
`ODL_SIGN_CERT` is not configured.

The version comes from `pubspec.yaml`, including its build suffix. Outputs are
under the git-ignored `artifacts/windows` directory:

- `ondevice-llm-<VERSION>-windows-x64-cpu.zip` (`-cuda.zip`, `-vulkan.zip` or `-cuda-vulkan.zip`).
- `ondevice-llm-<VERSION>-windows-x64-cpu-setup.exe` (`-cuda-setup.exe`, `-vulkan-setup.exe` or `-cuda-vulkan-setup.exe`)
  when ISCC is available.

Existing outputs of the same version and variant are overwritten. SHA-256 is
printed for each output. ZIP contents start with `ondevice_llm.exe` at the root;
extract the whole archive before running it. Deliver the Flutter/plugin DLLs and
the `data` directory together. Packaging copies the app-local Microsoft Visual
C++ x64 runtime from the selected Build Tools installation's
`VC/Redist/MSVC/<version>/x64/Microsoft.VC*.CRT` directory. It includes the
available `msvcp140`, `msvcp140_1`, `msvcp140_2`, `vcruntime140`,
`vcruntime140_1` and `concrt140` DLLs, and fails if the required CRT cannot be
found. No runtime installer is needed. Test on a clean target machine before release.

## Installer components

The [Inno Setup definition](../windows/installer/ondevice_llm.iss) installs per
user under `{localappdata}\Programs\OnDevice LLM` without requesting admin rights.
It creates a Start menu shortcut, offers an initially unchecked desktop shortcut,
registers an uninstaller, and uses `windows/runner/resources/app_icon.ico` for
Setup. The application executable supplies the installed shortcut/uninstall icon.

| Component | Contents | Selection |
| --- | --- | --- |
| OnDevice LLM and CPU inference | Executable, `ondevice_llm.dll`, `ondevice_llm_compat.dll`, VC++ runtime, Flutter/plugin DLLs, assets and `data` | Always installed; cannot be unchecked |
| GPU acceleration (Vulkan) | `ondevice_llm_vulkan.dll` | Offered and selected with `-Vulkan`; can be unchecked in Custom installation |
| NVIDIA GPU acceleration (CUDA 13 + 12) | `ondevice_llm_cuda.dll`, `ondevice_llm_cuda12.dll`, `cudart64_*.dll`, `cublas64_*.dll`, `cublasLt64_*.dll` | Offered and selected in a CUDA build; can be unchecked using Custom installation; absent from a CPU build |

CUDA adds roughly 0.5 GB before compression. The NVIDIA driver, including
`nvcuda.dll`, must already be installed on the target machine and is not bundled.
The CPU component remains available as the application's fallback. A CUDA ZIP
contains CPU and CUDA backends without an installer component picker.

Inno Setup remembers component choices on upgrades. Switching to a CPU installer
or deselecting CUDA/Vulkan removes the previously packaged GPU DLLs from the install
directory. Uninstall removes installed application files and shortcuts. It leaves
chats, downloaded models, settings and other application data in AppData intact;
there are no user-data deletion entries. Component selection follows the
[Inno Setup component rules](https://jrsoftware.org/ishelp/topic_componentssection.htm).

## Sign with the publisher's certificate

Packaging is unsigned by default. For a release, set `ODL_SIGN_CERT` to the
thumbprint of the publisher's code-signing certificate, installed with its private
key in the current user's certificate store (or exposed by the publisher's hardware
signing provider). Optionally set `ODL_SIGN_TIMESTAMP_URL` to an RFC 3161
timestamp service. SignTool must be on PATH or installed under
`Windows Kits\10\bin`. Keep private keys and certificate passwords out of the
repository and command history.

```powershell
$env:ODL_SIGN_CERT = '<CERTIFICATE_THUMBPRINT>'
$env:ODL_SIGN_TIMESTAMP_URL = '<RFC3161_TIMESTAMP_URL>'
powershell -NoProfile -File scripts/package-windows.ps1 -All -RequireSignature
```

With `ODL_SIGN_CERT` set, packaging signs `ondevice_llm.exe`, every
`ondevice_llm*.dll` bridge, `ondevice_sd.dll` and `diffusiongemma/dg_host.exe`
in the prepared bundle, then verifies each signature with `signtool verify /pa`.
Third-party DLLs keep their existing vendor signatures. The engine manifest,
ZIP and installer are produced after signing, so their hashes cover the signed
bytes, and the installer (`<OUTPUT_BASE>-setup.exe`) is signed and verified after
Inno Setup compiles it. Any signing or verification failure stops packaging.

`-RequireSignature` fails the run when no certificate is configured, before any
archive is produced. Use it for release builds and omit it for unsigned test
packages. `-DryRun` reports whether signing is configured without requiring a
certificate. Signing is a build-machine step: the timestamp request is the only
network operation and it happens during packaging, not in the application or
installer. Check the publisher name and signature on a clean machine before
publishing. Publish hashes only after signing, because signing changes the bytes.

### Manual signing fallback

If automatic signing is not used (for example the certificate is only reachable
through a separate signing machine), sign the prepared bundle's application
executable and project-owned native DLLs by hand before rebuilding the ZIP and
installer. Preserve existing vendor signatures on third-party binaries. Repeat
signing for the compat, CUDA and Vulkan bridges when present:

```powershell
$bundle = 'build/windows-packaging/<BUNDLE_ID>/bundle'
signtool sign /sha1 '<CERTIFICATE_THUMBPRINT>' /fd SHA256 /tr '<RFC3161_TIMESTAMP_URL>' /td SHA256 "$bundle/ondevice_llm.exe"
signtool sign /sha1 '<CERTIFICATE_THUMBPRINT>' /fd SHA256 /tr '<RFC3161_TIMESTAMP_URL>' /td SHA256 "$bundle/ondevice_llm.dll"
signtool verify /pa /v "$bundle/ondevice_llm.exe"
```

Check each command's exit code. Use the retained bundle, rather than rerunning
the packaging script without `ODL_SIGN_CERT`, which would rebuild unsigned
binaries. Recreate the ZIP from that signed bundle (remove the old ZIP first):

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path (Get-Location) 'artifacts/windows/<OUTPUT_BASE>.zip'
[System.IO.Compression.ZipFile]::CreateFromDirectory((Resolve-Path -LiteralPath $bundle).Path, $zip)
```

Recompile the installer with the same version and bundle. Set `IncludeCuda=1`
only for a bundle containing the CUDA DLLs; use `0` otherwise. Set
`IncludeVulkan=1` only when the Vulkan bridge is in the bundle. `AppNumericVersion`
is the three numeric version fields without prerelease or build suffixes.
Replace `<ISCC_EXE>` with the compiler command or a quoted compiler path:

```powershell
& '<ISCC_EXE>' '/DAppVersion=<VERSION>' '/DAppNumericVersion=<MAJOR.MINOR.PATCH>' '/DIncludeCuda=<0_OR_1>' '/DIncludeVulkan=<0_OR_1>' `
  "/DBundleDir=$((Resolve-Path -LiteralPath $bundle).Path)" `
  "/DOutputDir=$((Resolve-Path -LiteralPath 'artifacts/windows').Path)" `
  '/DOutputBaseName=<OUTPUT_BASE>-setup' 'windows/installer/ondevice_llm.iss'
signtool sign /sha1 '<CERTIFICATE_THUMBPRINT>' /fd SHA256 /tr '<RFC3161_TIMESTAMP_URL>' /td SHA256 'artifacts/windows/<OUTPUT_BASE>-setup.exe'
signtool verify /pa /v 'artifacts/windows/<OUTPUT_BASE>-setup.exe'
Get-FileHash -Algorithm SHA256 -LiteralPath 'artifacts/windows/<OUTPUT_BASE>.zip', 'artifacts/windows/<OUTPUT_BASE>-setup.exe'
```

Publish hashes only after signing: signing changes the bytes. The timestamp
request is a release-time operation on the build machine. Packaging adds no
network calls to the application or installer. See Microsoft's
[SignTool reference](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)
for certificate selection, timestamping and verification options.

## Optional GGUF file association

The Inno installer includes an unchecked **Open .gguf files with OnDevice LLM**
task (`ggufassociation`), with English, French and Spanish labels. It registers
`OnDeviceLLM.GGUF` and `.gguf\OpenWithProgids` under
`HKCU\Software\Classes`; no elevation or machine-wide association is needed.
The open command quotes both the executable and `%1`, so paths with spaces work.
An unassigned `.gguf` extension gets this ProgID; existing defaults and Windows
UserChoice are respected. Users can also choose the app through Open with.
Uninstall removes the app's ProgID and Open with entry, and clears the extension
default only if it still names this app. Chats and model files are retained.

The runner forwards the path to the existing instance when one is running;
otherwise `getInitialArgs` delivers it on startup. Both routes open desktop
Models and run its existing validated import flow. Installer compilation and
clean-machine install/uninstall remain release checks when Inno Setup is
available; the development verification used direct executable arguments.

## Optional MSIX

The `msix` dev dependency is currently absent and is not needed for ZIP or Inno
Setup packaging. To adopt MSIX separately, run `flutter pub add --dev msix`, add
`msix_config` to `pubspec.yaml` with the publisher's registered package identity,
publisher identity matching their certificate, display name, logo and four-part
MSIX version, then run `dart run msix:create`. Keep certificate secrets outside
tracked configuration. Review the package's
[configuration documentation](https://pub.dev/documentation/msix/latest/).

Build and inspect the desired CPU/CUDA/Vulkan Release bundle first: MSIX does not inherit
the Inno Setup optional component picker, and its default build may collect stale
CUDA files from Release. Use a clean Release directory for the intended variant.
MSIX needs a separate signing and clean-machine installation check before it is
offered as a release format.

Windows library selection on AVX2 CPUs is CUDA (if its driver and DLL load), then Vulkan
(if the loader exists and the bridge reports hardware GPU devices), then CPU.
For testing, set `$env:ODLLM_WINDOWS_BACKEND='vulkan'` before launching the app;
`cpu`, `cuda` and `compat` are also accepted. A failed forced GPU falls directly to CPU.
Without AVX2, all three AVX2 bridges are skipped and the SSE4.2 compat bridge
is used, even with a GPU override. If compat is absent, a diagnostic records
the legacy normal CPU fallback; that DLL may crash on the old CPU, so release
packages always require compat. Build it separately with
`scripts/build-windows-native.ps1 -Compat` (`build/native-windows/x64-compat`).
Backend and skip reasons appear in inference metrics; Settings names Vulkan
explicitly. AMD and clean-machine installer validation remain release checks.
