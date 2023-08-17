#!/usr/bin/env python3
import requests, json
s = requests.Session()
s.headers['Wanikani-Revision'] = '20170710'
s.headers['Authorization'] = 'Bearer a2344c7b-6d09-4aca-bd14-1945105c35b4'
url = 'https://api.wanikani.com/v2/subjects'
data = []
while url:
    print(url)
    stuff = s.get(url).json()
    data += stuff['data']
    url = stuff['pages']['next_url']
by_kind = {}
for item in data:
    by_kind.setdefault(item['object'], []).append(item)

#open('tmp.json', 'w').write(json.dumps(by_kind))

assert set(by_kind.keys()) == {'radical', 'kanji', 'vocabulary', 'kana_vocabulary'}
for kind, items in by_kind.items():
    with open(f'{kind}.json', 'w') as fp:
        json.dump(items, fp, indent='    ')
