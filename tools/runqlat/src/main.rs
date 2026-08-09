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

    /// Run as a Prometheus exporter serving GET /metrics on this address
    /// (e.g. ":9602"), instead of a one-shot trace. Runs until killed.
    #[arg(long, value_name = "ADDR")]
    exporter: Option<String>,
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

    if let Some(addr) = args.exporter {
        // Exporter mode: serve /metrics until killed.
        let obj = skel.object();
        periscope_exporter::serve(&addr, || render_metrics(obj))?;
        return Ok(());
    }

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

/// Read the log2 histogram buckets (index -> count) from hist_map.
fn read_buckets(obj: &libbpf::Object) -> Vec<(u32, u64)> {
    let hist_map = obj
        .maps()
        .find(|m| m.name() == "hist_map")
        .expect("hist_map not found in BPF object");
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
    buckets.sort_by_key(|(idx, _)| *idx);
    buckets
}

/// Read a single u64 slot from the hist_sum map (0 = total us, 1 = count).
fn read_sum_slot(obj: &libbpf::Object, slot: u32) -> u64 {
    let sum = obj
        .maps()
        .find(|m| m.name() == "hist_sum")
        .expect("hist_sum not found in BPF object");
    let key = slot.to_ne_bytes();
    match sum.lookup(&key, libbpf::MapFlags::ANY) {
        Ok(Some(v)) if v.len() == 8 => u64::from_ne_bytes(v[..8].try_into().unwrap()),
        _ => 0,
    }
}

/// Render the Prometheus text-format exposition for the run queue histogram.
///
/// The log2 buckets (index N covers 2^(N-1)..2^N-1 microseconds) are converted to
/// cumulative Prometheus `le` buckets in seconds, plus `_sum` and `_count`.
fn render_metrics(obj: &libbpf::Object) -> String {
    const NAME: &str = "periscope_runqueue_latency_seconds";
    let buckets = read_buckets(obj);
    let sum_us = read_sum_slot(obj, 0);
    let count = read_sum_slot(obj, 1);

    let mut out = String::new();
    out.push_str(&format!(
        "# HELP {NAME} Run queue (scheduler) latency (seconds).\n"
    ));
    out.push_str(&format!("# TYPE {NAME} histogram\n"));

    // Cumulative le buckets. Bucket index N has upper bound 2^N us; emit le for
    // each present bucket, then +Inf. le values are in seconds.
    let mut cum: u64 = 0;
    for (idx, c) in &buckets {
        cum += c;
        let hi_us: f64 = if *idx == 0 { 1.0 } else { (1u64 << idx) as f64 };
        let le = hi_us / 1e6;
        out.push_str(&format!("{NAME}_bucket{{le=\"{le:e}\"}} {cum}\n"));
    }
    out.push_str(&format!("{NAME}_bucket{{le=\"+Inf\"}} {cum}\n"));
    out.push_str(&format!("{NAME}_sum {}\n", sum_us as f64 / 1e6));
    out.push_str(&format!("{NAME}_count {count}\n"));
    out
}

fn print_histogram(obj: &libbpf::Object) {
    let buckets = read_buckets(obj);

    if buckets.is_empty() {
        println!("No data yet.");
        return;
    }

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
