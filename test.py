#!/usr/local/bin/python2
# -*- coding: utf-8 -*-

import json, random, curses, subprocess, os, unicodedata, re, math, sys, codecs, time, codecs, fcntl
import readline
from itertools import groupby
import distance
import ujson as json
os.environ['ZDOTDIR'] = '/dev/null'

os.chdir(os.path.dirname(os.path.abspath(sys.argv[0])))
logfile = codecs.open('log.txt', 'r+', encoding='utf-8')
fcntl.flock(logfile.stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

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

def read_kana(pre, prompt='> '):
    while True:
        print pre
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

def read_eng(pre, prompt='> '):
    while True:
        print pre
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
        self.character = self.character.strip()
        if self.user_specific:
            self.srs_numeric = self.user_specific['srs_numeric']
        else:
            self.srs_numeric = 0
        self.old_tests = []

    def __cmp__(self, other):
        return cmp(self.character, other.character)

    def __hash__(self):
        return hash(self.character)

    def print_reading_alternatives(self, k):
        others = self.list.by_kana.get(k, [])[:]
        if self in others: others.remove(self)
        if others:
            print ' Entered kana matches:'
            for oword in others:
                oword.print_()

    def print_meaning_alternatives(self, k):
        others = self.list.by_meaning.get(k, [])[:]
        if self in others: others.remove(self)
        if others:
            print ' Entered meaning matches:'
            for oword in others:
                oword.print_()

    def print_similar_meaning(self):
        similar = set(oword for meaning in self.meaning for oword in self.list.by_meaning[meaning])
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

    def print_(self):
        print '  ', self.character, u', '.join(self.kana), u', '.join(self.meaning)

    def ansi_character(self):
        return self.character

    def reading_answer_qual(self, answer):
        return 2 if answer in self.kana else 0

class Kanji(Item):
    def __init__(self, props):
        Item.__init__(self, props)
        for a in ['kunyomi', 'onyomi', 'nanori']:
            prop = props[a]
            setattr(self, a, [x.strip() for x in props[a].split(', ')] if prop and prop.strip() and prop != 'None' else [])
        self.all_kana = self.kunyomi + self.onyomi + self.nanori
        self.unimportant_kana = self.kunyomi if self.important_reading == 'onyomi' else self.onyomi
        self.kana = getattr(self, self.important_reading)
        self.meaning = self.meaning.split(', ')

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
        self.time = int(time.time())
        self.kind = kind
        self.item = item
        self.old_tests_idx = len(item.old_tests)
        item.old_tests.append(None)
        self.set_wrong(False)

    def run(self):
        global cur_test
        cur_test = self
        self.KINDS[self.kind](self, self.item)
        del cur_test
        if last_appended_test is not self:
            self.set_wrong(self.was_wrong, force_append=True)
        return not self.was_wrong

    def set_wrong(self, wrong, force_append=False):
        self.was_wrong = wrong
        self.YEP = YEP_wrong if wrong else YEP_real
        result = 'wrong' if wrong else 'right'
        data = {'time': int(time.time()), 'kind': self.kind, 'item': self.item, 'result': result}
        line = u'%s:%s:%s:%s:%s\n' % (self.time, self.kind, self.item.__class__.__name__.lower(), self.item.character, result)
        if last_appended_test is self:
            change_last_line(line)
            self.item.old_tests[-1] = data
        elif wrong or force_append:
            append_line(line)
            set_last_appended_test(self)
            self.item.old_tests.append(data)

    def meaning_to_reading(self, word):
        meaning = u', '.join(word.meaning)
        if word.character.startswith(u'〜'):
            meaning = u'(〜) ' + meaning
        if isinstance(word, Kanji):
            meaning = purple(meaning) + ' /k'
        while True:
            k = read_kana(meaning)
            right = word.reading_answer_qual(k)
            print (NOPE, self.YEP+'?', self.YEP)[right], green(word.character), red(u', '.join(word.kana))
            word.print_reading_alternatives(k)
            word.print_similar_meaning()
            if right > 0:
                return
            else:
                self.set_wrong(True)

    def reading_to_meaning(self, oword):
        while True:
            p = u', '.join(oword.kana)
            if isinstance(oword, Kanji):
                p += u' /k'
            e = read_eng(p)
            words = sorted(set(w for k in oword.kana for w in oword.list.by_kana[k]))
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
                self.set_wrong(True)

    def character_to_rm(self, word):
        imperfect = False
        # todo combine the two?
        def meaning():
            while True:
                entered_meaning = normalize(read_eng(word.ansi_character(), MEANING_PROMPT))
                qual = word.meaning_answer_qual(entered_meaning)
                print (NOPE, self.YEP+'?', self.YEP)[qual], blue(u', '.join(word.meaning))
                if qual > 0:
                    return
                else:
                    word.print_meaning_alternatives(entered_meaning)
                    self.set_wrong(True)
        def reading():
            while True:
                entered_reading = read_kana(word.ansi_character(), READING_PROMPT)
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
                    self.set_wrong(True)

        ops = [meaning, reading]
        random.shuffle(ops)
        for op in ops: op()

    def kanji_confusion(self, confusion):
        kanjis = confusion.kanjis[:]
        random.shuffle(kanjis)
        for kanji in kanjis:
            self.character_to_rm(kanji)

    KINDS = {'m2r': meaning_to_reading, 'r2m': reading_to_meaning, 'c2': character_to_rm, 'kc': kanji_confusion}


last_line = None
def change_last_line(line):
    global last_line
    assert line.endswith('\n')
    assert last_line is not None
    logfile.seek(-len(last_line.encode('utf-8')), 2)
    pos = logfile.tell()
    test = logfile.read() 
    assert test == last_line
    logfile.seek(pos)
    logfile.truncate()
    logfile.write(line)
    logfile.flush()
    last_line = line

def append_line(line):
    global last_line
    assert line.endswith('\n')
    logfile.seek(0, 2)
    logfile.write(line)
    logfile.flush()
    last_line = line

def handle_bang(bang):
    bang = bang.strip()
    if bang in ('!wrong', '!right'):
        if last_appended_test is None:
            print 'no last'
            return
        last_appended_test.set_wrong(bang == '!wrong')
        return
    if bang in ('!pcton', '!pctoff'):
        global pcton
        pcton = bang == '!pcton'
        return
    print '?bang?', repr(bang)

Word.list = ItemList(map(Word, json.load(open('vocabulary.json'))))
Kanji.list = ItemList(map(Kanji, json.load(open('kanji.json'))))

pcton = True
total_right_except_lat = 0

last_appended_test = None
def set_last_appended_test(lat):
    global last_appended_test
    if last_appended_test is not None:
        global total_right_except_lat
        total_right_except_lat += not last_appended_test.was_wrong
    last_appended_test = lat

def read_log():
    logfile.seek(0)
    for line in logfile.read().strip().split(u'\n'):
        bits = line.split(u':')
        if len(bits) == 4:
            bits = [u'0'] + bits
        assert len(bits) == 5
        ttime, kind, item_class, character, result = bits
        ttime = int(ttime)
        item_list = ITEM_CLASSES[item_class].list
        try:
            item = item_list.by_character[character]
        except KeyError:
            # interesting: quite a few were deleted
            #print '?', character
            continue
        item.old_tests.append({'time': ttime, 'kind': kind, 'item': item, 'result': result})

class Confusion(Item):
    def __init__(self, kanjis):
        self.character = kanjis[0].character
        self.kanjis = kanjis
        self.kana = []
        self.meaning = []
        self.user_specific = None
        Item.__init__(self, {})

ITEM_CLASSES = {'word': Word, 'kanji': Kanji, 'confusion': Confusion}

def read_confusion():
    confusions = []
    for line in open('confusion.txt').read().strip().split('\n'):
        line = line.decode('utf-8')
        confusions.append(Confusion([Kanji.list.by_character[c] for c in line]))
    Confusion.list = ItemList(confusions)


read_confusion()
read_log()

def save_item_list(item_list, filename):
    with codecs.open(filename, 'w', encoding='utf-8') as fp:
        for item in item_list:
            fp.write(u'%s:%s\n' % (item.__class__.__name__.lower(), item.character))
def load_item_list(filename):
    item_list = set()
    for line in codecs.open(filename, encoding='utf-8'):
        if line:
            item_class, character = line.strip().split(':')
            item_list.add(ITEM_CLASSES[item_class].list.by_character[character])
    return item_list

def item_was_recently_right(item):
    return item.old_tests and item.old_tests[-1]['result'] == 'right' and time.time() - 3600 < item.old_tests[-1]['time']
def item_was_last_wrong(item):
    return item.old_tests and item.old_tests[-1]['result'] == 'wrong'
def item_was_not_last_right(item):
    return (not item.old_tests) or item_was_last_wrong(item)
def item_was_recently_wrong(item):
    return item.old_tests and item.old_tests[-1]['result'] == 'wrong' and time.time() - 3600 < item.old_tests[-1]['time']
def get_filtered_items():
    filtered_items = []
    for cls in ITEM_CLASSES.values():
        if cls.avail_ops:
            filtered_items += filter(item_filter_real, cls.list.list)
    return filtered_items
def item_filter_real(item):
    return item_filter(item) and not item_was_recently_right(item)

if __name__ == '__main__' and 0:
    Kanji.avail_ops = ['r2m', 'm2r', 'c2']
    Word.avail_ops = ['r2m', 'm2r', 'c2']
    Confusion.avail_ops = ['kc']
    #item_filter = item_was_last_wrong
    #item_filter = lambda item: item.srs_numeric >= 9
    #item_filter = item_was_recently_wrong
    item_filter = lambda item: True
    #item_filter = lambda item: isinstance(item, Confusion)
    #item_filter = item_was_not_last_right
    item_map = lambda fi: fi
    item_map = lambda fi: random.sample(fi, 50)

    if len(sys.argv) > 1 and sys.argv[1] == '--load':
        loaded_item_list = load_item_list(sys.argv[2])
        item_filter = lambda item: not item_was_recently_right(item) and item in loaded_item_list
    elif len(sys.argv) > 1 and sys.argv[1] == '--save':
        item_filter = item_was_not_last_right
        item_map = lambda fi: random.sample(fi, 50)

    filtered_items = get_filtered_items()
    filtered_items = item_map(filtered_items)
    print '<%d items available>' % len(filtered_items)

    if len(sys.argv) > 1 and sys.argv[1] == '--save':
        assert item_filter is item_was_not_last_right#item_was_last_wrong
        save_item_list(filtered_items, sys.argv[2])
        exit()

    done = 0
    while True:
        pctstuff = ''
        if pcton and done > 0:
            done_right = total_right_except_lat + (not last_appended_test.was_wrong if last_appended_test is not None else 0)
            pctstuff = ' %d/%d=%.0f' % (done_right, done, done_right * 100.0 / done)
        print '[%d]%s' % (done, pctstuff)
        while True:
            item = None
            if not filtered_items:
                print 'all out...'
                break
            item = random.choice(filtered_items)
            if item_filter_real(item):
                break
            #filtered_items = get_filtered_items()
            filtered_items = filter(item_filter_real, filtered_items)
        if not item: break
        ops = item.avail_ops
        try:
            right = Test(random.choice(ops), item).run()
        except EOFError:
            break
        done += 1

        print
        #print
