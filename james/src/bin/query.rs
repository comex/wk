use lmdb::{Environment, Database, Transaction, RoTransaction, Cursor};
use lru::LruCache;
use std::convert::TryInto;
use std::sync::{Mutex, Arc};
struct Querier {
    env: Environment,
    entries_db: Database,
    index_db: Database,
    entries_cache: Mutex<LruCache<u32, Arc<james::Entry>>>,
}
impl Querier {
    fn new() -> Querier {
        let db_path = james::db_path();
        let env = james::db_environment_builder()
            .set_flags(lmdb::EnvironmentFlags::READ_ONLY)
            .open(&db_path).expect("open environment");
        let entries_db = env.open_db(Some("entries")).expect("open entries database");
        let index_db = env.open_db(Some("index")).expect("open index database");
        Querier {
            env,
            entries_db,
            index_db,
            entries_cache: Mutex::new(LruCache::new(128)),
        }
    }
    fn search(&self, query: &str, is_cancelled: impl Fn() -> bool, mut got_result: impl FnMut(&str, Arc<james::Entry>)) {
        let key = james::query_to_key(query);
        println!("key={:?}", key);
        let txn = self.env.begin_ro_txn().expect("begin RO transaction");
        let mut index_cursor = txn.open_ro_cursor(self.index_db.clone()).expect("open index cursor");
        loop {
            let iter = if key.is_empty() { index_cursor.iter_start() } else { index_cursor.iter_from(&key) };
            for res in iter {
                let (found_key, found_val) = res.expect("lookup");
                let found_key = std::str::from_utf8(found_key).unwrap();
                if is_cancelled() { return; }
                if !found_key.starts_with(query) { break; }
                got_result(found_key, self.get_entry(found_val, &txn));
            }
            break; // XX
        }
    }
    fn get_entry(&self, index_val: &[u8], txn: &RoTransaction) -> Arc<james::Entry> {
        let key = u32::from_le_bytes(index_val.try_into().expect("index_val length"));
        if let Some(entry) = self.entries_cache.lock().unwrap().get(&key).cloned() {
            return entry;
        }
        let compressed = txn.get(self.entries_db, &index_val).expect("get_entry");
        let decompressed = lz4::block::decompress(compressed, None).expect("decompress");
        //println!("{:?}", decompressed);
        let entry: james::Entry = bincode::deserialize(&decompressed).expect("deserialize");
        let arc = Arc::new(entry);
        self.entries_cache.lock().unwrap().put(key, arc.clone());
        arc
    }
}
fn main() {
    let q = Querier::new();
    let query = std::env::args().nth(1).unwrap();
    //panic!("{}", james::query_to_key(&query));
    q.search(&query,
        /* is_cancelled */ || false,
        /* got_result*/ |key, entry| {
            println!("{} => {:?}", key, entry);
        }
    );
}
