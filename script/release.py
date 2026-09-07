#!/usr/bin/env python3
"""Deterministic signed macOS releases. See docs/releasing.md."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
PROJECT = Path('SealNote.xcodeproj/project.pbxproj')


def run(*args, capture=False):
    return subprocess.run(args, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def versions(source, bump=False):
    pattern = re.compile(r'(/\* (?:Debug|Release) configuration for PBXNativeTarget "(?:SealNote|SealNoteMac)" \*/ = \{.*?\n\t\t\};)', re.S)
    blocks = pattern.findall(source)
    if len(blocks) != 4:
        raise ValueError('Expected four app build configurations')
    pairs = []
    for block in blocks:
        version = re.search(r'MARKETING_VERSION = (\d+\.\d+(?:\.\d+)?);', block)
        build = re.search(r'CURRENT_PROJECT_VERSION = (\d+);', block)
        if not version or not build:
            raise ValueError('Unsupported app version/build format')
        pairs.append((version[1], int(build[1])))
    if len(set(pairs)) != 1:
        raise ValueError('App versions/builds must agree across both platforms')
    version, build = pairs[0]
    if bump:
        major, minor, *_ = map(int, version.split('.'))
        version, build = f'{major}.{minor + 1}.0', build + 1
        def replace(match):
            block = re.sub(r'MARKETING_VERSION = [\d.]+;', f'MARKETING_VERSION = {version};', match[0])
            return re.sub(r'CURRENT_PROJECT_VERSION = \d+;', f'CURRENT_PROJECT_VERSION = {build};', block)
        source = pattern.sub(replace, source)
    return source, version, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['minor', 'resume'])
    parser.add_argument('--dry-run', action='store_true', help='Show version and checks without writes or network calls')
    parser.add_argument('--unsigned', action='store_true', help='Publish an unsigned DMG as a prerelease')
    args = parser.parse_args()
    package = ['bash', 'script/package_macos.sh'] + (['--unsigned'] if args.unsigned else [])
    source = (ROOT / PROJECT).read_text()
    updated, version, build = versions(source, args.action == 'minor')
    tag = f'v{version}'
    print(f'{args.action}: {tag} (build {build})', flush=True)
    if args.dry_run:
        return
    if run('git', 'branch', '--show-current', capture=True).strip() != 'main':
        raise ValueError('Release must run on main')
    if run('git', 'status', '--porcelain', capture=True).strip():
        raise ValueError('Commit or stash working tree changes before releasing')
    run(*package, '--check')
    run('gh', 'auth', 'status')
    run('git', 'fetch', 'origin', '--tags')
    run('git', 'merge-base', '--is-ancestor', 'origin/main', 'HEAD')
    if args.action == 'minor':
        if run('git', 'tag', '--list', tag, capture=True).strip():
            raise ValueError(f'{tag} already exists')
        (ROOT / PROJECT).write_text(updated)
        run('plutil', '-lint', str(PROJECT))
        run('git', 'diff', '--check')
        run('git', 'add', str(PROJECT))
        run('git', 'commit', '-m', f'Release {tag} (build {build})')
    head = run('git', 'rev-parse', 'HEAD', capture=True).strip()
    if args.action == 'resume':
        subject = run('git', 'log', '-1', '--format=%s', capture=True).strip()
        if subject != f'Release {tag} (build {build})':
            raise ValueError('Resume requires HEAD to be the release commit')
    if run('git', 'tag', '--list', tag, capture=True).strip():
        if run('git', 'rev-parse', f'{tag}^{{commit}}', capture=True).strip() != head:
            raise ValueError('Tag does not point to the release commit')
    else:
        run('git', 'tag', '-a', tag, '-m', f'Seal Note {tag} (build {build})')
    run('git', 'push', '--atomic', 'origin', 'HEAD:refs/heads/main', f'refs/tags/{tag}')
    # Listing must succeed; an API/auth failure must not be mistaken for absence.
    releases = json.loads(run('gh', 'api', '--paginate', '--slurp',
                             'repos/{owner}/{repo}/releases?per_page=100', capture=True))
    existing = next((r for page in releases for r in page if r['tag_name'] == tag), None)
    if existing:
        if existing['draft']:
            raise ValueError('A draft already exists; review and publish it explicitly')
        print(existing['html_url'])
        return
    run(*package, version, str(build))
    dmg = ROOT / 'dist' / version / f'Seal-Note-{version}.dmg'
    checksums = dmg.parent / 'SHA256SUMS.txt'
    previous = run('git', 'describe', '--tags', '--abbrev=0', 'HEAD^', capture=True).strip()
    commits = run('git', 'log', '--format=- %s (%h)', f'{previous}..HEAD', capture=True)
    distribution = ('非正式预发布：macOS 通用 DMG 未经 Developer ID 签名与 Apple 公证，首次打开可能被 Gatekeeper 拦截。仅供测试。' if args.unsigned else 'macOS 通用 DMG 已通过 Developer ID 签名、Apple 公证与 Gatekeeper 验证。')
    notes = f'## Seal Note {version}\n\n版本：{version} · Build：{build}\n\n{distribution} 支持 Apple Silicon + Intel。校验值见 SHA256SUMS.txt。\n\n### 提交记录\n\n{commits}'
    subprocess.run(['gh', 'release', 'create', tag, str(dmg), str(checksums), '--verify-tag', '--title',
                    f'Seal Note {tag}', '--notes-file', '-'] + (['--prerelease'] if args.unsigned else []), cwd=ROOT,
                   input=notes, text=True, check=True)
    run('gh', 'release', 'view', tag, '--json', 'url,isDraft,tagName')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f'Release stopped: {error}\nAfter a release commit exists, retry with: python3 script/release.py resume (keep --unsigned if used)', file=sys.stderr)
        sys.exit(1)
