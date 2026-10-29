#!/usr/bin/env python3
"""Check recorded real CGEvent/AppKit evidence; this script does not perform input."""
import json
import pathlib

base = pathlib.Path(__file__).resolve().parents[1]
folder = base / 'docs/evidence'
read = lambda name: json.loads((folder / ('1.0.2-' + name + '.json')).read_text())
baseline = read('baseline')
original = next(d for w in baseline['windows'] for d in w['documents'] if d['name'] == 'source.txt')
preview = next(d for w in baseline['windows'] for d in w['documents'] if d['name'] == 'preview.md')
cases = ['01-preview', '02-detach', '03-single-to-multi-editor', '04-preview-detach',
         '05-multi-to-single-preview', '06-editor-repeat', '08-multi-to-multi',
         '09-detach-third', '10-toolbar', '11-sidebar-before', '12-sidebar-drop',
         '13-status-drop', '14-escape-outside', '15-escape-preview-before',
         '16-escape-preview', '17-reorder']
results = []

def check(name, value):
    results.append({'name': name, 'passed': bool(value)})
    if not value:
        raise AssertionError(name)

def owner(state, identifier):
    return next(w for w in state['windows'] if any(d['id'] == identifier for d in w['documents']))

for case in cases:
    state = read(case)
    documents = [d for w in state['windows'] for d in w['documents']]
    source = next(d for d in documents if d['id'] == original['id'])
    md = next(d for d in documents if d['id'] == preview['id'])
    check(case + ': source identity/text/dirty/undo/format/selection', source == original)
    check(case + ': markdown source and preview context', md == preview)
    check(case + ': tracking cleaned', not state['dragActive'])

check('single to single over preview', len(read('01-preview')['windows']) == 1
      and len(owner(read('01-preview'), original['id'])['documents']) == 2)
check('single to multi over editor', len(read('03-single-to-multi-editor')['windows']) == 1
      and len(owner(read('03-single-to-multi-editor'), original['id'])['documents']) == 3)
check('multi to single over preview', len(read('05-multi-to-single-preview')['windows']) == 2
      and len(owner(read('05-multi-to-single-preview'), original['id'])['documents']) == 2)
check('multi to multi', len(owner(read('08-multi-to-multi'), original['id'])['documents']) == 3)
check('second-tab detach', len(read('02-detach')['windows']) == 2
      and len(owner(read('02-detach'), original['id'])['documents']) == 1)
check('third-tab detach', len(read('09-detach-third')['windows']) == 3
      and len(owner(read('09-detach-third'), original['id'])['documents']) == 1)
check('sidebar target received', owner(read('12-sidebar-drop'), original['id'])['sidebar'])
check('status target received independently', not owner(read('13-status-drop'), original['id'])['sidebar']
      and any(w['sidebar'] for w in read('13-status-drop')['windows']))
check('escape outside preserves complete window state', read('13-status-drop')['windows']
      == read('14-escape-outside')['windows'])
check('escape over preview preserves complete window state', read('15-escape-preview-before')['windows']
      == read('16-escape-preview')['windows'])
check('tab reordered to first position', owner(read('17-reorder'), original['id'])['documents'][0]['id']
      == original['id'])
log = (folder / '1.0.2-real-drag.log').read_text()
for zone in ['preview', 'editor', 'toolbar', 'sidebar', 'status', 'tabs']:
    check('AppKit accepted zone ' + zone, 'drop zone=' + zone in log)
check('two native Escape endings', log.count('accepted=false escape=true') >= 2)
final_before = read('final-before')
final_source = next(d for w in final_before['windows'] for d in w['documents'] if d['name'] == 'source.txt')
def final_doc(case):
    return next(d for w in read(case)['windows'] for d in w['documents'] if d['id'] == final_source['id'])
check('final manual JSON overrides txt', final_source['format'] == 'json' and final_source['dirty'])
check('final preview drop preserves complete document', final_doc('final-preview-drop') == final_source)
undone = final_doc('final-undo')
check('real undo after transfer restores clean content', not undone['dirty'] and undone['canRedo']
      and undone['text'] != final_source['text'])
check('real redo restores modified original', final_doc('final-redo') == final_source)
created = read('final-third-created')['windows'][0]['documents']
closed = read('final-third-closed')['windows'][0]['documents']
check('third close removes exactly third ID', len(created) == 3
      and [d['id'] for d in closed] == [d['id'] for d in created[:2]])
check('second close cancellation preserves source', final_doc('final-controls') == final_source)
check('final sidebar click opens', read('final-controls')['windows'][0]['sidebar'])
check('final Escape preserves all state', read('final-controls')['windows'] == read('final-escape')['windows']
      and not read('final-escape')['dragActive'])
revoked = read('driver-revoked')
check('temporary driver access revoked', not revoked['trusted'] and not revoked['postAccess'])
report = {'input': 'Real CGEvent input from user-authorized temporary driver; AppKit callbacks and fixture snapshots',
          'passed': True, 'checks': len(results), 'results': results}
(base / 'docs/real-drag-results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print('Real drag evidence:', len(results), 'checks passed')
