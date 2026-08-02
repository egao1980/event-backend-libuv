# Build shared libuv into lib/windows-amd64/ with MSVC + CMake (not MinGW).
# Headers under build/.../prefix/include are what cffi-grovel needs; MinGW gcc may
# grovel against those same headers later — ABI of uv.dll is still MSVC.
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

# Prefer VS developer environment (same pattern as cl-stack-ssl).
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
  $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
  if ($vsPath) {
    $devCmd = Join-Path $vsPath "Common7\Tools\VsDevCmd.bat"
    if (Test-Path $devCmd) {
      Write-Host "==> enter VS x64 env via VsDevCmd.bat"
      cmd /c "`"$devCmd`" -arch=amd64 -host_arch=amd64 && set" | ForEach-Object {
        if ($_ -match '^(.*?)=(.*)$') {
          Set-Item -Path "env:$($matches[1])" -Value $matches[2]
        }
      }
    }
  }
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
  throw "cmake not found"
}
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
  throw "cl.exe not found (install VS Build Tools with C++ workload)"
}

$Prefix = Join-Path $Build "prefix"
$CmakeBuild = Join-Path $Build "build"
Write-Host "==> cmake/MSVC build libuv $Version -> $Out"
# Pin VS generator so MinGW on PATH cannot steal the build.
cmake -S $Build -B $CmakeBuild `
  -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_INSTALL_PREFIX=$Prefix `
  -DLIBUV_BUILD_SHARED=ON `
  -DLIBUV_BUILD_TESTS=OFF
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
cmake --build $CmakeBuild --config Release
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }
cmake --install $CmakeBuild --config Release
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
