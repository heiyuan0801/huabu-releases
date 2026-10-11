#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
toolchain_env="${HUABU_TOOLCHAIN_ENV:-/Volumes/mac/developer/huabu-flutter-env.sh}"
if [[ -f "$toolchain_env" ]]; then source "$toolchain_env"; fi

platform="${1:-}"
if [[ "$platform" != macos && "$platform" != android && "$platform" != ios ]]; then
  echo '用法: scripts/package-release.sh macos|android|ios [--package-only] [Flutter build 参数]'
  exit 2
fi
shift
package_only=false
if [[ "${1:-}" == --package-only ]]; then package_only=true; shift; fi
version="$(awk '/^version:/ { print $2; exit }' pubspec.yaml)"
output_dir="$project_dir/build/packages/$version/$platform"
mkdir -p "$output_dir"

case "$platform" in
  macos)
    if [[ "$(uname -s)" != Darwin ]]; then echo 'macOS 包必须在 Mac 上构建。'; exit 1; fi
    if [[ "$package_only" == false ]]; then flutter build macos --release "$@"; fi
    app_path="$project_dir/build/macos/Build/Products/Release/未来画布.app"
    if [[ ! -d "$app_path" ]]; then echo '未找到 Release app，请先构建。'; exit 1; fi
    zip_path="$output_dir/huabu-$version-macos.zip"
    dmg_path="$output_dir/huabu-$version-macos.dmg"
    stage_dir="$(mktemp -d "$output_dir/dmg-stage.XXXXXX")"
    trap 'rm -rf "$stage_dir"' EXIT
    ditto "$app_path" "$stage_dir/未来画布.app"
    ln -s /Applications "$stage_dir/Applications"
    ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
    hdiutil create -volname '未来画布' -srcfolder "$stage_dir" -format UDZO -ov "$dmg_path"
    printf '%s\n' 'macOS Release 包；脚本不执行 Developer ID 签名、公证或更新签名。' > "$output_dir/BUILD-NOTES.txt"
    ;;
  android)
    if [[ "$package_only" == false ]]; then
      flutter build apk --release --split-per-abi -P force-version-code-ignoring-abi=true "$@"
      flutter build apk --release "$@"
      flutter build appbundle --release "$@"
    fi
    apk_dir="$project_dir/build/app/outputs/flutter-apk"
    for abi in armeabi-v7a arm64-v8a x86_64; do
      source_apk="$apk_dir/app-$abi-release.apk"
      if [[ ! -f "$source_apk" ]]; then echo "未找到 $source_apk"; exit 1; fi
      cp "$source_apk" "$output_dir/huabu-$version-android-$abi.apk"
    done
    cp "$apk_dir/app-release.apk" "$output_dir/huabu-$version-android-universal.apk"
    cp "$project_dir/build/app/outputs/bundle/release/app-release.aab" "$output_dir/huabu-$version-android.aab"
    printf '%s\n' 'Release APK/AAB 使用 HUABU_ANDROID_KEY_PROPERTIES 指定的正式签名；发布前核对真实版本和签名。universal APK 为统一安装入口，split APK 按 ABI 选择，AAB 用于应用市场。' > "$output_dir/BUILD-NOTES.txt"
    ;;
  ios)
    if [[ "$(uname -s)" != Darwin ]]; then echo 'iOS 包必须在 Mac 上构建。'; exit 1; fi
    if [[ "$package_only" == false ]]; then flutter build ipa --release --no-codesign "$@"; fi
    archive_path="$project_dir/build/ios/archive/Runner.xcarchive"
    if [[ ! -d "$archive_path" ]]; then echo '未找到 iOS xcarchive，请先构建。'; exit 1; fi
    ditto -c -k --sequesterRsrc --keepParent "$archive_path" "$output_dir/huabu-$version-ios-unsigned.xcarchive.zip"
    printf '%s\n' '这是未签名 Release xcarchive，供开发者在 Xcode 中签名导出；不是可安装的 IPA。' > "$output_dir/BUILD-NOTES.txt"
    ;;
esac

cd "$output_dir"
shopt -s nullglob
artifacts=(./*.zip ./*.dmg ./*.apk ./*.aab)
shasum -a 256 "${artifacts[@]}" > SHA256SUMS.txt
echo "资源包位置: $output_dir"
