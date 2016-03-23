# -*- coding: utf-8 -*-

import json, random, curses, subprocess, os, unicodedata, re, math
import readline
from itertools import groupby
import distance
os.environ['ZDOTDIR'] = '/dev/null'

def red(x):
    return '\x1b[31;1m'+x+'\x1b[0m'
def green(x):
    return '\x1b[32;1m'+x+'\x1b[0m'
def blue(x):
    return '\x1b[34;1m'+x+'\x1b[0m'
def yback(x):
    return '\x1b[43m'+x+'\x1b[0m'
def rback(x):
    return '\x1b[41m'+x+'\x1b[0m'
NOPE = rback('NOPE')
YEP = yback('YEP')
READING_PROMPT = red('reading> ')
MEANING_PROMPT = blue('meaning> ')

def read_kana(prompt='> '):
    return subprocess.check_output(['./read-kana.zsh', prompt]).strip().decode('utf-8')

def read_eng(prompt='> '):
    while True:
        r = raw_input(prompt)
        try:
            r = r.decode('utf-8')
        except e:
            print '!encoding', e
            continue
        if any(unicodedata.east_asian_width(c) == 'W' for c in r):
            print '(do you somehow have an IME up?)'
            continue
        return r.strip()

class Word:
    def __init__(self, props):
        self.__dict__.update(props)
        self.kana = self.kana.split(', ')
        self.meaning = self.meaning.split(', ')
        if self.user_specific:
            self.srs_numeric = self.user_specific['srs_numeric']
        else:
            self.srs_numeric = 0

    def print_(self):
        print '  ', self.character, u', '.join(self.kana), u', '.join(self.meaning)

    def __cmp__(self, other):
        return cmp(self.character, other.character)

    def __hash__(self):
        return hash(self.character)

    def meaning_answer_qual(self, entered):
        qual = 0
        for meaning in word.meaning:
            meaning = normalize(meaning)
            # arbitrary
            ok_dist = round(0.4*len(meaning))
            dist = distance.levenshtein(entered, meaning)
            qual = max(qual, 2 if dist == 0 else 1 if dist <= ok_dist else 0)
        return qual

    def print_reading_alternatives(self, k):
        others = word_list.by_kana.get(k, [])[:]
        if self in others: others.remove(self)
        if others:
            print ' Entered kana matches:'
            for oword in others:
                oword.print_()
        similar = set(oword for meaning in self.meaning for oword in word_list.by_meaning[meaning])
        similar.remove(self)
        if similar:
            print ' Similar meaning:'
            for oword in similar:
                oword.print_()

class WordList:
    def __init__(self, list):
        self.list = list
        self.by_character = {word.character: word for word in list}
        self.by_kana = {}
        self.by_meaning = {}
        for word in list:
            for x in ('kana', 'meaning'):
                for thing in getattr(word, x):
                    getattr(self, 'by_'+x).setdefault(thing, []).append(word)
    def random(self):
        return random.choice(self.list)

def normalize(e):
    return re.sub('[^a-z0-9]', '', e.lower())

def meaning_to_reading(word):
    meaning = u', '.join(word.meaning)
    if word.character.startswith(u'〜'):
        meaning = u'(〜) ' + meaning
    while True:
        print meaning
        k = read_kana()
        if k: break
    right = k in word.kana
    print (NOPE, YEP)[right], green(word.character), red(u', '.join(word.kana))
    word.print_reading_alternatives(k)
    return right

def reading_to_meaning(oword):
    print u', '.join(oword.kana)
    words = sorted(set(w for k in oword.kana for w in word_list.by_kana[k]))
    e = read_eng()
    ok = (0, 0)
    en = normalize(e)
    for word in words:
        word_qual = (1, 2)[set(oword.kana) == set(word.kana)]
        answer_qual = word.meaning_answer_qual(en)
        if answer_qual:
            ok = max(ok, (word_qual, answer_qual))
    print (NOPE, YEP+'?', YEP)[ok[1]] + (' [for one]' if ok[0] == 1 else '')
    for i, word in enumerate(words):
        if len(words) > 1:
            print '%d.' % i,
        print green(word.character), blue(u', '.join(word.meaning))
    return ok > (0, 0)

def character_to_rm(word):
    print word.character
    imperfect = False
    def meaning():
        while True:
            entered_meaning = normalize(read_eng(MEANING_PROMPT))
            qual = word.meaning_answer_qual(entered_meaning)
            print (NOPE, YEP+'?', YEP)[qual], blue(u', '.join(word.meaning))
            if qual >= 1:
                return
            else:
                imperfect = True
    def reading():
        entered_reading = read_kana(READING_PROMPT)
        ok = entered_reading in word.kana
        print (NOPE, YEP)[ok], red(u', '.join(word.kana))
        if ok:
            return
        else:
            word.print_reading_alternatives(entered_reading)
            imperfect = True

    ops = [meaning, reading]
    random.shuffle(ops)
    for op in ops: op()
    return not imperfect

x_words = map(Word, json.load(open('vocabulary.json')))
x_words = filter(lambda word: word.srs_numeric >= 9, x_words)
word_list = WordList(x_words)
include_straight = True

done = 0
while True:
    print '[%d]' % done
    word = word_list.random()
    ops = [meaning_to_reading, reading_to_meaning]
    if include_straight:
        ops.append(character_to_rm)
    random.choice(ops)(word)
    done += 1
    print
    #print
