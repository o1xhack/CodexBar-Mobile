import subprocess,plistlib,json,hashlib,os,zipfile,re,datetime
from pathlib import Path
r=Path('/Volumes/StudioSSD/Projects/working/apple/CodexBar');s=Path('/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v083');os.chdir(r)
out=s/'mac-artifact-verification';out.mkdir()
name='CodexBar-0.83.0.1-mobile.3.3.0'; assetRoot=r/'CodexBarMobile/build/upstream-v083'; files=[assetRoot/(name+'.zip'),assetRoot/(name+'.dSYM.zip')]
def run(args): return subprocess.check_output(args,stderr=subprocess.STDOUT).decode().strip()
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
 return h.hexdigest()
assets=[]
for p in files:
 with zipfile.ZipFile(p) as z:
  names=z.namelist();assert names and not any(x.startswith('/') or '..' in Path(x).parts or x=='error.log' or x.startswith('work/') or '/._' in x for x in names)
  assert all(x.startswith('CodexBar.app/') for x in names) if p==files[0] else all(x.startswith('CodexBar.dSYM/') for x in names)
 run(['/usr/bin/ditto','-x','-k',str(p),str(out)])
 assets.append({'name':p.name,'size':p.stat().st_size,'sha256':sha(p),'zipEntries':len(names)})
app=out/'CodexBar.app'; info=plistlib.loads((app/'Contents/Info.plist').read_bytes()); source=run(['git','rev-parse',info['CodexGitCommit']])
assert source==json.loads((r/'CodexBarMobile/Research/092-v083-upstream-sync/evidence/mac-draft-source-manifest.json').read_text())['sourceCommit']
assert info['CFBundleIdentifier']=='com.o1xhack.codexbar' and info['CFBundleShortVersionString']=='0.83.0.1' and info['CFBundleVersion']=='176.1.3.3.0' and info['CodexMobileVersion']=='3.3.0'
assert info['SUFeedURL']=='https://raw.githubusercontent.com/o1xhack/CodexBar-Mobile/mobile-dev/appcast.xml'
binary=app/'Contents/MacOS/CodexBar';dwarf=out/'CodexBar.dSYM/Contents/Resources/DWARF/CodexBar'
assert set(run(['lipo','-archs',str(binary)]).split())=={'arm64','x86_64'}
uuid=run(['dwarfdump','--uuid',str(binary)]);duuid=run(['dwarfdump','--uuid',str(dwarf)])
def uuid_map(x):return dict((a,b.upper()) for b,a in re.findall(r'UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)',x))
assert uuid_map(uuid)==uuid_map(duuid) and set(uuid_map(uuid))=={'arm64','x86_64'}
checks={}
for label,args in [('codesign',['codesign','--verify','--deep','--strict','--verbose=2',str(app)]),('stapler',['xcrun','stapler','validate',str(app)]),('distribution',['syspolicy_check','distribution',str(app)])]: checks[label]=run(args)
authority='Authority=Developer ID Application: Yuxiao Wang (3TUERHN53E)'
executables=[]
for label,b in [('App',binary),('CLI',app/'Contents/Helpers/CodexBarCLI'),('Watchdog',app/'Contents/Helpers/CodexBarClaudeWatchdog'),('Widget',app/'Contents/PlugIns/CodexBarWidget.appex/Contents/MacOS/CodexBarWidget')]:
 assert b.is_file(),label
 arches=run(['lipo','-archs',str(b)]).split(); assert set(arches)=={'arm64','x86_64'},label
 signature=run(['codesign','-dv','--verbose=4',str(b)]); assert 'TeamIdentifier=3TUERHN53E' in signature and authority in signature and re.search(r'flags=.*\bruntime\b',signature),label
 run(['codesign','--verify','--strict',str(b)])
 metadata=run(['xcrun','vtool','-show-build',str(b)]); minimums=re.findall(r'(?m)^\s*minos\s+(\S+)',metadata); assert len(minimums)==2 and all(x=='14.0' for x in minimums),label
 executables.append({'role':label,'path':str(b.relative_to(out)),'architectures':arches,'sha256':sha(b),'developerIDAuthorityVerified':True,'hardenedRuntime':True,'minimumOSPerArchitecture':minimums})
bundles=[]
probeHome=s/'mac-group-probe-home';probeHome.mkdir(exist_ok=True)
policy='(version 1)(allow default)(deny network*)(deny mach-lookup (global-name-regex #".*[Cc]loud.*"))(deny mach-lookup (global-name-regex #".*cfprefsd.*"))(deny file-read* (subpath "'+str(r)+'"))(deny file-read* (subpath "'+str(Path.home())+'"))(deny file-write* (subpath "'+str(Path.home())+'"))'
def group_probe(executable):
 value=run(['/usr/bin/sandbox-exec','-p',policy,'/usr/bin/env','-i','PATH=/usr/bin:/bin:/usr/sbin:/sbin','HOME='+str(probeHome),'CFFIXED_USER_HOME='+str(probeHome),'TMPDIR='+str(s/'tmp'),'SWIFT_TESTING=1','CODEXBAR_DISABLE_KEYCHAIN_ACCESS=1','CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1','CODEXBAR_RESOURCE_SMOKE=1',str(executable)])
 assert 'CODEXBAR_RESOURCE_SMOKE_OK' in value
 lines=[x for x in value.splitlines() if x.startswith('CODEXBAR_APP_GROUP_DIAGNOSTIC ')];assert len(lines)==1
 return json.loads(lines[0].split(' ',1)[1])
