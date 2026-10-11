param(
  [ValidateSet('x64', 'arm64')][string]$Arch = 'x64',
  [switch]$PackageOnly,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs = @()
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -and $env:OS -ne 'Windows_NT') { throw 'Windows 包必须在 Windows 主机上构建。' }
$ProjectDir = Split-Path $PSScriptRoot -Parent
Push-Location $ProjectDir
try {
  $VersionLine = Get-Content pubspec.yaml | Where-Object { $_ -match '^version:\s*(\S+)' } | Select-Object -First 1
  $Version = ($VersionLine -replace '^version:\s*', '').Trim()
  $OutputDir = Join-Path $ProjectDir "build/packages/$Version/windows-$Arch"
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
  if (-not $PackageOnly) {
    $HostArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    if ($HostArch -ne $Arch) { throw "Flutter Windows 按主机架构构建；当前主机为 $HostArch，不能生成 $Arch 包。" }
    if ($env:WS_DSA_PUBLIC_KEY) {
      $PublicKey = Get-Content $env:WS_DSA_PUBLIC_KEY -Raw
      if ($PublicKey -notmatch '-----BEGIN PUBLIC KEY-----' -or $PublicKey -match 'PRIVATE KEY') { throw 'WS_DSA_PUBLIC_KEY 必须指向更新公钥 PEM，不得使用私钥。' }
      $ResourceKey = Join-Path $ProjectDir 'windows/runner/resources/update_dsa_pub.pem'
      if ((Resolve-Path $env:WS_DSA_PUBLIC_KEY).Path -ne $ResourceKey) { Copy-Item $env:WS_DSA_PUBLIC_KEY $ResourceKey -Force }
    }
    & flutter build windows --release @FlutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows 构建失败。' }
  }
  $BundleDir = Join-Path $ProjectDir "build/windows/$Arch/runner/Release"
  if (-not (Test-Path "$BundleDir/huabu_app.exe")) { throw "未找到 Windows Release bundle: $BundleDir" }
  $ZipPath = Join-Path $OutputDir "huabu-$Version-windows-$Arch.zip"
  Compress-Archive -Path "$BundleDir/*" -DestinationPath $ZipPath -Force
  $Iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  $IsccPath = if ($Iscc) { $Iscc.Source } else { $null }
  if (-not $IsccPath) {
    $KnownIscc = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
    if (Test-Path $KnownIscc) { $IsccPath = $KnownIscc }
  }
  if ($IsccPath) {
    & $IsccPath "/DAppVersion=$Version" "/DAppArch=$Arch" "/DBundleDir=$BundleDir" "/DOutputDir=$OutputDir" "$PSScriptRoot/windows-installer.iss"
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup 安装器生成失败。' }
  } else {
    Write-Warning '已生成便携 ZIP；未找到 Inno Setup，尚未生成可供 WinSparkle 自动更新的安装器。'
  }
  'Windows Release 包；脚本不执行 Authenticode 或 WinSparkle 更新签名。ZIP 必须整目录解压运行。' | Set-Content "$OutputDir/BUILD-NOTES.txt" -Encoding utf8
  Get-ChildItem $OutputDir -File | Where-Object { $_.Extension -in '.zip', '.exe' } | ForEach-Object {
    $Hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$Hash  $($_.Name)"
  } | Set-Content "$OutputDir/SHA256SUMS.txt" -Encoding ascii
  Write-Output "资源包位置: $OutputDir"
} finally { Pop-Location }
