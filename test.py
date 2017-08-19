# -*- coding: utf-8 -*-
# TODO have all forms require entering it right after wrong
# and change YEP to not be green
'''
and wtf is this

reading> はねい
NOPE はんけい
reading> !right
reading> はんけい
YEP? はんけい

it doesnt leave a log at all
'''

import json, random, curses, subprocess, os, unicodedata, re, math, sys, codecs
import readline
from itertools import groupby
import distance
os.environ['ZDOTDIR'] = '/dev/null'

os.chdir(os.path.dirname(os.path.abspath(sys.argv[0])))
logfile = open('log.txt', 'r+b')

#sys.stdout = codecs.getwriter("utf-8")(sys.stdout) <-- THIS BREAKS IT

def red(x):
    return '\x1b[31;1m'+x+'\x1b[0m'
def dred(x):
    return '\x1b[31m'+x+'\x1b[0m'
def green(x):
    return '\x1b[32;1m'+x+'\x1b[0m'
def blue(x):
    return '\x1b[34;1m'+x+'\x1b[0m'
def purple(x):
    return '\x1b[35;1m'+x+'\x1b[0m'
def yback(x):
    return '\x1b[43m'+x+'\x1b[0m'
def rback(x):
    return '\x1b[41m'+x+'\x1b[0m'
NOPE = rback('NOPE')
YEP_real = yback('YEP')
YEP_wrong = rback('YEP')
READING_PROMPT = red('reading> ')
MEANING_PROMPT = blue('meaning> ')

def read_kana(prompt='> '):
    while True:
        try:
            text = subprocess.check_output(['./read-kana.zsh', prompt]).strip().decode('utf-8')
        except subprocess.CalledProcessError:
            raise EOFError
        if not text:
            continue
        if text.startswith('!'):
            handle_bang(text)
            continue
        return text

def read_eng(prompt='> '):
    while True:
        # xxx no backspace?
        r = raw_input(prompt)
        try:
            r = r.decode('utf-8')
        except e:
            print '!encoding', e
            continue
        if r.startswith('!'):
            handle_bang(r)
            continue
        if not r:
            continue
        if any(unicodedata.east_asian_width(c) == 'W' for c in r):
            print '(do you somehow have an IME up?)'
            continue
        return r.strip()

class Item:
    def __init__(self, props):
        self.__dict__.update(props)
        if self.user_specific:
            self.srs_numeric = self.user_specific['srs_numeric']
        else:
            self.srs_numeric = 0

    def __cmp__(self, other):
        return cmp(self.character, other.character)

    def __hash__(self):
        return hash(self.character)

    def print_reading_alternatives(self, k):
        others = self.this_type_list.by_kana.get(k, [])[:]
        if self in others: others.remove(self)
        if others:
            print ' Entered kana matches:'
            for oword in others:
                oword.print_()

    def print_meaning_alternatives(self, k):
        others = self.this_type_list.by_meaning.get(k, [])[:]
        if self in others: others.remove(self)
        if others:
            print ' Entered meaning matches:'
            for oword in others:
                oword.print_()

    def print_similar_meaning(self):
        similar = set(oword for meaning in self.meaning for oword in self.this_type_list.by_meaning[meaning])
        similar.remove(self)
        if similar:
            print ' Similar meaning:'
            for oword in similar:
                oword.print_()

    def meaning_answer_qual(self, entered):
        qual = 0
        for meaning in self.meaning:
            meaning = normalize(meaning)
            # arbitrary
            ok_dist = round(0.4*len(meaning))
            dist = distance.levenshtein(entered, meaning)
            qual = max(qual, 2 if dist == 0 else 1 if dist <= ok_dist else 0)
        return qual

class Word(Item):
    def __init__(self, props):
        Item.__init__(self, props)
        self.kana = self.kana.split(', ')
        self.meaning = self.meaning.split(', ')

    @property
    def this_type_list(self):
        return word_list

    def print_(self):
        print '  ', self.character, u', '.join(self.kana), u', '.join(self.meaning)

    def ansi_character(self):
        return self.character

    def reading_answer_qual(self, answer):
        return 1 if answer in self.kana else 0

class Kanji(Item):
    def __init__(self, props):
        Item.__init__(self, props)
        for a in ['kunyomi', 'onyomi', 'nanori']:
            setattr(self, a, props[a].split(', ') if props[a] and props[a] != 'None' else [])
        self.all_kana = self.kunyomi + self.onyomi + self.nanori
        self.unimportant_kana = self.kunyomi if self.important_reading == 'onyomi' else self.onyomi
        self.kana = getattr(self, self.important_reading)
        self.meaning = self.meaning.split(', ')

    @property
    def this_type_list(self):
        return kanji_list

    def print_(self):
        print '  ', purple(self.character), u', '.join(self.kana), u', '.join(self.meaning)

    def ansi_character(self):
        return purple(self.character) + ' /k'

    def reading_answer_qual(self, answer):
        def fits(k):
            return re.sub('\..*', '', k) == answer
        return 2 if any(map(fits, self.kana)) else \
               1 if any(map(fits, self.all_kana)) else \
               0

class ItemList:
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

