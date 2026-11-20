#!/usr/bin/env python3
"""AsmrDownloader 的 KaneoPilot 发布适配器（只服务两个固定文件名的 zip）。

prepare <release-files>   从目录里的两个 zip 生成 kaneopilot-release.json
publish <release-files>   复用同一份字节创建/复用 draft Release，上传资产，回读校验后发布

身份字段全部来自 workflow env，不插值进 shell 源码。task_manifest 原样写入、不做任何
清洗：KaneoPilot 会按 sort_keys=True 与紧凑分隔符重新序列化后与冻结输入逐字节比对。
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.parse

MANIFEST_NAME = 'kaneopilot-release.json'
# 固定资产名：KaneoPilot 的发布策略 required_assets 与这里必须一致（不带版本号）。
ASSETS = ('AsmrDownloader-Windows.zip', 'AsmrDownloader-macOS.zip')
SHA = re.compile(r'[0-9a-f]{40}')
TAG = re.compile(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z][0-9A-Za-z.-]*)?')


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def setting(name):
    return (os.environ.get(name) or '').strip()


def matches(pattern, value):
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def collect_assets(root):
    require(root.is_dir(), '发布目录不存在：' + str(root))
    files = {}
    for path in sorted(root.rglob('*')):
        require(not path.is_symlink(), '发布资产不允许符号链接：' + path.name)
        if not path.is_file():
            continue
        if path.parent == root and path.name == MANIFEST_NAME:
            continue
        require(path.name in ASSETS, '出现未声明的发布资产：' + path.name)
        require(path.name not in files, '发布资产重复：' + path.name)
        require(path.stat().st_size > 0, '发布资产为空：' + path.name)
        files[path.name] = path
    missing = [name for name in ASSETS if name not in files]
    require(not missing, '缺少发布资产：' + ', '.join(missing))
    return files


def identity(tag):
    """tag 与 channel/version 必须自洽：prerelease 当且仅当 tag 带 - 后缀。"""
    matched = TAG.fullmatch(tag)
    require(matched is not None, 'tag 必须是 vX.Y.Z 或 vX.Y.Z-<预发布后缀>：' + repr(tag))
    version = tag[1:].split('-', 1)[0]
    channel = 'prerelease' if matched.group(4) else 'stable'
    return channel, version


def composition(files):
    repository = setting('GITHUB_REPOSITORY')
    require(repository != '', '缺少 GITHUB_REPOSITORY')
    run_id = setting('GITHUB_RUN_ID')
    attempt = setting('GITHUB_RUN_ATTEMPT')
    require(re.fullmatch(r'[1-9][0-9]*', run_id) is not None, 'GITHUB_RUN_ID 无效：' + repr(run_id))
    require(re.fullmatch(r'[1-9][0-9]*', attempt) is not None, 'GITHUB_RUN_ATTEMPT 无效：' + repr(attempt))
    tag = setting('TAG_NAME') or setting('GITHUB_REF_NAME')
    channel, version = identity(tag)
    target = (setting('TARGET_SHA') or setting('GITHUB_SHA')).lower()
    require(matches(SHA, target), 'target_sha 必须是完整 40 位小写 commit SHA：' + repr(target))
    batch = setting('RELEASE_BATCH_ID')
    raw = os.environ.get('TASK_MANIFEST_JSON') or ''
    declared_sha = setting('TASK_MANIFEST_SHA256').lower()
    task = {}
    if raw.strip():
        require(hashlib.sha256(raw.encode('utf-8')).hexdigest() == declared_sha,
                'task_manifest_sha256 与 task_manifest_json 的字节不一致')
        try:
            task = json.loads(raw)
        except ValueError as error:
            raise ValueError('task_manifest_json 不是合法 JSON：' + str(error)) from None
        require(isinstance(task, dict), 'task_manifest_json 必须是 JSON 对象')
        # 清理过的清单会让核心的逐字节比对必然失败，所以在写任何远端状态之前就拒绝。
        require(canonical(task) == raw.encode('utf-8'),
                'task_manifest_json 不是规范 JSON（sort_keys/紧凑分隔符），核心会按规范形式逐字节比对')
    if task:
        require(batch != '', 'dispatch 缺少 release_batch_id')
        require(task.get('channel') in ('prerelease', 'stable'), 'task_manifest.channel 无效')
        require(task.get('channel') == channel, 'task_manifest.channel 与 tag 不一致：' + repr(channel))
        require(task.get('version') == version, 'task_manifest.version 与 tag 不一致：' + repr(version))
        require(task.get('tag') == tag, 'task_manifest.tag 与 inputs.tag_name 不一致')
        require(task.get('target_sha') == target, 'task_manifest.target_sha 与 inputs.target_sha 不一致')
        require(task.get('repository') == repository, 'task_manifest.repository 与当前仓库不一致')
        require(task.get('batch_id') == batch, 'task_manifest.batch_id 与 inputs.release_batch_id 不一致')
        number = task.get('build_number')
        require(type(number) is int and 0 < number <= 2147483647, 'task_manifest.build_number 必须是正整数')
        required = task.get('required_assets')
        if isinstance(required, list) and required:
            missing = [name for name in required if name not in ASSETS]
            require(not missing, 'KaneoPilot 发布策略要求本工作流不产出的资产名：' + ', '.join(missing)
                    + '（工作流固定产出：' + ', '.join(ASSETS) + '）')
    else:
        # tag 推送 / 手动补发没有清单：身份从 tag 推导，不影响 dispatch 路径。
        number = 0
    rows = [dict(name=name, size=int(path.stat().st_size), sha256=sha256_file(path))
            for name, path in sorted(files.items())]
    return dict(schema=1, batch_id=batch, repository=repository, target_sha=target,
                task_manifest_sha256=declared_sha, task_manifest=task,
                workflow_run_id=int(run_id), run_attempt=int(attempt),
                channel=channel, version=version, tag=tag,
                build_number=int(number), assets=rows)


def build(root):
    provenance = composition(collect_assets(root))
    return provenance, canonical(provenance)


def prepare(root):
    provenance, data = build(root)
    path = root / MANIFEST_NAME
    path.write_bytes(data)
    return path, provenance


def write_or_check(root):
    """prepare 写下的字节就是 artifact 与 Release 资产的同一份字节。"""
    provenance, data = build(root)
    path = root / MANIFEST_NAME
    if path.exists():
        require(path.read_bytes() == data,
                'release-files/' + MANIFEST_NAME + ' 与本次输入不一致，不要手工改写这个文件')
    else:
        path.write_bytes(data)
    return path, provenance


def gh(args, payload=None, binary=False, allow_404=False):
    process = subprocess.run(['gh', *args], input=payload, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=os.environ, check=False)
    if process.returncode != 0:
        message = process.stderr.decode('utf-8', 'replace').strip()
        if allow_404 and 'HTTP 404' in message:
            return None
        raise ValueError('gh ' + ' '.join(args[:2]) + ' 失败：'
                         + (message or '退出码 ' + str(process.returncode)))
    return process.stdout if binary else process.stdout.decode('utf-8')


def api_json(path, method=None, payload=None, allow_404=False, headers=()):
    args = ['api']
    if method:
        args += ['--method', method]
    args.append(path)
    for header in headers:
        args += ['-H', header]
    if payload is not None:
        args += ['--input', '-']
    text = gh(args, payload=payload, allow_404=allow_404)
    if text is None:
        return None
    text = text.strip()
    return json.loads(text) if text else None


def quote(value):
    return urllib.parse.quote(value, safe='')


def tag_commit(repository, tag):
    ref = api_json('repos/' + repository + '/git/ref/tags/' + quote(tag), allow_404=True)
    if ref is None:
        return None
    obj = ref.get('object') if isinstance(ref, dict) else None
    seen = set()
    for _ in range(16):
        require(isinstance(obj, dict) and matches(SHA, obj.get('sha')), '远端 tag 对象无效')
        if obj['sha'] in seen:
            raise ValueError('远端 tag 对象成环')
        seen.add(obj['sha'])
        if obj.get('type') == 'commit':
            return obj['sha']
        require(obj.get('type') == 'tag', '远端 tag 未指向 commit')
        annotation = api_json('repos/' + repository + '/git/tags/' + obj['sha'])
        require(isinstance(annotation, dict) and annotation.get('sha') == obj['sha'],
                '远端 annotated tag 缺失或已变化')
        obj = annotation.get('object')
    raise ValueError('远端 tag 的注解层数超过上限')


def release_by_tag(repository, tag):
    return api_json('repos/' + repository + '/releases/tags/' + quote(tag), allow_404=True)


def draft_by_tag(repository, tag):
    """draft 不出现在 releases/tags 端点（这是 404 而不是空结果），只能从 Release 列表里找。"""
    for page in range(1, 11):
        rows = api_json('repos/' + repository + '/releases?per_page=100&page=' + str(page))
        require(isinstance(rows, list), '无法读取 Release 列表')
        for row in rows:
            if isinstance(row, dict) and row.get('tag_name') == tag and row.get('draft') is True:
                return row
        if len(rows) < 100:
            return None
    raise ValueError('Release 列表分页超过上限')


def list_assets(repository, release_id):
    rows = []
    for page in range(1, 21):
        values = api_json('repos/' + repository + '/releases/' + str(release_id)
                          + '/assets?per_page=100&page=' + str(page))
        require(isinstance(values, list), '无法读取 Release 资产列表')
        rows.extend(values)
        if len(values) < 100:
            return rows
    raise ValueError('Release 资产列表分页超过上限')


def assets_by_name(repository, release_id):
    rows = {}
    for asset in list_assets(repository, release_id):
        name = asset.get('name') if isinstance(asset, dict) else None
        require(isinstance(name, str) and name != '', 'Release 资产缺少名字')
        require(name not in rows, 'Release 资产重复：' + name)
        rows[name] = asset
    return rows


def fallback_notes(provenance):
    lines = ['## 构建信息', '',
             '- 版本标签：`' + provenance['tag'] + '`',
             '- 构建提交：`' + provenance['target_sha'] + '`',
             '- 发布渠道：`' + provenance['channel'] + '`', '',
             '请下载对应平台的 zip，并用同批发布的 `' + MANIFEST_NAME
             + '` 校验完整性（其中记录每个资产的 size 与 sha256）。', '']
    return '\n'.join(lines)


def notes_file(value, provenance):
    if value:
        path = Path(value)
        if path.is_file() and path.stat().st_size > 0:
            return path, False
    handle = tempfile.NamedTemporaryFile('w', suffix='.md', delete=False, encoding='utf-8')
    with handle:
        handle.write(fallback_notes(provenance))
    return Path(handle.name), True


def verify_release(repository, release, provenance, path):
    tag = provenance['tag']
    prerelease = provenance['channel'] == 'prerelease'
    require(isinstance(release, dict), '无法读取 Release')
    require(release.get('draft') is False, 'Release 仍是 draft')
    require(release.get('tag_name') == tag, 'Release tag 不是 ' + tag)
    require(release.get('prerelease') is prerelease, 'Release prerelease 与 channel 不一致')
    require(release.get('html_url') == 'https://github.com/' + repository + '/releases/tag/' + quote(tag),
            'Release 地址不是同仓库同 tag')
    require(tag_commit(repository, tag) == provenance['target_sha'], 'tag 未指向 target_sha')
    rows = assets_by_name(repository, release.get('id'))
    declared = {row['name']: (row['size'], 'sha256:' + row['sha256']) for row in provenance['assets']}
    verified = []
    for name in ASSETS:
        require(name in rows, 'Release 缺少必需资产：' + name)
        asset = rows[name]
        require(type(asset.get('size')) is int and (asset['size'], asset.get('digest')) == declared[name],
                'Release 资产的 size/digest 与声明不一致：' + name)
        url = ('https://github.com/' + repository + '/releases/download/' + quote(tag) + '/' + quote(name))
        require(asset.get('browser_download_url') == url, 'Release 资产下载地址不属于同仓库同 tag：' + name)
        verified.append(dict(name=name, size=declared[name][0], sha256=declared[name][1][7:], url=url))
    require(MANIFEST_NAME in rows, 'Release 缺少 ' + MANIFEST_NAME)
    asset = rows[MANIFEST_NAME]
    raw = path.read_bytes()
    require(type(asset.get('size')) is int and asset['size'] == len(raw),
            'Release 里的 ' + MANIFEST_NAME + ' 大小与本次 artifact 不一致')
    require(asset.get('digest') == 'sha256:' + hashlib.sha256(raw).hexdigest(),
            'Release 里的 ' + MANIFEST_NAME + ' digest 与本次 artifact 不一致')
    remote = gh(['api', 'repos/' + repository + '/releases/assets/' + str(asset.get('id')),
                 '-H', 'Accept: application/octet-stream'], binary=True)
    require(remote == raw, 'Release 里的 ' + MANIFEST_NAME + ' 字节与本次 artifact 不一致')
    verified.append(dict(name=MANIFEST_NAME, size=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                         url='https://github.com/' + repository + '/releases/download/' + quote(tag)
                         + '/' + quote(MANIFEST_NAME)))
    return dict(tag=tag, prerelease=prerelease, target_sha=provenance['target_sha'],
                release_url=release.get('html_url'), release_id=release.get('id'), assets=verified)


def create_draft(repository, provenance, notes):
    """POST 直接拿回 Release 身份：draft 无法按 tag 读回，不能让发布依赖第二次查询。"""
    path, generated = notes_file(notes, provenance)
    try:
        body = path.read_text(encoding='utf-8')
    finally:
        if generated:
            path.unlink(missing_ok=True)
    tag = provenance['tag']
    value = api_json('repos/' + repository + '/releases', method='POST',
                     payload=canonical(dict(tag_name=tag, target_commitish=provenance['target_sha'],
                                            name=repository.split('/')[-1] + ' ' + tag, body=body,
                                            draft=True,
                                            prerelease=provenance['channel'] == 'prerelease')),
                     headers=('Content-Type: application/json',))
    require(isinstance(value, dict) and type(value.get('id')) is int and value['id'] > 0,
            '创建 draft Release 后没有返回可用的 Release id')
    return value


def upload_assets(repository, tag, uploads):
    """资产必须走 gh 的 release 上传：REST 上传端点在 uploads.github.com，
    gh api 只打 api.github.com，对新上传固定 404。gh release upload 能按 tag 找到
    draft；同一份字节重跑时用 --clobber 覆盖成同样的内容。"""
    gh(['release', 'upload', tag, *[str(path) for path in uploads], '--repo', repository, '--clobber'])


def publish(root, notes):
    path, provenance = write_or_check(root)
    repository = provenance['repository']
    tag = provenance['tag']
    prerelease = provenance['channel'] == 'prerelease'
    current = tag_commit(repository, tag)
    if current is not None:
        require(current == provenance['target_sha'],
                '远端 tag ' + tag + ' 已指向 ' + current + '，不是本次 target_sha；拒绝覆盖已有发布')
    release = release_by_tag(repository, tag)
    if isinstance(release, dict) and release.get('draft') is False:
        # 已发布的 Release 不能重新打包；只有字节完全一致才算幂等重跑。
        return verify_release(repository, release, provenance, path)
    if not isinstance(release, dict):
        # 按 tag 读不到只证明它还不是已发布 Release；列表里同 tag 的 draft 必须复用而不是重建。
        release = draft_by_tag(repository, tag)
    if not isinstance(release, dict):
        release = create_draft(repository, provenance, notes)
    require(release.get('tag_name') == tag, 'draft Release 的 tag 不是 ' + tag)
    require(release.get('draft') is True, 'Release 不是可继续发布的 draft，请先人工核对：' + tag)
    require(release.get('target_commitish') == provenance['target_sha'],
            '已有 draft Release 的 target 是 ' + repr(release.get('target_commitish'))
            + '，不是本次 target_sha；拒绝复用')
    upload_assets(repository, tag, [root / name for name in ASSETS] + [path])
    value = api_json('repos/' + repository + '/releases/' + str(release['id']), method='PATCH',
                     payload=canonical(dict(draft=False, prerelease=prerelease)),
                     headers=('Content-Type: application/json',))
    require(isinstance(value, dict) and value.get('id') == release['id'], '发布 Release 后身份不可确认')
    final = release_by_tag(repository, tag)
    return verify_release(repository, final, provenance, path)


def main(argv):
    require(len(argv) >= 3, '用法：pilot_release.py prepare|publish <release-files 目录> [--notes-file PATH]')
    command = argv[1]
    root = Path(argv[2])
    if command == 'prepare':
        path, provenance = prepare(root)
        print(json.dumps(provenance['assets'], ensure_ascii=False, sort_keys=True))
        print('wrote ' + str(path) + ' (' + str(path.stat().st_size) + ' bytes)')
        return
    if command == 'publish':
        notes = argv[argv.index('--notes-file') + 1] if '--notes-file' in argv else ''
        result = publish(root, notes)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return
    raise ValueError('未知子命令：' + command)


if __name__ == '__main__':
    try:
        main(sys.argv)
    except (ValueError, OSError) as error:
        print('::error::' + str(error), file=sys.stderr)
        sys.exit(1)
