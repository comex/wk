use serde::Deserialize;
use regex::{Regex, Captures};
use lmdb::Transaction;
use itertools::Itertools;

use james::Entry;

#[derive(Debug, Deserialize, PartialEq)]
struct JMDict {
    entry: Vec<Entry>,
}
fn main() {
    let db_path = james::db_path();
    let _ = std::fs::remove_dir_all(&db_path);
    std::fs::create_dir(&db_path).expect("create DB");
    let env = james::db_environment_builder()
        .open(&db_path).expect("open environment");
    let entries_db = env.create_db(Some("entries"), lmdb::DatabaseFlags::INTEGER_KEY).expect("create entries database");
    let index_db = env.create_db(Some("index"), lmdb::DatabaseFlags::DUP_SORT).expect("create index database");
    let mut txn = env.begin_rw_txn().expect("begin RW transaction");

    let text = std::fs::read_to_string("../JMdict_e").unwrap();
    // quick-xml doesn't support arbitrary symbols, and I don't even want them to be expanded, so do a hacky search and replace
    let text = Regex::new(r"&([a-zA-Z0-9-]+);").unwrap().replace_all(&text, |captures: &Captures| -> String {
        format!("%%[{}]", &captures[1])
    });
    println!("parsing...");
    let mut dict: JMDict = quick_xml::de::from_str(&text).unwrap();
    println!("writing...");

    dict.entry.sort_by_key(|entry| entry.ent_seq);

    {
        let mut entries_cursor = txn.open_rw_cursor(entries_db).expect("open entries cursor");
        for entry in &dict.entry {
            let value_unc: Vec<u8> = bincode::serialize(&entry).expect("bincode serialize");
            let value = lz4::block::compress(&value_unc, None, true).expect("compress");
            let key: [u8; 4] = entry.ent_seq.to_le_bytes(); // TODO(future): to_ne_bytes is unstable; other places too
            entries_cursor.put(&key, &value, lmdb::WriteFlags::NO_OVERWRITE | lmdb::WriteFlags::APPEND).expect("append entries entry");
        }
    }

    {
        let mut index_cursor = txn.open_rw_cursor(index_db).expect("open index cursor");
        for entry in &dict.entry {
            let iter = entry.k_ele.iter().map(|k| &k.keb)
                .chain(entry.r_ele.iter().map(|r| &r.reb))
                .map(|s| james::query_to_key(s))
                .sorted()
                .dedup();
            for key in iter {
                if key.is_empty() { continue; }
                let value: [u8; 4] = entry.ent_seq.to_le_bytes();
                index_cursor.put(&key, &value, lmdb::WriteFlags::empty()).expect("add index entry");
            }
        }
    }

    txn.commit().expect("commit");


}
