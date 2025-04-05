#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ['requests']
# ///
import requests, json
s = requests.Session()
s.headers['Wanikani-Revision'] = '20170710'
s.headers['Authorization'] = 'Bearer ' + open('wk-api-key.txt').read().strip()

def fetch_paginated(url):
    data = []
    while url:
        print(url)
        stuff = s.get(url).json()
        data += stuff['data']
        url = stuff['pages']['next_url']
    return data

def dump(stuff, path):
    with open(path, 'w') as fp:
        json.dump(stuff, fp, indent='    ')
def do_study_materials():
    data = fetch_paginated('https://api.wanikani.com/v2/study_materials')
    dump(data, 'study_materials.json')
def do_subjects():
    data = fetch_paginated('https://api.wanikani.com/v2/subjects')
    by_kind = {}
    for item in data:
        by_kind.setdefault(item['object'], []).append(item)

    #open('tmp.json', 'w').write(json.dumps(by_kind))

    assert set(by_kind.keys()) == {'radical', 'kanji', 'vocabulary', 'kana_vocabulary'}
    for kind, items in by_kind.items():
        dump(items, f'{kind}.json')

do_study_materials()
do_subjects()
