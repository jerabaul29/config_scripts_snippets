
- https://ryhl.io/blog/async-what-is-blocking/
- Function tokio::task::spawn_blocking => Runs the provided closure on a thread where blocking is acceptable.
- https://pkolaczk.github.io/multiple-threadpools-rust/ see in particular the:

let (tx, rx) = std::sync::mpsc::channel();
for f in files.into_iter() {
    let tx = tx.clone();
    pool.spawn(move || {
        tx.send(compute_hash(f)).unwrap();
    });
}
drop(tx); // need to close all senders, otherwise...
let hashes: Vec<FileHash> = rx.into_iter().collect();  // ... this would block

Instead of spawning tasks directly on the thread pool struct, we first need to create a scope object by calling scope function. The scope is guaranteed to exit only after all tasks launched inside it finished. This essentially allows the tasks inside the scope to access variables that live at least as long as the scope:

let (tx, rx) = std::sync::mpsc::channel();
let logger: &Log = ...;
pool.scope(move |s| {
    for f in files.into_iter() {
        let tx = tx.clone();
        s.spawn(move |s| {
            logger.println(format!("Computing hash of: {}", f.display()));  // ok
            tx.send(f).unwrap();
        });
    }
});



