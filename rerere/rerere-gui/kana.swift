import RegexBuilder
let kana: [String: String] = [
    "a": "あ",
    "i": "い",
    "u": "う",
    "e": "え",
    "o": "お",
    "ka": "か",
    "ki": "き",
    "ku": "く",
    "ke": "け",
    "ko": "こ",
    "ga": "が",
    "gi": "ぎ",
    "gu": "ぐ",
    "ge": "げ",
    "go": "ご",
    "sa": "さ",
    "si": "し",
    "su": "す",
    "se": "せ",
    "so": "そ",
    "za": "ざ",
    "ji": "じ",
    "zu": "ず",
    "ze": "ぜ",
    "zo": "ぞ",
    "ta": "た",
    "ti": "ち",
    "tu": "つ",
    "tsu": "つ",
    "te": "て",
    "to": "と",
    "da": "だ",
    "di": "ぢ",
    "du": "づ",
    "de": "で",
    "do": "ど",
    "na": "な",
    "ni": "に",
    "nu": "ぬ",
    "ne": "ね",
    "no": "の",
    "ha": "は",
    "hi": "ひ",
    "fu": "ふ",
    "he": "へ",
    "ho": "ほ",
    "ba": "ば",
    "bi": "び",
    "bu": "ぶ",
    "be": "べ",
    "bo": "ぼ",
    "pa": "ぱ",
    "pi": "ぴ",
    "pu": "ぷ",
    "pe": "ぺ",
    "po": "ぽ",
    "ma": "ま",
    "mi": "み",
    "mu": "む",
    "me": "め",
    "mo": "も",
    "ya": "や",
    "yu": "ゆ",
    "yo": "よ",
    "ra": "ら",
    "ri": "り",
    "ru": "る",
    "re": "れ",
    "ro": "ろ",
    "wa": "わ",
    "wo": "を",
    "nn": "ん",
    "shi": "し",
    "chi": "ち",
    "xya": "ゃ",
    "xyu": "ゅ",
    "xyo": "ょ",
    "xtu": "っ",
    "xtsu": "っ",
]

@MainActor let kanaRegex: Regex = try! Regex(kana.keys.joined(separator: "|"))

func indexToBytes(_ stringIndex: String.Index, in str: String) -> Int {
    let utf8 = str.utf8
    return utf8.distance(from: utf8.startIndex, to: stringIndex.samePosition(in: str.utf8)!)
}
func bytesToIndex(_ utf8Index: Int, in str: String) -> String.Index {
    let utf8 = str.utf8
    return utf8.index(utf8.startIndex, offsetBy: utf8Index).samePosition(in: str)!
}

@MainActor
func fixKana(_ text: inout String, fix: (_ fixIndex: (String.Index) -> String.Index) -> Void) {
    func replace<Output>(_ regex: some RegexComponent<Output>, with replacementFunc: (Regex<Output>.Match) -> String) {
        // It's surprisingly hard to do better than O(n^2) with how crazy String.Index is (it's specific to a given string).
        // Possible, but surprisingly hard.
        // So do the dumb thing instead.
        while let match = try! regex.regex.firstMatch(in: text) {
            let startIndex = indexToBytes(match.range.lowerBound, in: text)
            let oldEndIndex = indexToBytes(match.range.upperBound, in: text)
            let replacement = replacementFunc(match)
            let newEndIndex = startIndex + replacement.utf8.count
            var newText: String = text
            newText.replaceSubrange(match.range, with: replacement)
            fix { (oldSI: String.Index) -> String.Index in
                // Even if the quadratic behavior elsewhere were fixed, this is also potentially O(n).  (is it really?)
                let old = indexToBytes(oldSI, in: text)
                let new: Int
                if old <= startIndex {
                    new = old
                } else if old >= oldEndIndex {
                    new = newEndIndex + (old - oldEndIndex)
                } else {
                    new = newEndIndex
                }
                return bytesToIndex(new, in: newText)
            }
            text = newText
        }
        
    }
    replace(/([mnrbphgk])y([aiueo])/) { m in "\(m.1)ixy\(m.2)" }
    replace(/(sh|ch|j)([aueo])/) { m in "\(m.1)ixy\(m.2)" }
    replace(/kk|ss|cc|tt|ff|bb|pp/) { m in "xtsu\(m.0.dropFirst())" }
    replace(kanaRegex) { m in kana[String(m.0)]! }

}
