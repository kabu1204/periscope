use std::time::Duration;

use anyhow::Result;
use clap::Parser;
use libbpf_rs as libbpf;

use libbpf::skel::{OpenSkel, Skel, SkelBuilder};
use libbpf::MapCore as _;

// Include the generated BPF skeleton from the build script output directory.
mod skel {
    include!(concat!(env!("OUT_DIR"), "/runqlat.skel.rs"));
}

use skel::*;

/// Run queue latency histogram tool (equivalent to bcc runqlat).
#[derive(Parser, Debug)]
struct Args {
    /// Duration in seconds to trace before printing and exiting.
    /// If not specified, runs for 1 hour or until killed.
    #[arg(short, long)]
    duration: Option<u64>,
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Build and open the BPF skeleton.
    let skel_builder = RunqlatSkelBuilder::default();
    let mut obj_storage: std::mem::MaybeUninit<libbpf::OpenObject> =
        std::mem::MaybeUninit::uninit();
    let open_skel = skel_builder.open(&mut obj_storage)?;
    let mut skel = open_skel.load()?;

    // Attach all BPF programs (tracepoints).
    skel.attach()?;

    eprintln!("Tracing run queue latency... Hit Ctrl-C to end.");

    // Wait for the specified duration or until Ctrl+C (SIGINT interrupts sleep).
    if let Some(secs) = args.duration {
        std::thread::sleep(Duration::from_secs(secs));
    } else {
        // Sleep until SIGINT interrupts us.
        std::thread::sleep(Duration::from_secs(3600));
    }

    // Print the final histogram.
    println!();
    print_histogram(skel.object());
    println!();

    Ok(())
}

fn print_histogram(obj: &libbpf::Object) {
    let hist_map = obj
        .maps()
        .find(|m| m.name() == "hist_map")
        .expect("hist_map not found in BPF object");

    // Collect all bucket counts.
    let mut buckets: Vec<(u32, u64)> = Vec::new();

    for key in hist_map.keys() {
        if key.len() != 4 {
            continue;
        }
        let idx = u32::from_ne_bytes(key[..4].try_into().unwrap());
        if let Some(val) = hist_map.lookup(&key, libbpf::MapFlags::ANY).unwrap() {
            if val.len() == 8 {
                let count = u64::from_ne_bytes(val[..8].try_into().unwrap());
                buckets.push((idx, count));
            }
        }
    }

    if buckets.is_empty() {
        println!("No data yet.");
        return;
    }

    buckets.sort_by_key(|(idx, _)| *idx);

    // Find the max count for bar chart scaling.
    let max_count = buckets.iter().map(|(_, c)| *c).max().unwrap_or(1);

    // Find the first and last non-zero buckets.
    let first_nonzero = buckets.iter().find(|(_, c)| *c > 0).map(|(i, _)| *i);
    let last_nonzero = buckets.iter().rfind(|(_, c)| *c > 0).map(|(i, _)| *i);

    let first = first_nonzero
        .or(buckets.first().map(|(i, _)| *i))
        .unwrap_or(0);
    let last = last_nonzero
        .or(buckets.last().map(|(i, _)| *i))
        .unwrap_or(0);

    // Print header.
    println!("\n     usecs               : count     distribution");

    for idx in first..=last {
        let count = buckets
            .iter()
            .find(|(i, _)| *i == idx)
            .map(|(_, c)| *c)
            .unwrap_or(0);

        // Bucket boundaries: index 0 = 0, index N = 2^(N-1) to 2^N - 1
        let lo: u64 = if idx == 0 { 0 } else { 1u64 << (idx - 1) };
        let hi: u64 = if idx == 0 {
            1
        } else if idx >= 63 {
            u64::MAX
        } else {
            (1u64 << idx) - 1
        };

        // Bar chart: 40 characters max.
        let bar_len = count
            .checked_mul(40)
            .map(|v| v as usize / max_count as usize);
        let bar: String = "#".repeat(bar_len.unwrap_or(0));

        println!("    {:>5} -> {:<10} : {:<8} |{:40}|", lo, hi, count, bar);
    }
}
