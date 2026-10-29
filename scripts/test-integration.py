#!/usr/bin/env python3
import pathlib,tempfile,subprocess,os,json
base=pathlib.Path(__file__).resolve().parents[1]
root=pathlib.Path(tempfile.mkdtemp(prefix='TinyEditor-integration-',dir='/tmp'))
report=base/'docs/integration-results.json'
env=os.environ.copy();env.update(TINYEDITOR_DATA_DIR=str(root),TINYEDITOR_INTEGRATION_REPORT=str(report))
with (root/'application.log').open('w') as log:
 process=subprocess.Popen([str(base/'artifacts/TinyEditor.app/Contents/MacOS/TinyEditor')],env=env,stdout=log,stderr=log)
 try: code=process.wait(timeout=60)
 except subprocess.TimeoutExpired:
  process.terminate();process.wait(timeout=10)
  raise RuntimeError('Isolated integration process did not quit within 60 seconds; no user documents were involved.')
result=json.loads(report.read_text());result.update(exitCode=code,normalExit=(code==0))
report.write_text(json.dumps(result,ensure_ascii=False,indent=2))
print('Integration:',len(result['results']),'checks; passed:',result.get('passed'),'normal exit:',code)
if code!=0 or not result.get('passed'):raise SystemExit(1)
