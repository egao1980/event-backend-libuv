# Build shared libuv into lib/windows-amd64/ with MSVC (VsDevCmd + NMake).
# Do not use MinGW here — MinGW gcc is only for cffi-grovel against the same headers.
# Env: LIBUV_VERSION (default 1.51.0)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Version = if ($env:LIBUV_VERSION) { $env:LIBUV_VERSION } else { "1.51.0" }
$Out = Join-Path $Root "lib\windows-amd64"
$Build = Join-Path $Root "build\libuv-$Version-windows-amd64"
$Tgz = Join-Path $Root "build\libuv-$Version.tar.gz"
$Url = "https://github.com/libuv/libuv/archive/refs/tags/v$Version.tar.gz"

New-Item -ItemType Directory -Force -Path (Join-Path $Root "build") | Out-Null
if (-not (Test-Path $Tgz)) {
  Write-Host "==> download $Url"
  Invoke-WebRequest -Uri $Url -OutFile $Tgz
}

if (Test-Path $Build) { Remove-Item -Recurse -Force $Build }
New-Item -ItemType Directory -Force -Path $Build | Out-Null
tar -xzf $Tgz -C $Build --strip-components=1

# Enter VS x64 env (cl/nmake/link). windows-latest already has Build Tools.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = $null
if (Test-Path $vswhere) {
  $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
}
if (-not $vsPath) {
  throw "Visual Studio with VC tools not found (vswhere)"
}
$devCmd = Join-Path $vsPath "Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path $devCmd)) {
  throw "VsDevCmd.bat not found under $vsPath"
}
Write-Host "==> enter VS x64 env via VsDevCmd.bat ($vsPath)"
cmd /c "`"$devCmd`" -arch=amd64 -host_arch=amd64 && set" | ForEach-Object {
  if ($_ -match '^(.*?)=(.*)$') {
    Set-Item -Path "env:$($matches[1])" -Value $matches[2]
  }
}

# Prefer cmake already on PATH / shipped with VS — do not require Chocolatey.
$cmake = $null
if (Get-Command cmake -ErrorAction SilentlyContinue) {
  $cmake = (Get-Command cmake).Source
} else {
  $vsCmake = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  if (Test-Path $vsCmake) { $cmake = $vsCmake }
}
if (-not $cmake) {
  throw "cmake not found (install VS C++ CMake tools, or put cmake on PATH)"
}
Write-Host "==> using cmake: $cmake"

if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
  throw "cl.exe not on PATH after VsDevCmd"
}
if (-not (Get-Command nmake -ErrorAction SilentlyContinue)) {
  throw "nmake not on PATH after VsDevCmd"
}

$Prefix = Join-Path $Build "prefix"
$CmakeBuild = Join-Path $Build "build"
Write-Host "==> MSVC/NMake build libuv $Version -> $Out"
# NMake uses the active cl.exe — avoids "Visual Studio 17 2022 could not find any instance".
& $cmake -S $Build -B $CmakeBuild `
  -G "NMake Makefiles" `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_INSTALL_PREFIX=$Prefix `
  -DLIBUV_BUILD_SHARED=ON `
  -DLIBUV_BUILD_TESTS=OFF
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
& $cmake --build $CmakeBuild
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }
& $cmake --install $CmakeBuild
if ($LASTEXITCODE -ne 0) { throw "cmake install failed" }

if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force -Path $Out | Out-Null
Get-ChildItem -Path (Join-Path $Prefix "bin") -Filter "uv.dll" -ErrorAction SilentlyContinue |
  ForEach-Object { Copy-Item $_.FullName (Join-Path $Out "libuv.dll") }
Get-ChildItem -Path (Join-Path $Prefix "lib") -Filter "*.dll" -ErrorAction SilentlyContinue |
  ForEach-Object { Copy-Item $_.FullName $Out -Force }
if (-not (Test-Path (Join-Path $Out "libuv.dll"))) {
  $cand = Get-ChildItem -Path $Prefix -Recurse -Filter "*uv*.dll" | Select-Object -First 1
  if ($cand) { Copy-Item $cand.FullName (Join-Path $Out "libuv.dll") }
}
if (-not (Test-Path (Join-Path $Out "libuv.dll"))) {
  throw "libuv.dll not found under $Prefix"
}

$inc = Join-Path $Prefix "include"
if (-not (Test-Path (Join-Path $inc "uv.h"))) {
  throw "uv.h not found at $inc"
}
$env:EVENT_PROTOCOL_UV_INCLUDE = $inc
Write-Host "EVENT_PROTOCOL_UV_INCLUDE=$($env:EVENT_PROTOCOL_UV_INCLUDE)"
Get-ChildItem $Out
