<#
固定依赖与工具链，先运行宿主 Go 测试，再交叉编译并同步 ARM64 c-shared 产物。
仅在当前进程临时设置编译环境，结束时恢复调用方原有环境变量。
#>
param(
  [string]$SdkRoot = $env:DEVECO_SDK_HOME
)

$ErrorActionPreference = 'Stop'

$versionFile = Join-Path $PSScriptRoot 'VERSION'
$versionValues = @{}
foreach ($line in Get-Content -LiteralPath $versionFile) {
  $parts = $line.Split('=', 2)
  if ($parts.Length -eq 2) {
    $versionValues[$parts[0]] = $parts[1]
  }
}

# 同时约束版本、源码提交和校验和，防止同名依赖或本地配置漂移。
$requiredVersionValues = @{
  go = 'go1.27.0'
  go_tls_patch = '97ce7c6ef39edf2a0a0eba7d6fd1075abf26dc2f'
  go_tls_patch_sha256 = 'F23053EDA062FDDE8EA6BEB767A404C3B353A46E787D2FE12B83DE1396B1D255'
  mihomo_module = 'github.com/chen08209/Clash.Meta'
  mihomo_version = 'v1.11.9-0.20261012003553-8380d0e7462f'
  mihomo_commit = '8380d0e7462f061a964323e9bf3129a236fcc5d5'
  mihomo_sum = 'h1:JsFapruRNTb7Z1yc5BQu+IMLZuHu8FZI7r8ei8pJq/U='
  harmony_api = '24'
}

foreach ($key in $requiredVersionValues.Keys) {
  if ($versionValues[$key] -ne $requiredVersionValues[$key]) {
    throw "VERSION mismatch for ${key}: expected $($requiredVersionValues[$key]), got $($versionValues[$key])"
  }
}

$toolchainScript = Join-Path $PSScriptRoot 'build-go-toolchain.ps1'
& $toolchainScript
$go = Join-Path $PSScriptRoot '.toolchains\go1.27.0-tlsgd\bin\go.exe'
$actualGoVersion = (& $go env GOVERSION).Trim()
if ($LASTEXITCODE -ne 0 -or $actualGoVersion -ne $requiredVersionValues['go']) {
  throw "Go version mismatch: expected $($requiredVersionValues['go']), got $actualGoVersion"
}

if ([string]::IsNullOrWhiteSpace($SdkRoot)) {
  throw 'DEVECO_SDK_HOME is empty. Pass -SdkRoot or set the environment variable.'
}

# 用无空格的本地联接路径传递给 CGO，避免 SDK 安装路径被拆成多个参数。
$nativeTarget = Join-Path $SdkRoot 'default\openharmony\native'
$nativeRoot = Join-Path $PSScriptRoot '.ohos-native'
if (-not (Test-Path -LiteralPath $nativeRoot)) {
  New-Item -ItemType Junction -Path $nativeRoot -Target $nativeTarget | Out-Null
}

$llvmBin = Join-Path $nativeRoot 'llvm\bin'
$clang = Join-Path $llvmBin 'clang.exe'
$sysroot = Join-Path $nativeRoot 'sysroot'
$outputDirectory = Join-Path $PSScriptRoot 'out\arm64-v8a'
$goCache = Join-Path $PSScriptRoot '.gocache-tlsgd'
$goModCache = Join-Path $PSScriptRoot '.gomodcache'

if (-not (Test-Path -LiteralPath $clang)) {
  throw "OHOS clang not found: $clang"
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $goCache | Out-Null
New-Item -ItemType Directory -Force -Path $goModCache | Out-Null

$previous = @{
  GOOS = $env:GOOS
  GOARCH = $env:GOARCH
  CGO_ENABLED = $env:CGO_ENABLED
  CC = $env:CC
  CGO_CFLAGS = $env:CGO_CFLAGS
  CGO_LDFLAGS = $env:CGO_LDFLAGS
  GOCACHE = $env:GOCACHE
  GOMODCACHE = $env:GOMODCACHE
  PATH = $env:PATH
}

try {
  $env:GOCACHE = $goCache
  $env:GOMODCACHE = $goModCache
  $env:CGO_ENABLED = '0'
  Push-Location $PSScriptRoot
  try {
    $moduleInfo = (& $go mod download -json "$($requiredVersionValues['mihomo_module'])@$($requiredVersionValues['mihomo_version'])" | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $moduleInfo.Path -ne $requiredVersionValues['mihomo_module'] -or
      $moduleInfo.Version -ne $requiredVersionValues['mihomo_version'] -or
      $moduleInfo.Sum -ne $requiredVersionValues['mihomo_sum'] -or
      $moduleInfo.Origin.Hash -ne $requiredVersionValues['mihomo_commit']) {
      throw 'Pinned Clash.Meta module source, version, checksum or commit does not match VERSION.'
    }
    $moduleSelection = (& $go list -m -json github.com/metacubex/mihomo | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $moduleSelection.Replace.Path -ne $requiredVersionValues['mihomo_module'] -or
      $moduleSelection.Replace.Version -ne $requiredVersionValues['mihomo_version'] -or
      $moduleSelection.Replace.Sum -ne $requiredVersionValues['mihomo_sum']) {
      throw 'Pinned Mihomo dependency does not select the Clash.Meta module from VERSION.'
    }
    & $go test .
    if ($LASTEXITCODE -ne 0) {
      throw "Go host tests failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  $env:GOOS = 'linux'
  $env:GOARCH = 'arm64'
  $env:CGO_ENABLED = '1'
  $env:PATH = "$llvmBin;$env:PATH"
  $env:CC = "$clang --target=aarch64-linux-ohos --sysroot=$sysroot -D__MUSL__"
  $env:CGO_CFLAGS = ''
  $env:CGO_LDFLAGS = ''
  Push-Location $PSScriptRoot
  try {
    & $go build -trimpath -buildmode=c-shared `
      -ldflags '-extldflags=-Wl,-soname,libnlash_core.so' `
      -o (Join-Path $outputDirectory 'libnlash_core.so') .
    if ($LASTEXITCODE -ne 0) {
      throw "Go c-shared build failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  $prebuiltDirectory = Join-Path $PSScriptRoot '..\proxy_core\src\main\cpp\prebuilt\arm64-v8a'
  New-Item -ItemType Directory -Force -Path $prebuiltDirectory | Out-Null
  Copy-Item -Force (Join-Path $outputDirectory 'libnlash_core.so') $prebuiltDirectory
  Copy-Item -Force (Join-Path $outputDirectory 'libnlash_core.h') $prebuiltDirectory

  # N-API 通过 dlopen 加载 Go 库，必须使用 musl 支持的动态 TLS 重定位。
  $readelf = Join-Path $llvmBin 'llvm-readelf.exe'
  $coreLibrary = Join-Path $outputDirectory 'libnlash_core.so'
  $relocations = (& $readelf -rW $coreLibrary | Out-String)
  if (-not $relocations.Contains('R_AARCH64_TLSDESC') -or $relocations.Contains('R_AARCH64_TLS_TPREL')) {
    throw 'Go c-shared TLS model validation failed: expected TLSDESC and no TPREL relocation.'
  }
} finally {
  foreach ($key in $previous.Keys) {
    Set-Item -Path "Env:$key" -Value $previous[$key]
  }
}
