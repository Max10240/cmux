//! NEVER MERGE. A measure of the open of cmux-git (`Repository::open`, `Checkout::open`) on five
//! layouts that the real git makes, beside the one git run that was the whole of
//! `Checkout::open` before this branch ("before"). The test ends with a panic that has the
//! times, so that the log of a step shows them.
#![cfg(unix)]

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use cmux_git::head::Checkout;
use cmux_git::run::run_git_within;
use cmux_git::{MAX_SMALL_OUTPUT_BYTES, Repository};

const ROUNDS: usize = 101;

/// The least, the middle and the largest of `times`, in milliseconds.
fn summary(mut times: Vec<Duration>) -> String {
    times.sort();
    let ms = |time: Duration| time.as_secs_f64() * 1000.0;
    format!(
        "min {:.2} / median {:.2} / max {:.2} ms",
        ms(times[0]),
        ms(times[times.len() / 2]),
        ms(times[times.len() - 1])
    )
}

/// Runs git in `directory`, apart from the host's git config.
fn git(directory: &Path, arguments: &[&str]) {
    let ended = Command::new("git")
        .arg("-C")
        .arg(directory)
        .args(["-c", "user.name=t", "-c", "user.email=t@e.test"])
        .args(arguments)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .unwrap()
        .success();
    assert!(ended, "git {arguments:?} failed in {directory:?}");
}

/// The time of the one git run that was the whole of `Checkout::open` before this branch.
fn before(folder: &Path) -> Duration {
    let start = Instant::now();
    let arguments = ["rev-parse", "--show-toplevel"];
    let output =
        run_git_within(folder, &[], &arguments, MAX_SMALL_OUTPUT_BYTES, Duration::from_secs(30));
    let time = start.elapsed();
    assert!(output.is_ok(), "git rev-parse failed in {folder:?}");
    time
}

#[test]
fn measure_the_open_on_five_layouts() {
    let top = std::env::temp_dir().join(format!("measure-open-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&top);
    std::fs::create_dir_all(&top).unwrap();
    let top = top.canonicalize().unwrap();

    // A main checkout, a folder below it, a linked work tree, a work tree whose git folder is
    // at another place and names it by `core.worktree`, and a work tree whose `.git` entry is
    // a link to its git folder at another place.
    let main = top.join("main");
    std::fs::create_dir_all(main.join("below/deep")).unwrap();
    git(&main, &["init", "--quiet", "--initial-branch=main"]);
    std::fs::write(main.join("a.txt"), "one\n").unwrap();
    git(&main, &["add", "a.txt"]);
    git(&main, &["commit", "--quiet", "-m", "a.txt"]);
    let linked = top.join("linked");
    git(&main, &["worktree", "add", "--quiet", "-b", "linked", linked.to_str().unwrap()]);
    let (apart, store) = (top.join("apart"), top.join("store"));
    std::fs::create_dir_all(&apart).unwrap();
    let arguments =
        ["init", "--quiet", "--initial-branch=main", "--separate-git-dir", store.to_str().unwrap()];
    git(&apart, &arguments);
    git(&apart, &["config", "core.worktree", apart.to_str().unwrap()]);
    let (by_link, link_store) = (top.join("by-link"), top.join("link-store"));
    std::fs::create_dir_all(&by_link).unwrap();
    let arguments = [
        "init",
        "--quiet",
        "--initial-branch=main",
        "--separate-git-dir",
        link_store.to_str().unwrap(),
    ];
    git(&by_link, &arguments);
    std::fs::remove_file(by_link.join(".git")).unwrap();
    std::os::unix::fs::symlink(&link_store, by_link.join(".git")).unwrap();

    let layouts: [(&str, PathBuf); 5] = [
        ("a main checkout", main.clone()),
        ("a folder below the top folder", main.join("below/deep")),
        ("a linked work tree", linked),
        ("a git folder at another place", apart),
        ("a link to a git folder at another place", by_link),
    ];
    let mut lines = Vec::new();
    for (name, folder) in layouts {
        let (mut children, mut repositories, mut checkouts) = (Vec::new(), Vec::new(), Vec::new());
        // The first round is not counted.
        for round in 0..=ROUNDS {
            let time = before(&folder);
            let start = Instant::now();
            let repository = Repository::open(&folder);
            let repository_time = start.elapsed();
            let start = Instant::now();
            let checkout = Checkout::open(&folder);
            let checkout_time = start.elapsed();
            assert!(repository.is_ok(), "{name}: the repository's open failed");
            assert!(checkout.is_ok(), "{name}: the checkout's open failed");
            if round > 0 {
                children.push(time);
                repositories.push(repository_time);
                checkouts.push(checkout_time);
            }
        }
        lines.push(format!("{name}: before (one git run): {}", summary(children)));
        lines.push(format!("{name}: Repository::open: {}", summary(repositories)));
        lines.push(format!("{name}: Checkout::open: {}", summary(checkouts)));
    }
    let _ = std::fs::remove_dir_all(&top);
    panic!("MEASURE ({ROUNDS} rounds each)\nMEASURE {}", lines.join("\nMEASURE "));
}