runtimeGroups=group_probe(binary);assert runtimeGroups['bundleID']==info['CFBundleIdentifier']
expectedGroup=runtimeGroups['runtimeGroupID'];assert expectedGroup==runtimeGroups['widgetRuntimeGroupID'] and expectedGroup.startswith('3TUERHN53E.')
cli=app/'Contents/Helpers/CodexBarCLI';cliRuntimeGroups=group_probe(cli);assert cliRuntimeGroups['runtimeGroupID']==expectedGroup
cliEnt=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(cli)],stderr=subprocess.DEVNULL));assert cliEnt['com.apple.security.application-groups']==[expectedGroup]
assert not any(k.startswith('com.apple.developer.icloud') for k in cliEnt)
checks['signedRuntimeGroupDiagnostic']=runtimeGroups;checks['signedCLIRuntimeGroupDiagnostic']=cliRuntimeGroups
for p in [app,app/'Contents/PlugIns/CodexBarWidget.appex']:
 bi=plistlib.loads((p/'Contents/Info.plist').read_bytes()); expectedBundleVersion='176.1.3.3.0' if p==app else '176.1'; assert bi['CFBundleVersion']==expectedBundleVersion and bi['CFBundleShortVersionString']=='0.83.0.1'
 ent=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(p)],stderr=subprocess.DEVNULL)); sig=run(['codesign','-dv','--verbose=4',str(p)])
 assert 'TeamIdentifier=3TUERHN53E' in sig and authority in sig and re.search(r'flags=.*\bruntime\b',sig)
 assert not ent.get('get-task-allow') and not ent.get('com.apple.security.get-task-allow')
 assert ent['com.apple.security.application-groups']==[expectedGroup]
 record={'path':str(p.relative_to(out)),'identifier':bi['CFBundleIdentifier'],'bundleVersion':bi['CFBundleVersion'],'shortVersion':bi['CFBundleShortVersionString'],'signatureTeam':'3TUERHN53E','hardenedRuntime':True,'runtimeGroup':expectedGroup,'groupAuthorization':'Team-prefixed group matches actual signing team; no profile needed for this group','groupAuthorizationReference':'https://developer.apple.com/documentation/xcode/accessing-app-group-containers'}
 profile=p/'Contents/embedded.provisionprofile'
 if p==app:
  assert ent['com.apple.developer.icloud-container-environment']=='Production' and profile.is_file()
  decoded=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(profile)],stderr=subprocess.DEVNULL));assert decoded['TeamIdentifier']==['3TUERHN53E']
  expiry=decoded['ExpirationDate'];now=datetime.datetime.now(datetime.timezone.utc);assert (expiry.replace(tzinfo=datetime.timezone.utc) if expiry.tzinfo is None else expiry)>now
  permitted=decoded['Entitlements'];actualID=ent.get('com.apple.application-identifier',ent.get('application-identifier'));permittedID=permitted.get('com.apple.application-identifier',permitted.get('application-identifier'))
  assert actualID=='3TUERHN53E.'+bi['CFBundleIdentifier'] and permittedID==actualID
  allowedEnv=permitted['com.apple.developer.icloud-container-environment'];assert allowedEnv=='Production' or isinstance(allowedEnv,list) and 'Production' in allowedEnv
  import fnmatch
  allowed=permitted['com.apple.developer.icloud-container-identifiers'];assert all(any(fnmatch.fnmatchcase(v,a) for a in allowed) for v in ent['com.apple.developer.icloud-container-identifiers'])
  record.update(environment='Production',profileSHA256=sha(profile),profileExpiration=str(expiry),profileRole='CloudKit Production')
 else:
  assert ent['com.apple.security.app-sandbox'] is True
  assert not any(k.startswith('com.apple.developer.icloud') for k in ent)
  record.update(environment='not applicable: app-group-only widget; no CloudKit calls',profileRequired=False)
 record['entitlementKeys']=sorted(ent);bundles.append(record)
for f in json.loads((r/'CodexBarMobile/Research/092-v083-upstream-sync/evidence/mac-draft-source-manifest.json').read_text())['inputs']:
 p=r/f['path']; assert sha(p)==f['sha256'] if not f['symlink'] else hashlib.sha256(os.readlink(p).encode()).hexdigest()==f['sha256']
proof={'verifiedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceCommit':source,'artifactSourceShort':info['CodexGitCommit'],'currentHead':run(['git','rev-parse','HEAD']),'appVersion':info['CFBundleShortVersionString'],'sparkleVersion':info['CFBundleVersion'],'mobileVersion':info['CodexMobileVersion'],'feedURL':info['SUFeedURL'],'buildTimestamp':info['CodexBuildTimestamp'],'appBinarySHA256':sha(binary),'dSYMSHA256':sha(dwarf),'architectureUUIDs':uuid_map(uuid),'assets':assets,'bundles':bundles,'executables':executables,'checks':checks,'allInputHashesMatch':True,'published':False}
(s/'mac-artifacts-verified.json').write_text(json.dumps(proof,indent=2)+'\n')
print(json.dumps({k:proof[k] for k in ['sourceCommit','appVersion','sparkleVersion','architectureUUIDs','allInputHashesMatch']}))
