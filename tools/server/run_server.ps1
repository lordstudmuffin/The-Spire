<#
.SYNOPSIS
  Runs one dedicated floor server of The Spire on Windows, restarting it if it
  stops, with its data and logs in one folder.

.DESCRIPTION
  Uses the exported server (build\windows-server\the-spire-server.console.exe)
  when it exists, otherwise Godot 4.3 running the project from source.
  Press Ctrl+C to stop (no restart after Ctrl+C).

  Data (character records, realm DB, Godot's own log) lives in
  <DataDir>\Godot\app_userdata\Anime Life RPG\, and this script's console logs
  in <DataDir>\logs\. Give every server you run at once its own -Port AND its
  own -DataDir: two servers must never share one data folder.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\server\run_server.ps1
.EXAMPLE
  tools\server\run_server.ps1 -Port 4434 -Name "Test Realm II" -DataDir "$env:LOCALAPPDATA\TheSpireServer2"
#>
param(
	[int]$Port = 4433,
	[int]$Floor = 1,
	[string]$Name = "",
	[string]$Realm = "server",
	[ValidateRange(1, 30)][int]$Capacity = 30,
	[string]$DataDir = "$env:LOCALAPPDATA\TheSpireServer",
	# Path to a server binary or Godot 4.3 console exe; found automatically when empty.
	[string]$Godot = "",
	[switch]$NoRestart,
	# Log a players / mobs / memory health line every few seconds.
	[switch]$Report
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($Name -eq "") { $Name = "Floor $Floor" }

$argv = @("--headless")
if ($Godot -eq "") {
	$exported = Join-Path $root "build\windows-server\the-spire-server.console.exe"
	if (Test-Path $exported) {
		$Godot = $exported
	} else {
		foreach ($c in @("$env:GODOT", "C:\Godot\Godot_v4.3-stable_win64_console.exe")) {
			if ($c -and (Test-Path $c)) { $Godot = $c; break }
		}
		if ($Godot -eq "") { throw "No server binary found. Export 'Windows Dedicated Server' or pass -Godot <path to Godot_v4.3-stable_win64_console.exe>." }
		$argv += @("--path", $root)
	}
}
$argv += @("--", "--server", "--port", "$Port", "--floor", "$Floor", "--realm", $Realm, "--capacity", "$Capacity", "--server-name", $Name)
if ($Report) { $argv += "--report" }

New-Item -ItemType Directory -Force -Path (Join-Path $DataDir "logs") | Out-Null
# Godot puts user:// under %APPDATA%\Godot\app_userdata\<project>; point it at
# the data folder for this process (and the server it starts) only.
$oldAppData = $env:APPDATA
$env:APPDATA = $DataDir

Write-Host "The Spire dedicated server '$Name'  floor $Floor  udp $Port  capacity $Capacity"
Write-Host "  binary : $Godot"
Write-Host "  data   : $DataDir"
Write-Host "  Allow UDP $Port in Windows Firewall for players outside this PC (see docs\DEDICATED_SERVER.md)."

$delay = 5
# Godot writes warnings to stderr; in Windows PowerShell those must not stop the script.
$ErrorActionPreference = "Continue"
try {
while ($true) {
	# Keep two weeks of console logs.
	Get-ChildItem (Join-Path $DataDir "logs") -Filter "server-*.log" -ErrorAction SilentlyContinue |
		Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } | Remove-Item -Force -ErrorAction SilentlyContinue
	$log = Join-Path $DataDir ("logs\server-{0}-{1}.log" -f $Port, (Get-Date -Format "yyyyMMdd-HHmmss"))
	Write-Host "[run_server] $(Get-Date -Format s) starting; log $log"
	$started = Get-Date
	# 2>&1 turns Godot's stderr lines into records; "$_" prints them as text.
	& $Godot @argv 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log -Append
	$code = $LASTEXITCODE
	$ran = ((Get-Date) - $started).TotalSeconds
	Write-Host "[run_server] $(Get-Date -Format s) server exited with code $code after $([int]$ran) s"
	if ($NoRestart) { exit $code }
	# 5 s after a healthy run; back off (10, 20 .. 60 s) while it crash-loops.
	if ($ran -ge 60) { $delay = 5 }
	Write-Host "[run_server] restarting in $delay s (Ctrl+C to stop)"
	Start-Sleep -Seconds $delay
	if ($ran -lt 60) { $delay = [Math]::Min($delay * 2, 60) }
}
} finally {
	$env:APPDATA = $oldAppData  # when dot-sourced / run inside an open shell
}
