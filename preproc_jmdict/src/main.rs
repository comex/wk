use serde::Deserialize;
#[derive(Debug, Deserialize, PartialEq)]
struct KEle {
    keb: String,
}
#[derive(Debug, Deserialize, PartialEq)]
struct REle {
    reb: String,
}
#[derive(Debug, Deserialize, PartialEq)]
struct Gloss {
    g_type: Option<String>,
    #[serde(rename = "$value")]
    value: String,
}
#[derive(Debug, Deserialize, PartialEq)]
struct Sense {
    pos: Vec<String>,
    xref: Vec<String>,
    gloss: Vec<Gloss>,
}
#[derive(Debug, Deserialize, PartialEq)]
struct Entry {
    ent_seq: u64,
    k_ele: Vec<KEle>,
    r_ele: Vec<REle>,
    sense: Vec<Sense>,
}
#[derive(Debug, Deserialize, PartialEq)]
struct JMDict {
    entry: Vec<Entry>,
}
fn main() {
    let text = std::fs::read_to_string("../JMdict_e").unwrap();
    let dict: JMDict = quick_xml::de::from_str(&text).unwrap();
}