class Test:
    def __init__(self, kind, item):
        self.wrong_line, self.right_line = (u'%s:%s:%s:%s\n' % (kind, item.__class__.__name__.lower(), item.character, result) for result in ('wrong', 'right'))
        self.kind = kind
        self.item = item
        self.unwrong()

    def run(self):
        global cur_test
        cur_test = self
        self.KINDS[self.kind](self, self.item)
        del cur_test
        if last_appended_test is not self:
            assert not self.was_wrong
            append_line(self.right_line)
        return not self.was_wrong

    def set_wrong(self, wrong):
        if self.was_wrong == wrong:
            return
        self.was_wrong = wrong
        self.YEP = YEP_wrong if wrong else YEP_real
        if last_appended_test is self:
            change_last_line(self.wrong_line if wrong else self.right_line)
        elif wrong:
            append_line(self.wrong_line)
        global last_appended_test
        last_appended_test = self

    def unwrong(self):
        self.YEP = YEP_real
        self.was_wrong = False

    def meaning_to_reading(self, word):
        meaning = u', '.join(word.meaning)
        if word.character.startswith(u'〜'):
            meaning = u'(〜) ' + meaning
        if isinstance(word, Kanji):
            meaning = purple(meaning) + ' /k'
        while True:
            print meaning
            k = read_kana()
            right = word.reading_answer_qual(k)
            print (NOPE, self.YEP+'?', self.YEP)[right], green(word.character), red(u', '.join(word.kana))
            word.print_reading_alternatives(k)
            word.print_similar_meaning()
            if right > 0:
                return
            else:
                self.wrong()

    def reading_to_meaning(self, oword):
        while True:
            print u', '.join(oword.kana)
            words = sorted(set(w for k in oword.kana for w in oword.this_type_list.by_kana[k]))
            e = read_eng()
            ok = (0, 0)
            en = normalize(e)
            for word in words:
                word_qual = (1, 2)[set(oword.kana) == set(word.kana)]
                answer_qual = word.meaning_answer_qual(en)
                if answer_qual:
                    ok = max(ok, (word_qual, answer_qual))
            print (NOPE, self.YEP+'?', self.YEP)[ok[1]] + (' [for one]' if ok[0] == 1 else '')
            for i, word in enumerate(words):
                if len(words) > 1:
                    print '%d.' % i,
                print green(word.character), blue(u', '.join(word.meaning))
            if ok > (0, 0):
                return
            else:
                self.wrong()

    def character_to_rm(self, word):
        print word.ansi_character()
        imperfect = False
        # todo combine the two?
        def meaning():
            while True:
                entered_meaning = normalize(read_eng(MEANING_PROMPT))
                qual = word.meaning_answer_qual(entered_meaning)
                print (NOPE, self.YEP+'?', self.YEP)[qual], blue(u', '.join(word.meaning))
                if qual > 0:
                    return
                else:
                    word.print_meaning_alternatives(entered_meaning)
                    self.wrong()
        def reading():
            while True:
                entered_reading = read_kana(READING_PROMPT)
                qual = word.reading_answer_qual(entered_reading)
                print (NOPE, self.YEP+'?', self.YEP)[qual], red(u', '.join(word.kana)),
                if isinstance(word, Kanji) and word.unimportant_kana:
                    print '>>', dred(u', '.join(word.unimportant_kana)),
                print
                if qual > 0:
                    return
                else:
                    word.print_reading_alternatives(entered_reading)
                    #word.print_similar_meaning()
                    self.wrong()

        ops = [meaning, reading]
        random.shuffle(ops)
        for op in ops: op()
    KINDS = {'m2r': meaning_to_reading, 'r2m': reading_to_meaning, 'c2': character_to_rm}


last_line = None
def change_last_line(line):
    global last_line
    assert line.endswith('\n')
    assert last_line is not None
    logfile.seek(-len(last_line.encode('utf-8')), 2)
    pos = logfile.tell()
    test = logfile.read() 
    assert test == last_line.encode('utf-8')
    logfile.seek(pos)
    logfile.truncate()
    logfile.write(line.encode('utf-8'))
    last_line = line

def append_line(line):
    global last_line
    assert line.endswith('\n')
    logfile.seek(0, 2)
    logfile.write(line.encode('utf-8'))
    last_line = line

def handle_bang(bang):
    bang = bang.strip()
    if bang in ('!wrong', '!right'):
        if last_line is None or not re.search(':(wrong|right)\n$', last_line):
            print 'no last %r' % (last_line,)
            return
        new = re.sub(':[^:]*\n$', ':'+bang[1:]+'\n', last_line)
        if new != last_line:
            global done_right
            done_right += (1 if bang == '!right' else -1)
            change_last_line(new)
        if bang == '!right' and cur_test.was_wrong:
            cur_test.unwrong()
        return
    if bang in ('!pcton', '!pctoff'):
        global pcton
        pcton = bang == '!pcton'
        return
    print '?bang?'

word_list = ItemList(map(Word, json.load(open('vocabulary.json'))))
kanji_list = ItemList(map(Kanji, json.load(open('kanji.json'))))
all_items = word_list.list + kanji_list.list

pcton = True

last_appended_test = None

if __name__ == '__main__':
    kanji_ops = []#meaning_to_reading, character_to_rm]
    word_ops = ['m2r']#['r2m', 'm2r', 'c2']
    item_filter = lambda word: word.srs_numeric >= 9
    filtered_items = (word_list.list if word_ops else []) + \
                     (kanji_list.list if kanji_ops else [])
    filtered_items = filter(item_filter, filtered_items)

    done = 0
    done_right = 0
    while True:
        pctstuff = ''
        if pcton and done > 0:
            pctstuff = ' %d/%d=%.0f' % (done_right, done, done_right * 100.0 / done)
        print '[%d]%s' % (done, pctstuff)
        #item = kanji_list.random()
        item = random.choice(filtered_items)
        ops = word_ops if isinstance(item, Word) else kanji_ops
        try:
            right = Test(random.choice(ops), item).run()
        except EOFError:
            break
        done += 1
        if right: done_right += 1

        print
        #print
