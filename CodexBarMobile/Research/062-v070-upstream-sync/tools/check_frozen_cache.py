#!/usr/bin/env python3
"""冻结旧/新真实缓存代码的 iOS 磁盘矩阵；不替代实体 CloudKit/APNs/UI。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--scratch', type=Path, required=True)
parser.add_argument('--wire-root', type=Path, required=True)
parser.add_argument('--simulator', required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[4]
volume = plistlib.loads(subprocess.check_output(['diskutil', 'info', '-plist', '/Volumes/StudioSSD']))
if (volume.get('VolumeUUID') != '9D5FE511-B66C-4765-BB8F-61E5ACB3969D'
        or volume.get('MountPoint') != '/Volumes/StudioSSD' or not os.path.ismount('/Volumes/StudioSSD')):
    raise SystemExit('StudioSSD validation failed')
root = args.scratch.resolve()
wire = args.wire_root.resolve()
for path in [root, wire, repo]:
    if not path.is_relative_to(Path('/Volumes/StudioSSD')):
        raise SystemExit('All inputs and outputs must resolve on StudioSSD')
if not root.is_relative_to(Path('/Volumes/StudioSSD/Developer/BuildScratch')):
    raise SystemExit('Scratch must be under BuildScratch')
root.mkdir(parents=True, exist_ok=False)
(root / 'tmp').mkdir()
wire_manifest_bytes = (wire / 'source-manifest.json').read_bytes()
wire_manifest = json.loads(wire_manifest_bytes)
wire_harness = Path(__file__).with_name('FrozenWireHarness.swift').read_bytes()
if hashlib.sha256(wire_harness).hexdigest() != wire_manifest['harnessSHA256']:
    raise SystemExit('Wire harness drift')
(root / 'wire').mkdir()
wire_inputs = {}
for kind in ['old', 'new']:
    for device in ['mac-a', 'mac-b']:
        name = kind + '-' + device + '.json'
        data = (wire / name).read_bytes()
        (root / 'wire' / name).write_bytes(data)
        wire_inputs[name] = hashlib.sha256(data).hexdigest()
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j']))
targets = [(runtime, device) for runtime, entries in devices['devices'].items()
           for device in entries if device['udid'] == args.simulator]
if len(targets) != 1 or targets[0][1]['state'] != 'Booted' or 'iOS' not in targets[0][0]:
    raise SystemExit('Target must be a booted iOS Simulator')
old_ref = wire_manifest['oldCommit']
for item in wire_manifest['files']:
    current = (repo / item['path']).read_bytes()
    old = subprocess.check_output(['git', 'show', old_ref + ':' + item['path']], cwd=repo)
    if (hashlib.sha256(current).hexdigest() != item['newSHA256']
            or hashlib.sha256(old).hexdigest() != item['oldSHA256']):
        raise SystemExit('Wire source drift: ' + item['path'])
paths = sorted(str(p.relative_to(repo)) for p in (repo / 'Shared/Models').glob('*.swift'))
paths += ['Shared/iCloud/CloudConstants.swift', 'Shared/iCloud/AccountIdentityNormalize.swift',
          'Shared/Utilities/EmailRedaction.swift']
paths += ['CodexBarMobile/CodexBarMobile/Storage/' + n + '.swift' for n in
          ['SwiftDataSchema', 'CostLedgerModels', 'ModelContainerFactory', 'SwiftDataBridge', 'CostLedgerService']]
paths += ['CodexBarMobile/CodexBarMobile/Models/' + n + '.swift' for n in
          ['MobileDisplayPreferences', 'TokenActivity', 'ProviderUsageSnapshot+Identity']]
paths += ['CodexBarMobile/CodexBarWidgetShared/ProviderSnapshotMerger.swift']
harness = Path(__file__).with_name('FrozenCacheHarness.swift').read_bytes()
(root / 'Harness.swift').write_bytes(harness)
manifest = {'oldCommit': old_ref, 'newCommit': subprocess.check_output(
    ['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'harnessSHA256': hashlib.sha256(harness).hexdigest(), 'files': [],
    'wireInputsSHA256': wire_inputs,
    'wireManifestSHA256': hashlib.sha256(wire_manifest_bytes).hexdigest(),
    'wireHarnessSHA256': wire_manifest['harnessSHA256'],
    'simulatorRuntime': targets[0][0], 'simulator': args.simulator}
platform = Path('/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer')
env = dict(os.environ, TMPDIR=str(root / 'tmp'), SIMCTL_CHILD_TMPDIR=str(root / 'tmp'))
for kind in ['old', 'new']:
    sources = []
    for path in paths:
        data = ((repo / path).read_bytes() if kind == 'new' else
                subprocess.check_output(['git', 'show', old_ref + ':' + path], cwd=repo))
        target = root / kind / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(data.decode().replace('import CodexBarSync\n', ''))
        sources.append(str(target))
        manifest['files'].append({'kind': kind, 'path': path, 'sha256': hashlib.sha256(data).hexdigest()})
    command = ['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-module-name', 'CodexBarSync',
               '-target', 'arm64-apple-ios17.0-simulator', '-sdk', str(platform / 'SDKs/iPhoneSimulator27.0.sdk'),
               '-module-cache-path', str(root / 'module-cache'), *sources, str(root / 'Harness.swift'),
               '-o', str(root / (kind + '-cache')), *(['-D', 'NEW_CACHE'] if kind == 'new' else [])]
    (root / (kind + '-compile-command.json')).write_text(json.dumps(command, indent=2))
    with (root / (kind + '-build.log')).open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env)
    print(kind, 'build', result.returncode, flush=True)
    if result.returncode:
        (root / 'source-manifest.json').write_text(json.dumps(manifest, indent=2))
        raise SystemExit(result.returncode)
(root / 'source-manifest.json').write_text(json.dumps(manifest, indent=2))
results = []
for mask in range(16):
    versions = ['new' if mask & (1 << bit) else 'old' for bit in [3, 2, 1, 0]]
    row = {'case': mask + 1, 'versions': versions, 'operations': []}
    for phone, reader in zip(['phone-a', 'phone-b'], versions[2:]):
        store = root / ('case-' + str(mask + 1)) / phone / 'Store.sqlite'
        store.parent.mkdir(parents=True, exist_ok=True)
        writers = [str(root / 'wire' / (versions[0] + '-mac-a.json')), str(root / 'wire' / (versions[1] + '-mac-b.json'))]
        for phase in ['write', 'read-prune', 'read-retained']:
            command = ['xcrun', 'simctl', 'spawn', args.simulator, str(root / (reader + '-cache')),
                       phase, str(store), *writers, '-cwlEnabled', 'YES']
            log_path = store.parent / (phase + '.log')
            with log_path.open('w') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env)
            row['operations'].append({'phone': phone, 'reader': reader, 'phase': phase,
                                      'command': command, 'log': str(log_path), 'exit': result.returncode})
            if result.returncode:
                results.append(row)
                (root / 'matrix-cache.json').write_text(json.dumps({'cases': results}, indent=2))
                raise SystemExit(result.returncode)
    row['result'] = 'pass'
    results.append(row)
    print('case', mask + 1, 'pass', flush=True)
(root / 'matrix-cache.json').write_text(json.dumps({
    'scope': 'real published-old/current iOS SwiftData cache, cold merge and disk ghost prune; synthetic wire, no CloudKit/APNs/UI',
    'cases': results}, indent=2))
print('PASS: 16 masks, 32 independent caches, 96 separate iOS processes', flush=True)
