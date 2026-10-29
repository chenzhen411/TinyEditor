#!/usr/bin/env python3
import json,os,subprocess,tempfile,time,pathlib
base=pathlib.Path(__file__).resolve().parents[1]
app=base/'artifacts/TinyEditor.app/Contents/MacOS/TinyEditor'
root=pathlib.Path(tempfile.mkdtemp(prefix='TinyEditor-launch-',dir='/tmp'))
md=root/'sample.md';md.write_text('# TinyEditor\n\n**离线预览**\n\n```mermaid\ngraph LR\n A[原文] --> B[预览]\n```\n\n$E=mc^2$\n')
def helpers():
 lines=subprocess.check_output(['ps','-axo','pid=,rss=,comm='],text=True).splitlines();out={}
 for line in lines:
  parts=line.strip().split(None,2)
  if len(parts)==3 and 'com.apple.WebKit.' in parts[2]:out[int(parts[0])]={'rssMiB':int(parts[1])/1024,'executable':parts[2]}
 return out
runs=[]
for kind in ['blank','blank','blank','markdown']:
 report=root/f'{kind}-{len(runs)}.json';env=os.environ.copy();env.update(TINYEDITOR_DATA_DIR=str(root/'data'),TINYEDITOR_LAUNCH_REPORT=str(report))
 old=helpers();start=time.perf_counter();process=subprocess.Popen([str(app)]+([str(md)] if kind=='markdown' else []),env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 while not report.exists() and time.perf_counter()-start<20 and process.poll() is None:time.sleep(.005)
 if not report.exists():raise RuntimeError('Launch probe did not complete')
 elapsed=(time.perf_counter()-start)*1000;result=json.loads(report.read_text());new=helpers();result.update(kind=kind,spawnToReadyObservedMs=elapsed,newWebKitProcesses={str(pid):data for pid,data in new.items() if pid not in old})
 process.wait(timeout=15);runs.append(result)
output={'method':'Fresh GUI process; filesystem and system caches NOT purged. mainToWindow excludes dyld before main; spawnToReadyObserved includes process creation, rendering and up to 5ms polling. RSS is resident memory, includes shared pages, not private footprint. Helper processes identified as new WebKit PIDs during each sample.','runs':runs}
(base/'docs/launch-results.json').write_text(json.dumps(output,ensure_ascii=False,indent=2))
print(json.dumps(output,ensure_ascii=False,indent=2))
