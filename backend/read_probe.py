import json

data = json.load(open('audio_probe_results.json', encoding='utf-8'))
for r in data:
    status = r.get('status', '?')
    ok_str = 'OK' if r.get('ok') else 'FAIL'
    body = r.get('body', '')
    body_str = json.dumps(body)[:140] if isinstance(body, (dict,list)) else str(body)[:140]
    print(f'[{ok_str}] [{status}] {r["label"]}')
    print(f'      => {body_str}')
