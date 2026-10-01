import json
import pathlib
import re
import struct

base = pathlib.Path(r'C:\Program Files (x86)\ASUS\ArmouryDevice')
out = pathlib.Path(__file__).parent / 'rog-h2004-evidence' / '09-code-evidence.json'
results = []

for path in [base / 'View' / '6802' / 'service.js', base / 'View' / '7038' / 'service.js']:
    if not path.exists():
        continue
    data = path.read_text(encoding='utf-8', errors='replace')
    for term in ('F-1034', 'H-2004', 'initializeAlertPage', 'initialLoadingAlertPage'):
        for match in list(re.finditer(re.escape(term), data))[:3]:
            results.append({'file': str(path), 'term': term, 'offset': match.start(), 'excerpt': data[max(0, match.start()-180):match.end()+280]})

archive = base / 'resources' / 'app.asar'
if archive.exists():
    with archive.open('rb') as handle:
        prefix = handle.read(16)
        _, header_size, _, json_size = struct.unpack('<4I', prefix)
        tree = json.loads(handle.read(json_size))
        data_offset = 8 + header_size

        def visit(node, path=''):
            for name, item in node.get('files', {}).items():
                entry = path + '/' + name
                if 'files' in item:
                    visit(item, entry)
                elif name.endswith(('.js', '.json')) and not item.get('unpacked') and 'offset' in item and item['size'] <= 12000000:
                    handle.seek(data_offset + int(item['offset']))
                    text = handle.read(item['size']).decode('utf-8', errors='replace')
                    for term in ('Rejected request from untrusted process', 'F-1034', 'trusted process'):
                        for match in list(re.finditer(re.escape(term), text))[:2]:
                            results.append({'file': str(archive) + ':' + entry, 'term': term, 'offset': match.start(), 'excerpt': text[max(0, match.start()-200):match.end()+350]})

        visit(tree)

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'output': str(out), 'matches': len(results)}, ensure_ascii=False))
