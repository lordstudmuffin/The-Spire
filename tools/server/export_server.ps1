<#
.SYNOPSIS
  Exports the dedicated server build(s) with the presets in export_presets.cfg.

.DESCRIPTION
  Needs the Godot 4.3 export templates once: in the editor, Editor > Manage
  Export Templates > Download and Install (or unpack
  Godot_v4.3-stable_export_templates.tpz into
  %APPDATA%\Godot\export_templates\4.3.stable\).
  Writes build\linux-server\ and/or build\windows-server\ (git-ignored).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\server\export_server.ps1 -Platform linux
#>
param(
	[ValidateSet("linux", "windows", "both")][string]$Platform = "both",
	[string]$Godot = "C:\Godot\Godot_v4.3-stable_win64_console.exe"
)
$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot (pass -Godot)." }
$templates = Join-Path $env:APPDATA "Godot\export_templates\4.3.stable"
if (-not (Test-Path $templates)) {
	Write-Warning "Export templates for 4.3 are not installed ($templates). Install them from the editor: Editor > Manage Export Templates."
	exit 1
}
$jobs = @()
if ($Platform -ne "windows") { $jobs += ,@("Linux Dedicated Server", "build\linux-server\the-spire-server.x86_64") }
if ($Platform -ne "linux") { $jobs += ,@("Windows Dedicated Server", "build\windows-server\the-spire-server.exe") }
foreach ($j in $jobs) {
	$out = Join-Path $root $j[1]
	New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
	Write-Host "Exporting '$($j[0])' -> $out"
	& $Godot --headless --path $root --export-release $j[0] $out 2>&1 | ForEach-Object { "$_" } |
		Where-Object { $_ -notmatch "Parameter .m. is null" }
	if (-not (Test-Path $out)) { Write-Error "Export of '$($j[0])' failed (see output above)."; exit 1 }
	Copy-Item (Join-Path $root "tools\server\run_server.sh") (Split-Path $out) -Force
}
Write-Host "Done. Linux: build\linux-server\ (+ run_server.sh). Windows: build\windows-server\ (run tools\server\run_server.bat)."
