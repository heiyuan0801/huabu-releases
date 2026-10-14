#!/usr/bin/env python3
"""Verify a public Huabu release and atomically activate its local mirror."""
import argparse
import base64
import fcntl
import hashlib
import html
import io
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import dsa, ed25519
from defusedxml import ElementTree as SafeET
from packaging.version import Version

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)
METADATA = {'flutter-release.json', 'appcast-macos.xml', 'appcast-windows.xml', 'SHA256SUMS'}


class MirrorError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise MirrorError(message)


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()


def digest(path, algorithm='sha256'):
    result = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.digest()


def fetch(address, destination=None):
    # No account credentials, retry policy, or additional network timeout.
    request = Request(address, headers={'User-Agent': 'Huabu-release-mirror', 'Accept': 'application/vnd.github+json'})
    try:
        with urlopen(request) as response:
            if destination is None:
                return response.read()
            with destination.open('wb') as output:
                shutil.copyfileobj(response, output)
    except HTTPError as error:
        raise MirrorError(f'GitHub 请求失败（HTTP {error.code}），保留当前版本') from None
    except URLError:
        raise MirrorError('GitHub 网络请求失败，保留当前版本') from None


def release_record(value, repository, selected_tag):
    require(isinstance(value, dict), 'GitHub 发行资料格式错误')
    tag = value.get('tag_name', '')
    require(isinstance(tag, str) and re.fullmatch(r'client-v\d+\.\d+\.\d+', tag), '只同步正式 client-v 版本')
    require(selected_tag is None or selected_tag == tag, '指定 tag 与来源不一致')
    require(value.get('draft') is False and value.get('prerelease') is False, '不镜像草稿或预发行版')
    release_url = f'https://github.com/{repository}/releases/tag/{tag}'
    require(value.get('html_url') == release_url, '发行来源与指定仓库不一致')
    assets = value.get('assets')
    require(isinstance(assets, list) and len(assets) == 14, '正式发行必须包含完整 14 项资源')
    normalized = []
    for asset in assets:
        require(isinstance(asset, dict), 'GitHub 资源资料格式错误')
        name, checksum, size = asset.get('name'), asset.get('digest'), asset.get('size')
        require(isinstance(name, str) and name not in ('.', '..') and re.fullmatch(r'[A-Za-z0-9+._-]+', name), 'GitHub 资源文件名无效')
        require(asset.get('state') == 'uploaded', 'GitHub 资源尚未上传完成')
        require(isinstance(checksum, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', checksum), 'GitHub 资源缺少 SHA256')
        require(type(size) is int and size > 0, 'GitHub 资源长度无效')
        address = f'https://github.com/{repository}/releases/download/{tag}/{quote(name, safe="")}'
        require(asset.get('browser_download_url') == address, 'GitHub 资源地址不属于当前发行')
        normalized.append({key: asset[key] for key in ('id', 'name', 'state', 'size', 'digest', 'browser_download_url')})
    require(len({asset['name'] for asset in normalized}) == 14, 'GitHub 资源存在重复文件名')
    # Exclude mutable download counters so repeated runs remain byte-for-byte idempotent.
    return {'id': value.get('id'), 'tag_name': tag, 'draft': False, 'prerelease': False,
            'html_url': release_url, 'assets': sorted(normalized, key=lambda asset: asset['name'])}


def manifest(value, tag):
    require(isinstance(value, dict) and type(value.get('schemaVersion')) is int and value['schemaVersion'] == 1, '更新清单 schemaVersion 无效')
    version, build = value.get('version'), value.get('buildNumber')
    require(isinstance(version, str) and re.fullmatch(r'\d+\.\d+\.\d+', version), '更新清单版本无效')
    require(tag == f'client-v{version}' and type(build) is int and build > 0, '更新清单 tag 或构建号不一致')
    require(isinstance(value.get('notes'), str), '更新日志格式无效')
    require(isinstance(value.get('downloads'), dict) and set(value['downloads']) == {'macos', 'windows', 'android'}, '更新清单下载平台不完整')
    require(isinstance(value.get('appcasts'), dict) and set(value['appcasts']) == {'macos', 'windows'}, '更新清单 appcast 平台不完整')
    return value


def artifact_names(release):
    prefix = f"huabu-{release['version']}+{release['buildNumber']}-"
    return {prefix + suffix for suffix in (
        'macos.dmg', 'macos.zip', 'windows-x64-setup.exe', 'windows-x64.zip', 'android.aab',
        'android-universal.apk', 'android-armeabi-v7a.apk', 'android-arm64-v8a.apk', 'android-x86_64.apk',
        'ios-unsigned.xcarchive.zip')}


def read_public_key(path, macos=False):
    data = path.read_bytes().strip()
    require(b'PRIVATE KEY' not in data, '仅允许提供更新公钥')
    if macos and not data.startswith(b'-----BEGIN PUBLIC KEY-----'):
        key = ed25519.Ed25519PublicKey.from_public_bytes(base64.b64decode(data, validate=True))
    else:
        key = serialization.load_pem_public_key(data)
    require(isinstance(key, ed25519.Ed25519PublicKey if macos else dsa.DSAPublicKey), '更新公钥类型不匹配')
    return key


def validate_sources(directory, record, repository, macos_key, windows_key):
    assets = {asset['name']: asset for asset in record['assets']}
    source = lambda name: directory / 'source' / name if name in METADATA else directory / name
    for name, asset in assets.items():
        path = source(name)
        require(path.is_file() and not path.is_symlink(), f'缺少完整资源：{name}')
        require(path.stat().st_size == asset['size'] and digest(path).hex() == asset['digest'][7:], f'GitHub 摘要或长度不一致：{name}')
    release = manifest(json.loads(source('flutter-release.json').read_bytes()), record['tag_name'])
    require(set(assets) == artifact_names(release) | METADATA, '发行资源集合与实际版本不一致')
    checksums = {}
    for line in source('SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9+._-]+)', line)
        require(match is not None and match[2] not in checksums, '来源 SHA256SUMS 格式无效')
        checksums[match[2]] = match[1]
    require(set(checksums) == set(assets) - {'SHA256SUMS'}, '来源 SHA256SUMS 资源集合不完整')
    require(all(checksums[name] == assets[name]['digest'][7:] for name in checksums), '来源 SHA256SUMS 与 GitHub 不一致')
    prefix = f"huabu-{release['version']}+{release['buildNumber']}-"
    base = f"https://github.com/{repository}/releases/download/{record['tag_name']}/"
    downloads = {'macos': prefix + 'macos.dmg', 'windows': prefix + 'windows-x64-setup.exe', 'android': prefix + 'android-universal.apk'}
    require(release['downloads'] == {platform: base + quote(name, safe='') for platform, name in downloads.items()}, '来源下载链接与当前包不一致')
    require(release['appcasts'] == {platform: base + f'appcast-{platform}.xml' for platform in ('macos', 'windows')}, '来源 appcast 链接不一致')
    feeds = {}
    for platform, filename in (('macos', prefix + 'macos.zip'), ('windows', prefix + 'windows-x64-setup.exe')):
        tree = SafeET.parse(source(f'appcast-{platform}.xml'))
        items = tree.findall('channel/item')
        require(len(items) == 1, '来源 appcast 必须包含唯一当前版本')
        item = items[0]
        enclosures = item.findall('enclosure')
        require(len(enclosures) == 1, '来源 appcast 安装包不唯一')
        enclosure = enclosures[0]
        require(enclosure.get('url') == base + quote(filename, safe='') and enclosure.get('length') == str(assets[filename]['size']), '来源 appcast 地址或长度不一致')
        require(enclosure.get(f'{{{SPARKLE}}}os') == platform and item.findtext('description') == release['notes'], '来源 appcast 平台或日志不一致')
        if platform == 'macos':
            require(item.findtext(f'{{{SPARKLE}}}version') == str(release['buildNumber']) and item.findtext(f'{{{SPARKLE}}}shortVersionString') == release['version'], 'Mac appcast 版本不一致')
            signature = base64.b64decode(enclosure.get(f'{{{SPARKLE}}}edSignature', ''), validate=True)
            macos_key.verify(signature, source(filename).read_bytes())
        else:
            require(enclosure.get(f'{{{SPARKLE}}}version') == f"{release['version']}+{release['buildNumber']}", 'Windows appcast 版本不一致')
            signature = base64.b64decode(enclosure.get(f'{{{SPARKLE}}}dsaSignature', ''), validate=True)
            # WinSparkle 0.8.1 verifies SHA1(SHA1(installer)), matching sign_update.bat.
            windows_key.verify(signature, digest(source(filename), 'sha1'), hashes.SHA1())
        feeds[platform] = tree
    return release, feeds, downloads


def page(releases, base, history=False):
    url = lambda path: html.escape(base + '/' + quote(path, safe='/'), quote=True)
    origin = urlparse(base)
    icon_url = html.escape(f'{origin.scheme}://{origin.netloc}/downloads/app-icon.png', quote=True)
    cards = []
    platforms = (('macos.dmg', 'macOS', 'Intel 与 Apple Silicon', '⌘'),
                 ('windows-x64-setup.exe', 'Windows', '64 位安装器', '⊞'),
                 ('android-universal.apk', 'Android', '通用 APK', '↗'))
    archives = (('macos.zip', 'macOS ZIP', '完整应用归档'), ('windows-x64.zip', 'Windows ZIP', '完整便携应用'),
                ('android-arm64-v8a.apk', 'Android ARM64', '按设备架构选择'), ('android-armeabi-v7a.apk', 'Android ARMv7', '按设备架构选择'),
                ('android-x86_64.apk', 'Android x86_64', '按设备架构选择'), ('android.aab', 'Android AAB', '应用市场用，不能直接安装'),
                ('ios-unsigned.xcarchive.zip', 'iOS 未签名归档', '仅供 Xcode 签名导出，不能直接安装'))
    for index, release in enumerate(sorted(releases, key=version_order, reverse=True)):
        tag = f"client-v{release['version']}"
        asset = lambda suffix: url(f"releases/{tag}/huabu-{release['version']}+{release['buildNumber']}-{suffix}")
        downloads = ''.join(f'<a class="download" href="{asset(suffix)}"><span class="platform" aria-hidden="true">{icon}</span><span><strong>{label}</strong><small>{caption}</small></span><span class="arrow" aria-hidden="true">↓</span></a>' for suffix, label, caption, icon in platforms)
        other = ''.join(f'<a class="archive" href="{asset(suffix)}"><strong>{label}</strong><small>{caption}</small><span aria-hidden="true">↗</span></a>' for suffix, label, caption in archives)
        badge = f'<span class="badge">{"最近发布" if history else "正式版本"}</span>' if index == 0 else ''
        cards.append(f'''<article aria-labelledby="version-{release['version']}">
<div class="version-heading"><div><span class="eyebrow">正式发行 · 构建 {release['buildNumber']}</span><h2 id="version-{release['version']}">v{release['version']} {badge}</h2></div><span class="edition">未来画布客户端</span></div>
<div class="release-body"><section class="notes"><h3>本次更新</h3><pre>{html.escape(release['notes'])}</pre></section><aside aria-label="v{release['version']} 安装包"><p class="download-label">选择你的设备</p>{downloads}<p class="install-note">下载后由系统确认安装</p></aside></div>
<details><summary>开发者与其他下载 <span>ZIP · 分架构 APK · AAB · iOS</span></summary><div class="archives">{other}</div></details></article>''')
    heading = '历史更新日志' if history else '更新与下载'
    return f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark">
<title>未来画布 · {heading}</title><style>
:root{{color-scheme:light dark;--bg:#f7f8fc;--card:#fff;--text:#202944;--muted:#65708a;--line:#e4e8f3;--soft:#f3f5fc;--blue:#3788ff;--purple:#7958ff;--shadow:0 18px 64px #293d6e08;font-family:"SF Pro Display","PingFang SC","Microsoft YaHei",sans-serif;background:var(--bg);color:var(--text)}}*{{box-sizing:border-box}}body{{margin:0;background:radial-gradient(ellipse at 90% 0,#7958ff09,transparent 45%)}}a{{color:inherit;text-decoration:none}}a:focus-visible,summary:focus-visible{{outline:3px solid var(--blue);outline-offset:5px}}.wrap{{width:min(1120px,100% - 64px);margin:auto}}header{{height:96px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--line)}}.brand{{display:flex;align-items:center;gap:12px;font-size:17px;font-weight:650;letter-spacing:.02em}}.brand img{{width:38px;height:38px;border-radius:11px}}.header-link{{font-size:13px;color:var(--muted);padding:10px 0}}.header-link:hover{{color:var(--blue)}}main{{padding:72px 0 56px;animation:arrive .45s ease-out}}.hero{{margin-bottom:44px;display:flex;align-items:flex-end;justify-content:space-between;gap:28px}}.eyebrow{{font-size:11px;font-weight:600;letter-spacing:.12em;color:var(--muted)}}.hero .eyebrow{{color:var(--purple)}}h1{{font-size:clamp(32px,4vw,48px);letter-spacing:-.055em;line-height:1.2;margin:18px 0 14px;font-weight:650}}.hero p{{font-size:14px;color:var(--muted);line-height:1.8;margin:0}}.hero-side{{white-space:nowrap;font-size:12px;color:var(--muted);padding-bottom:4px}}.hero-side::before{{content:"";display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--blue);margin-right:9px}}article{{background:var(--card);border:1px solid var(--line);border-radius:24px;box-shadow:var(--shadow);margin:24px 0;overflow:hidden}}.version-heading{{display:flex;justify-content:space-between;align-items:center;gap:16px;padding:30px 34px;border-bottom:1px solid var(--line)}}h2{{display:flex;align-items:center;gap:14px;font-size:32px;font-weight:600;letter-spacing:-.04em;margin:8px 0 0}}.badge{{padding:5px 9px;background:#3788ff12;color:var(--blue);border-radius:6px;font-size:10px;font-weight:600;letter-spacing:.02em}}.edition{{font-size:12px;color:var(--muted)}}.release-body{{display:grid;grid-template-columns:minmax(0,1fr) 280px;gap:44px;padding:30px 34px 34px}}h3,.download-label{{font-size:12px;letter-spacing:.04em;font-weight:600;margin:0 0 18px}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.95 "SF Pro Text","PingFang SC","Microsoft YaHei",sans-serif;color:var(--muted);margin:0}}.download{{display:flex;gap:12px;align-items:center;min-height:70px;margin-bottom:10px;padding:13px 15px;border:1px solid var(--line);border-radius:13px;background:var(--soft);transition:transform .18s,border-color .18s}}.download:hover{{transform:translateY(-2px);border-color:var(--blue)}}.platform{{font-size:24px;width:30px;text-align:center;color:var(--blue)}}.download strong,.archive strong{{display:block;font-size:13px;font-weight:600}}small{{display:block;font-size:11px;color:var(--muted);margin-top:5px}}.arrow{{margin-left:auto;color:var(--blue);font-size:20px}}.install-note{{text-align:center;color:var(--muted);font-size:10px;margin:15px 0 0}}details{{border-top:1px solid var(--line);padding:0 34px}}summary{{cursor:pointer;padding:20px 0;font-size:12px;color:var(--muted)}}summary span{{font-size:10px;margin-left:12px;opacity:.8}}.archives{{display:grid;grid-template-columns:1fr 1fr;gap:12px 24px;padding:0 0 26px}}.archive{{position:relative;padding:14px 28px 14px 0;border-top:1px solid var(--line)}}.archive:hover strong{{color:var(--blue)}}.archive>span{{position:absolute;right:0;top:16px;color:var(--muted)}}footer{{display:flex;justify-content:space-between;gap:20px;padding:26px 0 38px;border-top:1px solid var(--line);font-size:11px;color:var(--muted);line-height:1.8}}@keyframes arrive{{from{{opacity:0;transform:translateY(8px)}}to{{opacity:1;transform:none}}}}@media(prefers-color-scheme:dark){{:root{{--bg:#0b0d14;--card:#171a26;--text:#edf1fc;--muted:#9ca8c2;--line:#252a3a;--soft:#1c2030;--shadow:0 18px 64px #00000015}}}}@media(max-width:800px){{.wrap{{width:calc(100% - 36px)}}header{{height:78px}}main{{padding-top:44px}}.hero{{display:block;margin-bottom:30px}}.hero-side{{margin-top:20px}}.release-body{{grid-template-columns:1fr;gap:28px}}.version-heading,.release-body{{padding:24px}}.edition{{display:none}}details{{padding:0 24px}}.archives{{grid-template-columns:1fr}}summary span{{display:block;margin:6px 0 0 18px}}footer{{flex-direction:column;gap:4px}}}}@media(prefers-reduced-motion:reduce){{main{{animation:none}}.download{{transition:none}}}}
</style></head><body><div class="wrap"><header><a class="brand" href="{url('index.html')}"><img src="{icon_url}" alt="" width="38" height="38">未来画布</a><a class="header-link" href="{url('index.html' if history else 'history.html')}">{'返回最新版本' if history else '所有版本与更新日志'} <span aria-hidden="true">↗</span></a></header>
<main><section class="hero"><div><span class="eyebrow">未来画布 / 产品更新</span><h1>{'每一次更新，都有迹可循。' if history else '为下一次灵感，准备就绪。'}</h1><p>{'查看已发布版本的变化，选择适合你的安装包。' if history else '查看最新更新，下载适合你设备的未来画布。'}</p></div><div class="hero-side">本站提供完整安装包</div></section>{''.join(cards)}</main><footer><span>未来画布 · 让想象发生</span><span>下载与安装需系统确认；iOS 未签名归档仅供开发者使用。</span></footer></div></body></html>'''.encode()


def version_order(release):
    return Version(release['version']), release['buildNumber']


def rewrite(directory, record, release, feeds, downloads, base, write=True):
    tag = record['tag_name']
    url = lambda name: base + '/releases/' + tag + '/' + quote(name, safe='')
    mirrored = dict(release, downloads={platform: url(name) for platform, name in downloads.items()},
                    appcasts={platform: url(f'appcast-{platform}.xml') for platform in feeds})
    files = {'flutter-release.json': json_bytes(mirrored)}
    for platform, tree in feeds.items():
        enclosure = tree.find('channel/item/enclosure')
        name = f"huabu-{release['version']}+{release['buildNumber']}-" + ('macos.zip' if platform == 'macos' else 'windows-x64-setup.exe')
        enclosure.set('url', url(name))
        tree.find('channel/link').text = url('index.html')
        ET.indent(tree)
        buffer = io.BytesIO()
        tree.write(buffer, encoding='utf-8', xml_declaration=True)
        files[f'appcast-{platform}.xml'] = buffer.getvalue()
    names = artifact_names(release) | (METADATA - {'SHA256SUMS'})
    checksums = {name: hashlib.sha256(files[name]).hexdigest() if name in files else digest(directory / name).hex() for name in names}
    files['SHA256SUMS'] = ''.join(f'{checksums[name]}  {name}\n' for name in sorted(names)).encode()
    files['index.html'] = page([mirrored], base)
    if write:
        for name, data in files.items():
            (directory / name).write_bytes(data)
    return mirrored, files


def atomic_file(path, data):
    with tempfile.NamedTemporaryFile(prefix=f'.{path.parent.name}-{path.name}-', dir=path.parent.parent, delete=False) as output:
        temporary = Path(output.name)
        output.write(data)
        output.flush()
        os.fsync(output.fileno())
    try:
        temporary.chmod(0o644)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def link(path, target, replace=False):
    if path.is_symlink() and os.readlink(path) == target:
        return
    require(not path.exists() and not path.is_symlink() or replace and path.is_symlink(), f'不能覆盖已有非镜像入口：{path.name}')
    # Temporary entries stay outside the public tree and never block crash recovery.
    with tempfile.TemporaryDirectory(prefix=f'.{path.parent.name}-pointer-', dir=path.parent.parent) as folder:
        temporary = Path(folder) / 'pointer'
        temporary.symlink_to(target)
        os.replace(temporary, path)


def mirror(args):
    destination = args.destination.absolute()
    require(not destination.is_symlink(), '镜像目标目录不能是符号链接')
    destination.mkdir(parents=True, exist_ok=True)
    with (destination.parent / f'.{destination.name}.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('已有同步进程运行，本轮跳过')
            return
        raw = json.loads((args.source_dir / 'github-release.json').read_bytes()) if args.source_dir else json.loads(fetch(
            f'https://api.github.com/repos/{args.repository}/releases/' + ('tags/' + quote(args.tag, safe='') if args.tag else 'latest')))
        record = release_record(raw, args.repository, args.tag)
        macos_key, windows_key = read_public_key(args.macos_public_key, True), read_public_key(args.windows_public_key)
        tag = record['tag_name']
        versions = destination / 'releases'
        require(not versions.is_symlink(), '版本目录不能是符号链接')
        versions.mkdir(exist_ok=True)
        final = versions / tag
        require(not final.is_symlink(), '已存在版本不能是符号链接')
        stage = None
        try:
            if final.exists():
                require(not any(path.is_symlink() for path in final.rglob('*')), '已有版本包含异常符号链接')
                require(json.loads((final / 'source/github-release.json').read_bytes()) == record, '同一 tag 的来源已变化，拒绝覆盖')
                release, feeds, downloads = validate_sources(final, record, args.repository, macos_key, windows_key)
                mirrored, expected = rewrite(final, record, release, feeds, downloads, args.public_base_url, write=False)
                require(all((final / name).read_bytes() == data for name, data in expected.items()), '已有版本文件与校验结果不一致，拒绝覆盖')
                files = {str(path.relative_to(final)) for path in final.rglob('*') if path.is_file()}
                require(files == artifact_names(release) | set(expected) | {f'source/{name}' for name in METADATA | {'github-release.json'}}, '已有版本包含异常文件')
            else:
                stage = Path(tempfile.mkdtemp(prefix=f'.{destination.name}-{tag}-', dir=destination.parent))
                (stage / 'source').mkdir()
                for asset in record['assets']:
                    target = stage / 'source' / asset['name'] if asset['name'] in METADATA else stage / asset['name']
                    if args.source_dir:
                        matches = list(args.source_dir.rglob(asset['name']))
                        require(len(matches) == 1 and matches[0].is_file() and not matches[0].is_symlink(), f'离线资源缺失或重复：{asset["name"]}')
                        shutil.copyfile(matches[0], target)
                    else:
                        fetch(asset['browser_download_url'], target)
                (stage / 'source/github-release.json').write_bytes(json_bytes(record))
                release, feeds, downloads = validate_sources(stage, record, args.repository, macos_key, windows_key)
                mirrored, _ = rewrite(stage, record, release, feeds, downloads, args.public_base_url)
                for path in stage.rglob('*'):
                    path.chmod(0o555 if path.is_dir() else 0o444)
                # APFS requires the moved directory itself to remain writable.
                stage.chmod(0o755)
                os.replace(stage, final)
                stage = None
            # Also finish sealing a version after an interrupted rename.
            final.chmod(0o555)
            history = []
            for path in versions.iterdir():
                require(path.is_dir() and not path.is_symlink(), '版本历史目录存在异常文件')
                history.append(manifest(json.loads((path / 'flutter-release.json').read_bytes()), path.name))
            latest = destination / 'latest'
            previous = None
            if latest.is_symlink():
                target = os.readlink(latest)
                require(re.fullmatch(r'releases/client-v\d+\.\d+\.\d+', target) is not None, 'latest 指针格式无效')
                previous = manifest(json.loads((latest / 'flutter-release.json').read_bytes()), Path(target).name)
            else:
                require(not latest.exists(), 'latest 入口不是符号链接')
            atomic_file(destination / 'history.html', page(history, args.public_base_url, True))
            for name in ('index.html', 'flutter-release.json', 'appcast-macos.xml', 'appcast-windows.xml'):
                link(destination / name, f'latest/{name}')
            if previous is None or version_order(mirrored) >= version_order(previous):
                link(latest, f'releases/{tag}', replace=True)
                print(f'镜像校验完成，当前版本 {release["version"]}+{release["buildNumber"]}')
            else:
                print(f'历史版本 {release["version"]}+{release["buildNumber"]} 已校验，保留较新的 latest')
        finally:
            if stage is not None:
                for path in stage.rglob('*'):
                    if path.is_dir():
                        path.chmod(0o755)
                stage.chmod(0o755)
                shutil.rmtree(stage)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', default='heiyuan0801/huabu-releases')
    parser.add_argument('--destination', required=True, type=Path)
    parser.add_argument('--public-base-url', required=True)
    parser.add_argument('--tag')
    parser.add_argument('--source-dir', type=Path, help='Offline source with github-release.json and release assets')
    parser.add_argument('--macos-public-key', required=True, type=Path)
    parser.add_argument('--windows-public-key', required=True, type=Path)
    args = parser.parse_args()
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository) is not None, '仓库名格式无效')
    uri = urlparse(args.public_base_url)
    require(uri.scheme == 'https' and uri.hostname and uri.username is None and uri.password is None and not uri.query and not uri.fragment, '公开地址必须是不含凭据的 HTTPS 地址')
    args.public_base_url = args.public_base_url.rstrip('/')
    if args.tag:
        require(re.fullmatch(r'client-v\d+\.\d+\.\d+', args.tag) is not None, '指定 tag 格式无效')
    mirror(args)


if __name__ == '__main__':
    try:
        main()
    except MirrorError as error:
        print(f'同步未完成：{error}', file=sys.stderr)
        sys.exit(1)
    except InvalidSignature:
        print('同步未完成：更新签名验证失败，保留当前版本', file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        # Never print raw HTTP exceptions, redirect URLs, headers or key material.
        print(f'同步未完成：{type(error).__name__}，保留当前版本；请检查来源格式与文件权限', file=sys.stderr)
        sys.exit(1)
