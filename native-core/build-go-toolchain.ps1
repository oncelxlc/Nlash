<#
复制固定版本的 Go 并应用 ARM64 musl TLS 补丁，不修改系统安装的 Go。
已有完整工具链可直接复用；遇到不完整目录时停止，避免混用不同构建产物。
#>
param(
  [string]$OutputRoot = (Join-Path $PSScriptRoot '.toolchains\go1.27.0-tlsgd')
)

$ErrorActionPreference = 'Stop'

$requiredGoVersion = 'go1.27.0'
$requiredPatchHash = 'F23053EDA062FDDE8EA6BEB767A404C3B353A46E787D2FE12B83DE1396B1D255'
$patchPath = Join-Path $PSScriptRoot 'toolchain-patches\go1.27-musl-arm64-tlsgd.patch'
$patchedGo = Join-Path $OutputRoot 'bin\go.exe'

if (Test-Path -LiteralPath $patchedGo) {
  $actualVersion = (& $patchedGo env GOVERSION).Trim()
  $asmHelp = (& (Join-Path $OutputRoot 'pkg\tool\windows_amd64\asm.exe') -h 2>&1 | Out-String)
  if ($actualVersion -eq $requiredGoVersion -and $asmHelp.Contains('TLS model for thread-local storage')) {
    return
  }
  throw "Existing patched Go toolchain is invalid: $OutputRoot"
}

if (Test-Path -LiteralPath $OutputRoot) {
  throw "Incomplete patched Go toolchain directory exists: $OutputRoot"
}

if (-not (Test-Path -LiteralPath $patchPath)) {
  throw "Go TLS patch is missing: $patchPath"
}

$actualPatchHash = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash
if ($actualPatchHash -ne $requiredPatchHash) {
  throw "Go TLS patch checksum mismatch: expected $requiredPatchHash, got $actualPatchHash"
}

$bootstrapGo = (Get-Command go -ErrorAction Stop).Source
$bootstrapVersion = (& $bootstrapGo env GOVERSION).Trim()
if ($bootstrapVersion -ne $requiredGoVersion) {
  throw "Bootstrap Go version mismatch: expected $requiredGoVersion, got $bootstrapVersion"
}

$bootstrapRoot = (& $bootstrapGo env GOROOT).Trim()
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
Copy-Item -Path (Join-Path $bootstrapRoot '*') -Destination $OutputRoot -Recurse -Force

Push-Location $OutputRoot
try {
  & git apply --check --ignore-space-change --ignore-whitespace $patchPath
  if ($LASTEXITCODE -ne 0) {
    throw 'Go TLS patch does not apply cleanly to the pinned Go 1.27.0 source.'
  }

  & git apply --ignore-space-change --ignore-whitespace $patchPath
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to apply the Go TLS patch.'
  }

  $previousBootstrap = $env:GOROOT_BOOTSTRAP
  try {
    $env:GOROOT_BOOTSTRAP = $bootstrapRoot
    Push-Location (Join-Path $OutputRoot 'src')
    try {
      & '.\make.bat'
      if ($LASTEXITCODE -ne 0) {
        throw "Patched Go toolchain build failed with exit code $LASTEXITCODE"
      }
    } finally {
      Pop-Location
    }
  } finally {
    $env:GOROOT_BOOTSTRAP = $previousBootstrap
  }
} finally {
  Pop-Location
}

$builtVersion = (& $patchedGo env GOVERSION).Trim()
$builtAsmHelp = (& (Join-Path $OutputRoot 'pkg\tool\windows_amd64\asm.exe') -h 2>&1 | Out-String)
if ($builtVersion -ne $requiredGoVersion -or -not $builtAsmHelp.Contains('TLS model for thread-local storage')) {
  throw 'Patched Go toolchain validation failed.'
}
