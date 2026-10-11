#!/usr/bin/env python3
"""Prepare local GitHub release metadata; never upload or export private keys."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from urllib.parse import quote, unquote, urlparse
import xml.etree.ElementTree as ET
import zipfile

PROJECT = Path(__file__).resolve().parent.parent
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def run(*args):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True, text=True).stdout.strip()


def github_download_base(value):
    uri = urlparse(value)
    parts = uri.path.strip('/').split('/')
    if (uri.scheme != 'https' or uri.netloc != 'github.com' or uri.query or uri.fragment
            or len(parts) < 5 or parts[2:4] != ['releases', 'tag']):
        raise ValueError('请提供 HTTPS GitHub Releases tag 地址')
    tag = unquote('/'.join(parts[4:]))
    return f'https://github.com/{parts[0]}/{parts[1]}/releases/download/{quote(tag, safe="")}/'


def one(files, name):
    found = [file for file in files if file.name == name]
    if len(found) > 1:
        raise ValueError(f'存在多个同名资源包，请保留明确版本的唯一文件：{name}')
    return found[0] if found else None


def appcast(path, platform, version, build, notes, release_url, download_url, package, signature):
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = '未来画布'
    ET.SubElement(channel, 'link').text = release_url
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'未来画布 {version}'
    ET.SubElement(item, 'description', {f'{{{SPARKLE}}}format': 'plain-text'}).text = notes
    attributes = {'url': download_url, 'length': str(package.stat().st_size), 'type': 'application/octet-stream', f'{{{SPARKLE}}}os': platform}
    if platform == 'macos':
        ET.SubElement(item, f'{{{SPARKLE}}}version').text = str(build)
        ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
        attributes[f'{{{SPARKLE}}}edSignature'] = signature
    else:
        attributes[f'{{{SPARKLE}}}version'] = f'{version}+{build}'
        attributes[f'{{{SPARKLE}}}dsaSignature'] = signature
    ET.SubElement(item, 'enclosure', attributes)
    ET.indent(rss)
    ET.ElementTree(rss).write(path, encoding='utf-8', xml_declaration=True)


def sign_mac(package, tool, account, version, build):
    with zipfile.ZipFile(package, metadata_encoding='utf-8') as archive:
        info = plistlib.loads(archive.read('未来画布.app/Contents/Info.plist'))
    if info.get('CFBundleShortVersionString') != version or str(info.get('CFBundleVersion')) != str(build):
        raise ValueError('macOS ZIP 内实际版本与 pubspec.yaml 不一致，请重新打包')
    public_key = run(tool.parent / 'generate_keys', '--account', account, '-p')
    if not public_key or info.get('SUPublicEDKey') != public_key:
        raise ValueError('macOS ZIP 的 Sparkle 公钥与所选钥匙串账号不一致')
    fragment = run(tool, '--account', account, package)
    enclosure = ET.fromstring(f'<enclosure xmlns:sparkle="{SPARKLE}" {fragment} />')
    signature = enclosure.get(f'{{{SPARKLE}}}edSignature', '')
    if len(base64.b64decode(signature, validate=True)) != 64 or enclosure.get('length') != str(package.stat().st_size):
        raise ValueError('Sparkle 签名工具未返回有效签名与真实长度')
    run(tool, '--verify', '--account', account, package, signature)
    return signature


def verify_windows(package, signature_file, public_key, output):
    signature = ''.join(signature_file.read_text(encoding='utf-8-sig').split())
    raw_signature = base64.b64decode(signature, validate=True)
    key_text = public_key.read_text(encoding='utf-8-sig')
    if '-----BEGIN PUBLIC KEY-----' not in key_text or 'PRIVATE KEY' in key_text:
        raise ValueError('Windows 更新验证需要 DSA 公钥 PEM，不读取私钥')
    # Match WinSparkle 0.8.1's official sign_update.bat: sign SHA1(file)'s bytes.
    with tempfile.TemporaryDirectory(dir=output) as temp:
        digest_file, signature_path = Path(temp) / 'digest.bin', Path(temp) / 'signature.bin'
        with package.open('rb') as stream:
            digest_file.write_bytes(hashlib.file_digest(stream, 'sha1').digest())
        signature_path.write_bytes(raw_signature)
        run('openssl', 'dgst', '-sha1', '-verify', public_key, '-signature', signature_path, digest_file)
    return signature


def production_apk(package):
    sdk = os.environ.get('ANDROID_HOME', os.environ.get('ANDROID_SDK_ROOT', ''))
    tool = Path(sdk) / 'build-tools/36.0.0/apksigner' if sdk else None
    executable = str(tool) if tool and tool.is_file() else shutil.which('apksigner')
    if not executable:
        raise ValueError('发布 Android APK 前需要 apksigner 验证实际签名')
    details = run(executable, 'verify', '--print-certs', package)
    return 'cn=android debug' not in details.lower()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-url', required=True, help='Actual GitHub releases/tag URL to prepare')
    parser.add_argument('--packages-dir', type=Path)
    parser.add_argument('--notes-file', type=Path)
    parser.add_argument('--sign-update', type=Path, help='Sparkle sign_update tool; omit to leave Mac appcast unavailable')
    parser.add_argument('--macos-account', default='chat.weilai.huabuApp.updates')
    parser.add_argument('--windows-installer', type=Path)
    parser.add_argument('--windows-signature-file', type=Path, help='Base64 output from official WinSparkle sign_update.bat')
    parser.add_argument('--windows-public-key', type=Path)
    parser.add_argument('--android-apk', type=Path, help='Explicit production-signed installable APK, never AAB/debug APK')
    args = parser.parse_args()
    full_version = next(line.split(':', 1)[1].strip() for line in (PROJECT / 'pubspec.yaml').read_text().splitlines() if line.startswith('version:'))
    version, build = full_version.split('+')
    build = int(build)
    if build < 1:
        raise ValueError('buildNumber 必须为正整数')
    packages = (args.packages_dir or PROJECT / 'build/packages' / full_version).resolve()
    if not packages.is_dir():
        raise ValueError('没有已构建的版本资源包目录')
    output = packages / 'release'
    output.mkdir(exist_ok=True)
    files = sorted(file for file in packages.rglob('*') if file.is_file() and file.suffix in ('.zip', '.dmg', '.apk', '.aab', '.exe') and output not in file.parents)
    base = github_download_base(args.release_url)
    url = lambda file: base + quote(file.name, safe='')
    notes = args.notes_file.read_text(encoding='utf-8-sig') if args.notes_file else ''
    manifest = {'schemaVersion': 1, 'version': version, 'buildNumber': build, 'notes': notes, 'downloads': {}, 'appcasts': {}}
    if (args.windows_signature_file or args.windows_public_key) and not args.windows_installer:
        raise ValueError('生成 Windows feed 必须明确选择实际安装器')
    mac_zip = one(files, f'huabu-{full_version}-macos.zip')
    mac_download = one(files, f'huabu-{full_version}-macos.dmg') or mac_zip
    if mac_download:
        manifest['downloads']['macos'] = url(mac_download)
    if args.sign_update:
        if not mac_zip:
            raise ValueError('生成 Mac appcast 需要实际存在的 macOS ZIP')
        signature = sign_mac(mac_zip, args.sign_update.resolve(), args.macos_account, version, build)
        appcast(output / 'appcast-macos.xml', 'macos', version, build, notes, args.release_url, url(mac_zip), mac_zip, signature)
        manifest['appcasts']['macos'] = base + 'appcast-macos.xml'
    if args.windows_installer:
        installer = args.windows_installer.resolve()
        if installer not in files or not installer.name.startswith(f'huabu-{full_version}-windows-') or not installer.name.endswith('-setup.exe'):
            raise ValueError('Windows 下载必须选 packages 目录内实际安装器 EXE')
        manifest['downloads']['windows'] = url(installer)
        if args.windows_signature_file or args.windows_public_key:
            if not args.windows_signature_file or not args.windows_public_key:
                raise ValueError('Windows feed 需要真实 DSA 签名与对应公钥')
            signature = verify_windows(installer, args.windows_signature_file, args.windows_public_key, output)
            appcast(output / 'appcast-windows.xml', 'windows', version, build, notes, args.release_url, url(installer), installer, signature)
            manifest['appcasts']['windows'] = base + 'appcast-windows.xml'
    if args.android_apk:
        apk = args.android_apk.resolve()
        if apk not in files or not apk.name.startswith(f'huabu-{full_version}-android-') or apk.suffix != '.apk':
            raise ValueError('Android 下载必须选 packages 目录内实际 APK')
        if not production_apk(apk):
            raise ValueError('Android debug 签名 APK 只能测试，不能进入正式下载清单')
        manifest['downloads']['android'] = url(apk)
    inventory = []
    for file in files:
        with file.open('rb') as stream:
            sha256 = hashlib.file_digest(stream, 'sha256').hexdigest()
        if '-ios-unsigned.xcarchive.zip' in file.name:
            use = 'unsigned-ios-archive-not-installable'
        elif file.suffix == '.aab':
            use = 'android-app-bundle-not-direct-install'
        elif file.suffix == '.apk':
            if manifest['downloads'].get('android'):
                use = 'production-signed-android-apk' if production_apk(file) else 'debug-signed-android-apk-not-publishable'
            else:
                use = 'android-unapproved-signing-not-published'
        else:
            use = 'local-release-artifact-not-uploaded'
        inventory.append({'file': str(file.relative_to(packages)), 'length': file.stat().st_size, 'sha256': sha256, 'status': use})
    (output / 'flutter-release.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (output / 'release-artifacts.json').write_text(json.dumps(inventory, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'已准备本地发布资料：{output}；尚未上传 GitHub。')


if __name__ == '__main__':
    main()
