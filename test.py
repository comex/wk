import json, random, curses, subprocess, os
from itertools import groupby
os.environ['ZDOTDIR'] = '/dev/null'

LEVEL_MAX = 34

def red(x):
    return '\x1b[31;1m'+x+'\x1b[0m'
def blue(x):
    return '\x1b[34;1m'+x+'\x1b[0m'

def read_kana():
    return subprocess.check_output(['./read-kana.zsh']).strip().decode('utf-8')

def print_word(oword):
    print oword['character'], u', '.join(oword['kana']), u', '.join(oword['meaning'])

def vocab_quiz(vocab):
    word = random.choice(vocab)
    print u', '.join(word['meaning'])
    k = read_kana()
    right = k in word['kana']
    print ('NOPE', 'YEP')[right], red(word['character']), blue(u', '.join(word['kana']))
    others = all_by_kana.get(k, [])[:]
    try:
        others.remove(word)
    except ValueError: pass
    if others:
        print 'Others:'
        for oword in others:
            print_word(oword)
    similar = set(oword['character'] for meaning in word['meaning'] for oword in all_by_meaning[meaning])
    similar.remove(word['character'])
    if similar:
        print 'Similar:'
        for ochar in similar:
            print_word(all_by_character[ochar])

def read_it():
    global all_vocab, all_by_kana, all_by_meaning, all_by_character
    vocab = json.load(open('vocabulary.json'))
    for word in vocab:
        word['kana'] = word['kana'].split(', ')
        word['meaning'] = word['meaning'].split(', ')
    all_vocab = filter(lambda v: v['level'] <= LEVEL_MAX, vocab)
    all_by_kana = {}
    all_by_character = {}
    all_by_meaning = {}
    for word in all_vocab:
        all_by_character[word['character']] = word
        for kana in word['kana']: 
            all_by_kana.setdefault(kana, []).append(word)
        for meaning in word['meaning']: 
            all_by_meaning.setdefault(meaning, []).append(word)

read_it()
vocab_quiz(all_vocab)
