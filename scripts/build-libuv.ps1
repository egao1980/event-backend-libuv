# Build shared libuv into lib/windows-amd64/ on Windows (MSVC + cmake).
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

$Prefix = Join-Path $Build "prefix"
Write-Host "==> cmake/build libuv $Version -> $Out"
cmake -S $Build -B (Join-Path $Build "build") `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_INSTALL_PREFIX=$Prefix `
  -DLIBUV_BUILD_SHARED=ON `
  -DLIBUV_BUILD_TESTS=OFF
cmake --build (Join-Path $Build "build") --config Release
cmake --install (Join-Path $Build "build") --config Release

if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force -Path $Out | Out-Null
Get-ChildItem -Path (Join-Path $Prefix "bin") -Filter "uv.dll" -ErrorAction SilentlyContinue |
  ForEach-Object { Copy-Item $_.FullName (Join-Path $Out "libuv.dll") }
Get-ChildItem -Path (Join-Path $Prefix "lib") -Filter "*.dll" -ErrorAction SilentlyContinue |
  ForEach-Object { Copy-Item $_.FullName $Out -Force }
# Some installs name it uv.dll
if (-not (Test-Path (Join-Path $Out "libuv.dll"))) {
  $cand = Get-ChildItem -Path $Prefix -Recurse -Filter "*uv*.dll" | Select-Object -First 1
  if ($cand) { Copy-Item $cand.FullName (Join-Path $Out "libuv.dll") }
}
$env:EVENT_PROTOCOL_UV_INCLUDE = Join-Path $Prefix "include"
Write-Host "EVENT_PROTOCOL_UV_INCLUDE=$($env:EVENT_PROTOCOL_UV_INCLUDE)"
Get-ChildItem $Out
