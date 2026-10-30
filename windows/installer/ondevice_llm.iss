; Compiled by scripts/package-windows.ps1 using Inno Setup 6.3 or later.
#ifndef AppVersion
  #error AppVersion must be supplied by the packaging script
#endif
#ifndef AppNumericVersion
  #error AppNumericVersion must be supplied by the packaging script
#endif
#ifndef BundleDir
  #error BundleDir must point to the prepared release bundle
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by the packaging script
#endif
#ifndef OutputBaseName
  #error OutputBaseName must be supplied by the packaging script
#endif
#ifndef IncludeCuda
  #define IncludeCuda 0
#endif

#ifndef IncludeVulkan
  #define IncludeVulkan 0
#endif

[Setup]
AppId={{4E41CEB6-ED28-478E-975A-94A8CF166E53}
AppName=OnDevice LLM
AppVersion={#AppVersion}
VersionInfoVersion={#AppNumericVersion}
DefaultDirName={localappdata}\Programs\OnDevice LLM
DefaultGroupName=OnDevice LLM
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\ondevice_llm.exe
Uninstallable=yes
ChangesAssociations=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes

[Types]
Name: "standard"; Description: "Standard installation"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[CustomMessages]
english.GgufTask=Open .gguf files with OnDevice LLM
french.GgufTask=Ouvrir les fichiers .gguf avec OnDevice LLM
spanish.GgufTask=Abrir archivos .gguf con OnDevice LLM
english.FileAssociations=File associations:
french.FileAssociations=Associations de fichiers :
spanish.FileAssociations=Asociaciones de archivos:
english.GgufModel=GGUF model
french.GgufModel=Modèle GGUF
spanish.GgufModel=Modelo GGUF

[Components]
Name: "cpu"; Description: "OnDevice LLM and CPU inference (required)"; Types: standard custom; Flags: fixed
#if IncludeCuda
Name: "cuda"; Description: "NVIDIA GPU acceleration (CUDA 13, plus CUDA 12 for older drivers and GTX 10-series cards)"; Types: standard
#endif

#if IncludeVulkan
Name: "vulkan"; Description: "GPU acceleration (Vulkan)"; Types: standard
#endif

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked
Name: "ggufassociation"; Description: "{cm:GgufTask}"; GroupDescription: "{cm:FileAssociations}"; Flags: unchecked

[Registry]
; Only claim an unassigned extension. Windows UserChoice is never changed.
Root: HKCU; Subkey: "Software\Classes\.gguf"; ValueType: string; ValueData: "OnDeviceLLM.GGUF"; Tasks: ggufassociation; Flags: createvalueifdoesntexist uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\Classes\.gguf\OpenWithProgids"; ValueType: string; ValueName: "OnDeviceLLM.GGUF"; ValueData: ""; Tasks: ggufassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\OnDeviceLLM.GGUF"; ValueType: string; ValueData: "{cm:GgufModel}"; Tasks: ggufassociation; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\OnDeviceLLM.GGUF\DefaultIcon"; ValueType: string; ValueData: """{app}\ondevice_llm.exe"",0"; Tasks: ggufassociation
Root: HKCU; Subkey: "Software\Classes\OnDeviceLLM.GGUF\shell\open\command"; ValueType: string; ValueData: """{app}\ondevice_llm.exe"" ""%1"""; Tasks: ggufassociation

[Files]
; The base component includes the compat bridge and app-local VC++ CRT DLLs.
; Keep GPU files out of the required component, including in CUDA builds.
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "engine-manifest.json,ondevice_sd.dll,diffusiongemma,ondevice_llm_compat.dll,msvcp140*.dll,vcruntime140*.dll,concrt140.dll,ondevice_llm_vulkan.dll,ondevice_llm_cuda.dll,ondevice_llm_cuda12.dll,cudart64_*.dll,cublas64_*.dll,cublasLt64_*.dll"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: cpu
Source: "{#BundleDir}\ondevice_llm_compat.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: cpu
Source: "{#BundleDir}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: cpu
Source: "{#BundleDir}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: cpu
Source: "{#BundleDir}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: cpu
Source: "{#BundleDir}\msvcp140_1.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist; Components: cpu
Source: "{#BundleDir}\msvcp140_2.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist; Components: cpu
Source: "{#BundleDir}\concrt140.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist; Components: cpu
#if IncludeCuda
Source: "{#BundleDir}\ondevice_llm_cuda.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: cuda
Source: "{#BundleDir}\ondevice_llm_cuda12.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: cuda
Source: "{#BundleDir}\cudart64_*.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: cuda
Source: "{#BundleDir}\cublas64_*.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: cuda
Source: "{#BundleDir}\cublasLt64_*.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: cuda
; Pictures, videos and DiffusionGemma are CUDA builds.
Source: "{#BundleDir}\ondevice_sd.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist; Components: cuda
Source: "{#BundleDir}\diffusiongemma\*"; DestDir: "{app}\diffusiongemma"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist; Components: cuda
#endif

#if IncludeVulkan
Source: "{#BundleDir}\ondevice_llm_vulkan.dll"; DestDir: "{app}"; Flags: ignoreversion; Components: vulkan
#endif

Source: "{#ManifestDir}\cpu.json"; DestDir: "{app}"; DestName: "engine-manifest.json"; Flags: ignoreversion; Check: EngineSelection('cpu')
Source: "{#ManifestDir}\cuda.json"; DestDir: "{app}"; DestName: "engine-manifest.json"; Flags: ignoreversion; Check: EngineSelection('cuda')
Source: "{#ManifestDir}\vulkan.json"; DestDir: "{app}"; DestName: "engine-manifest.json"; Flags: ignoreversion; Check: EngineSelection('vulkan')
Source: "{#ManifestDir}\cuda-vulkan.json"; DestDir: "{app}"; DestName: "engine-manifest.json"; Flags: ignoreversion; Check: EngineSelection('cuda-vulkan')

[Icons]
Name: "{group}\OnDevice LLM"; Filename: "{app}\ondevice_llm.exe"
Name: "{autodesktop}\OnDevice LLM"; Filename: "{app}\ondevice_llm.exe"; Tasks: desktopicon

[InstallDelete]
; Remove only old packaged GPU binaries when upgrading to CPU or deselecting CUDA.
#if IncludeCuda
Type: files; Name: "{app}\ondevice_llm_cuda.dll"; Check: not WizardIsComponentSelected('cuda')
Type: files; Name: "{app}\ondevice_llm_cuda12.dll"; Check: not WizardIsComponentSelected('cuda')
Type: files; Name: "{app}\cudart64_*.dll"; Check: not WizardIsComponentSelected('cuda')
Type: files; Name: "{app}\cublas64_*.dll"; Check: not WizardIsComponentSelected('cuda')
Type: files; Name: "{app}\cublasLt64_*.dll"; Check: not WizardIsComponentSelected('cuda')
#else
Type: files; Name: "{app}\ondevice_llm_cuda.dll"
Type: files; Name: "{app}\ondevice_llm_cuda12.dll"
Type: files; Name: "{app}\cudart64_*.dll"
Type: files; Name: "{app}\cublas64_*.dll"
Type: files; Name: "{app}\cublasLt64_*.dll"
#endif

#if IncludeVulkan
Type: files; Name: "{app}\ondevice_llm_vulkan.dll"; Check: not WizardIsComponentSelected('vulkan')
#else
Type: files; Name: "{app}\ondevice_llm_vulkan.dll"
#endif

; No AppData cleanup: chats, models, settings and other user data are retained.

[Code]
function EngineSelection(Selection: String): Boolean;
var
  Selected: String;
begin
  Selected := '';
#if IncludeCuda
  if WizardIsComponentSelected('cuda') then Selected := 'cuda';
#endif
#if IncludeVulkan
  if WizardIsComponentSelected('vulkan') then begin
    if Selected <> '' then Selected := Selected + '-';
    Selected := Selected + 'vulkan';
  end;
#endif
  if Selected = '' then Selected := 'cpu';
  Result := Selected = Selection;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ProgId: String;
begin
  if CurUninstallStep = usUninstall then
    if RegQueryStringValue(HKCU, 'Software\Classes\.gguf', '', ProgId) then
      if ProgId = 'OnDeviceLLM.GGUF' then
        RegDeleteValue(HKCU, 'Software\Classes\.gguf', '');
end;
