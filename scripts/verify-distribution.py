#!/usr/bin/env python3
import pathlib,subprocess,json,tempfile,hashlib,re,zipfile,os,plistlib
base=pathlib.Path(__file__).resolve().parents[1]
archive=base/'artifacts/TinyEditor-macOS-arm64.zip'
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 names=z.namelist();assert names and all(n.startswith('TinyEditor.app/') for n in names)
 assert not any('InputCheck' in n or 'cg-input' in n for n in names)
 target=pathlib.Path(tempfile.mkdtemp(prefix='TinyEditor-zip-',dir='/tmp'));z.extractall(target)
app=target/'TinyEditor.app'
# Python extraction does not preserve executable bits; restore the archived POSIX mode.
with zipfile.ZipFile(archive) as z:
 for item in z.infolist():
  mode=(item.external_attr>>16)&0o777
  if mode:os.chmod(target/item.filename,mode)
exe=app/'Contents/MacOS/TinyEditor'
def run(args):
 p=subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);assert p.returncode==0,p.stdout;return p.stdout.strip()
sign=run(['codesign','--verify','--deep','--strict','--verbose=2',str(app)])
identity=run(['codesign','--display','--verbose=4',str(app)])
arch=run(['lipo','-archs',str(exe)])
build=run(['xcrun','vtool','-show-build',str(exe)])
assert arch=='arm64';assert re.search(r'minos\s+13\.0',build)
preview=app/'Contents/Resources/Preview';html=(preview/'index.html').read_text()
for path in re.findall(r'(?:src|href)="([^"]+)"',html):assert (preview/path).is_file(),path
for path in re.findall(r'url\(([^)]+)\)',(preview/'katex.min.css').read_text()):
 if not path.startswith('data:'):assert (preview/path.strip('\'"')).is_file(),path
assert (app/'Contents/Resources/TinyEditor.icns').is_file()
assert (app/'Contents/Resources/THIRD_PARTY_NOTICES.md').stat().st_size>10000
files={str(p.relative_to(app)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(app.rglob('*')) if p.is_file()}
metadata=plistlib.loads((app/'Contents/Info.plist').read_bytes())
result={'version':metadata['CFBundleShortVersionString'],'build':metadata['CFBundleVersion'],'architecture':arch,'minimumSystemVerified':'13.0','signature':'ad hoc','notarized':False,'zipIntegrity':True,'zipSHA256':hashlib.sha256(archive.read_bytes()).hexdigest(),'zipBytes':archive.stat().st_size,'appFileBytes':sum(p.stat().st_size for p in app.rglob('*') if p.is_file()),'resourceLinksComplete':True,'codeSignatureVerification':sign,'codeSignatureIdentity':identity,'buildVersion':build,'files':files}
result['inputDriverExcluded']=True
(base/'docs/distribution-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
(base/'artifacts/SHA256SUMS.txt').write_text(result['zipSHA256']+'  TinyEditor-macOS-arm64.zip\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['files','codeSignatureIdentity','buildVersion']},ensure_ascii=False,indent=2))
