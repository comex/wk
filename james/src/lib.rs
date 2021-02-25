use serde::{Serialize, Deserialize};
use itertools::Itertools;
use regex::{Regex, Captures};
use lazy_static::lazy_static;

#[derive(Debug, Serialize, Deserialize, PartialEq)]
pub struct KEle {
    pub keb: String,
    #[serde(default)]
    pub ke_inf: Vec<String>,
    #[serde(default)]
    pub ke_pri: Vec<String>,
}
#[derive(Debug, Serialize, Deserialize, PartialEq)]
pub struct REle {
    pub reb: String,
    #[serde(default)]
    pub re_nokanji: Option<()>,
    #[serde(default)]
    pub re_restr: Vec<String>,
    #[serde(default)]
    pub re_inf: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
pub struct Gloss {
    #[serde(default)]
    pub lang: Option<String>,
    #[serde(default)]
    pub g_type: Option<String>,
    // g_gend
    #[serde(rename = "$value")]
    pub value: String,
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
pub struct LSource {
    #[serde(default)]
    pub lang: Option<String>,
    #[serde(rename = "$value", default)]
    pub value: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
pub struct Sense {
    #[serde(default)]
    pub stagk: Vec<String>,
    #[serde(default)]
    pub stagr: Vec<String>,
    #[serde(default)]
    pub pos: Vec<String>,
    #[serde(default)]
    pub xref: Vec<String>,
    #[serde(default)]
    pub ant: Vec<String>,
    #[serde(default)]
    pub field: Vec<String>,
    #[serde(default)]
    pub misc: Vec<String>,
    #[serde(default)]
    pub s_inf: Vec<String>,
    #[serde(default)]
    pub lsource: Vec<LSource>,
    #[serde(default)]
    pub gloss: Vec<Gloss>,
    #[serde(default)]
    pub dial: Vec<String>,
}
#[derive(Debug, Serialize, Deserialize, PartialEq)]
pub struct Entry {
    #[serde(skip_serializing)]
    pub ent_seq: u32,
    #[serde(default)]
    pub k_ele: Vec<KEle>,
    #[serde(default)]
    pub r_ele: Vec<REle>,
    #[serde(default)]
    pub sense: Vec<Sense>,
}

static KANA_TO_ROMAJI: phf::Map<char, &'static str> = phf::phf_map! {
    'ー' => "-",
    'ア' => "a",
    'あ' => "a",
    'バ' => "ba",
    'ば' => "ba",
    'ベ' => "be",
    'べ' => "be",
    'ビ' => "bi",
    'び' => "bi",
    'ボ' => "bo",
    'ぼ' => "bo",
    'ブ' => "bu",
    'ぶ' => "bu",
    'チ' => "chi",
    'ち' => "chi",
    'ダ' => "da",
    'だ' => "da",
    'デ' => "de",
    'で' => "de",
    'ヂ' => "di",
    'ぢ' => "di",
    'ド' => "do",
    'ど' => "do",
    'ヅ' => "du",
    'づ' => "du",
    'エ' => "e",
    'え' => "e",
    'フ' => "fu",
    'ふ' => "fu",
    'ガ' => "ga",
    'が' => "ga",
    'ゲ' => "ge",
    'げ' => "ge",
    'ギ' => "gi",
    'ぎ' => "gi",
    'ゴ' => "go",
    'ご' => "go",
    'グ' => "gu",
    'ぐ' => "gu",
    'ハ' => "ha",
    'は' => "ha",
    'ヘ' => "he",
    'へ' => "he",
    'ヒ' => "hi",
    'ひ' => "hi",
    'ホ' => "ho",
    'ほ' => "ho",
    'イ' => "i",
    'い' => "i",
    'ジ' => "ji",
    'じ' => "ji",
    'カ' => "ka",
    'か' => "ka",
    'ケ' => "ke",
    'け' => "ke",
    'キ' => "ki",
    'き' => "ki",
    'コ' => "ko",
    'こ' => "ko",
    'ク' => "ku",
    'く' => "ku",
    'マ' => "ma",
    'ま' => "ma",
    'メ' => "me",
    'め' => "me",
    'ミ' => "mi",
    'み' => "mi",
    'モ' => "mo",
    'も' => "mo",
    'ム' => "mu",
    'む' => "mu",
    'ン' => "n", // *
    'ん' => "n", // *
    'ナ' => "na",
    'な' => "na",
    'ネ' => "ne",
    'ね' => "ne",
    'ニ' => "ni",
    'に' => "ni",
    'ノ' => "no",
    'の' => "no",
    'ヌ' => "nu",
    'ぬ' => "nu",
    'オ' => "o",
    'お' => "o",
    'パ' => "pa",
    'ぱ' => "pa",
    'ペ' => "pe",
    'ぺ' => "pe",
    'ピ' => "pi",
    'ぴ' => "pi",
    'ポ' => "po",
    'ぽ' => "po",
    'プ' => "pu",
    'ぷ' => "pu",
    'ラ' => "ra",
    'ら' => "ra",
    'レ' => "re",
    'れ' => "re",
    'リ' => "ri",
    'り' => "ri",
    'ロ' => "ro",
    'ろ' => "ro",
    'ル' => "ru",
    'る' => "ru",
    'サ' => "sa",
    'さ' => "sa",
    'セ' => "se",
    'せ' => "se",
    'シ' => "shi",
    'し' => "shi",
    'ソ' => "so",
    'そ' => "so",
    'ス' => "su",
    'す' => "su",
    'タ' => "ta",
    'た' => "ta",
    'テ' => "te",
    'て' => "te",
    'ト' => "to",
    'と' => "to",
    'ツ' => "tsu",
    'つ' => "tsu",
    'ウ' => "u",
    'う' => "u",
    'ヴ' => "vu",
    'ワ' => "wa",
    'わ' => "wa",
    'ヱ' => "we",
    'ゑ' => "we",
    'ヰ' => "wi",
    'ゐ' => "wi",
    'ヲ' => "wo",
    'を' => "wo",
    'ァ' => "xa",
    'ぁ' => "xa",
    'ェ' => "xe",
    'ぇ' => "xe",
    'ィ' => "xi",
    'ぃ' => "xi",
    'ォ' => "xo",
    'ぉ' => "xo",
    'ッ' => "xtsu",
    'っ' => "xtsu",
    'ゥ' => "xu",
    'ぅ' => "xu",
    'ヮ' => "xwa",
    'ゎ' => "xwa",
    'ャ' => "xya",
    'ゃ' => "xya",
    'ョ' => "xyo",
    'ょ' => "xyo",
    'ュ' => "xyu",
    'ゅ' => "xyu",
    'ヤ' => "ya",
    'や' => "ya",
    'ヨ' => "yo",
    'よ' => "yo",
    'ユ' => "yu",
    'ゆ' => "yu",
    'ザ' => "za",
    'ざ' => "za",
    'ゼ' => "ze",
    'ぜ' => "ze",
    'ゾ' => "zo",
    'ぞ' => "zo",
    'ズ' => "zu",
    'ず' => "zu",
};

static REPLACEMENTS: phf::Map<&'static str, &'static str> = phf::phf_map! {
    "xtsu" => "",
    "ixy" => "",
    "ix" => "",
    "ux" => "",
    "ox" => "",
    "ex" => "",
    "di" => "ji",
    "du" => "zu",
    "tsu" => "tu",
    "ti" => "chi",
    "ei" => "e",
    "ou" => "o",
    "wo" => "o",
};

lazy_static! {
    static ref REPLACEMENTS_REGEX: Regex =
        Regex::new(&REPLACEMENTS.keys().map(|s| regex::escape(s)).join("|"))
            .expect("regex");
}

pub fn query_to_key(query: &str) -> String {
    let mut out = String::new();

    for c in query.chars() {
        if let Some(s) = KANA_TO_ROMAJI.get(&c) {
            out.push_str(s);
        } else {
            let c = unicode_hfwidth::to_standard_width(c).unwrap_or(c);
            out.push(c);
        }
    }

    let mut out: String = out.to_lowercase();
    for _ in 0..2 {
        out = REPLACEMENTS_REGEX.replace_all(&out,
            |x: &Captures| -> &'static str { REPLACEMENTS[&x[0]] }
        ).into_owned();
    }
    let out: String = out.chars()
        .filter(|&c| !c.is_whitespace() && c != '-' && c != '・')
        .dedup_by(|&c1, &c2| { c1 == c2 && c1 < (0x80 as char) })
        .collect();

    println!("'{}' => '{}'", query, out);
    out

}
