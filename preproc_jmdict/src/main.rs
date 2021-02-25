use serde::{Serialize, Deserialize};
use regex::{Regex, Captures};
use lmdb::Transaction;
use std::path::Path;
use std::mem::drop;

#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct KEle {
    keb: String,
    #[serde(default)]
    ke_inf: Vec<String>,
    #[serde(default)]
    ke_pri: Vec<String>,
}
#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct REle {
    reb: String,
    #[serde(default)]
    re_nokanji: Option<()>,
    #[serde(default)]
    re_restr: Vec<String>,
    #[serde(default)]
    re_inf: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct Gloss {
    #[serde(default)]
    lang: Option<String>,
    #[serde(default)]
    g_type: Option<String>,
    // g_gend
    #[serde(rename = "$value")]
    value: String,
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct LSource {
    #[serde(default)]
    lang: Option<String>,
    #[serde(rename = "$value", default)]
    value: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct Sense {
    #[serde(default)]
    stagk: Vec<String>,
    #[serde(default)]
    stagr: Vec<String>,
    #[serde(default)]
    pos: Vec<String>,
    #[serde(default)]
    xref: Vec<String>,
    #[serde(default)]
    ant: Vec<String>,
    #[serde(default)]
    field: Vec<String>,
    #[serde(default)]
    misc: Vec<String>,
    #[serde(default)]
    s_inf: Vec<String>,
    #[serde(default)]
    lsource: Vec<LSource>,
    #[serde(default)]
    gloss: Vec<Gloss>,
    #[serde(default)]
    dial: Vec<String>,
}
#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct Entry {
    #[serde(skip_serializing)]
    ent_seq: u32,
    #[serde(default)]
    k_ele: Vec<KEle>,
    #[serde(default)]
    r_ele: Vec<REle>,
    #[serde(default)]
    sense: Vec<Sense>,
}
#[derive(Debug, Deserialize, PartialEq)]
struct JMDict {
    entry: Vec<Entry>,
}
fn main() {
    let db_path = Path::new("../jmdict.lmdb");
    let _ = std::fs::remove_dir_all(db_path);
    std::fs::create_dir(db_path).expect("create DB");
    let env = lmdb::Environment::new()
        .set_max_dbs(1)
        .set_map_size(1024 * 1024 * 128)
        .open(db_path).expect("open environment");
    let entries_db = env.create_db(Some("entries"), lmdb::DatabaseFlags::INTEGER_KEY).expect("create database");
    let mut txn = env.begin_rw_txn().expect("begin RW transaction");
    let mut entries_cursor = txn.open_rw_cursor(entries_db).expect("open cursor");

    let text = std::fs::read_to_string("../JMdict_e").unwrap();
    // quick-xml doesn't support arbitrary symbols, and I don't even want them to be expanded, so do a hacky search and replace
    let text = Regex::new(r"&([a-zA-Z0-9-]+);").unwrap().replace_all(&text, |captures: &Captures| -> String {
        format!("%%[{}]", &captures[1])
    });
    println!("parsing...");
    let mut dict: JMDict = quick_xml::de::from_str(&text).unwrap();
    println!("writing...");

    dict.entry.sort_by_key(|entry| entry.ent_seq);

    for entry in dict.entry {
        let value_unc: Vec<u8> = bincode::serialize(&entry).expect("bincode serialize");
        let value = lz4::block::compress(&value_unc, None, false).expect("compress");
        let key: [u8; 4] = entry.ent_seq.to_le_bytes(); // TODO(future): to_ne_bytes is unstable
        entries_cursor.put(&key, &value, lmdb::WriteFlags::NO_OVERWRITE | lmdb::WriteFlags::APPEND).expect("append entry");
    }

    drop(entries_cursor);
    txn.commit().expect("commit");


}
