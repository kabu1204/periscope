use std::time::Duration;

use anyhow::{bail, Result};
use clap::Parser;
use libbpf_rs as libbpf;

use libbpf::skel::{OpenSkel, Skel, SkelBuilder};
use libbpf::MapCore as _;

// Include the generated BPF skeleton from the build script output directory.
mod skel {
    include!(concat!(env!("OUT_DIR"), "/offcpu.skel.rs"));
}

use skel::*;

/// Maximum stack depth captured per stack (must match MAX_STACK_DEPTH in offcpu.bpf.c).
const MAX_STACK_DEPTH: usize = 127;

/// Size of the aggregation key in offcpu.bpf.c:
/// pid (4) + padding (4) + kernel_stack_id (8) + user_stack_id (8) + comm (16) = 40.
const KEY_SIZE: usize = 40;

/// Off-CPU time by stack (equivalent to bcc offcputime).
#[derive(Parser, Debug)]
struct Args {
    /// Duration in seconds to trace before printing and exiting.
    /// If not specified, runs for 1 hour or until killed.
    #[arg(short, long)]
    duration: Option<u64>,

    /// Only show the top N stacks by total off-CPU time (0 = all).
    #[arg(short, long, default_value_t = 0)]
    top: usize,

    /// Run as a Prometheus exporter serving GET /metrics on this address
    /// (e.g. ":9603"), instead of a one-shot trace. Runs until killed.
    #[arg(long, value_name = "ADDR")]
    exporter: Option<String>,
}

/// One parsed aggregation record from the counts map.
struct Record {
    pid: u32,
    kernel_stack_id: i64,
    user_stack_id: i64,
    comm: String,
    total_us: u64,
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Build and open the BPF skeleton.
    let skel_builder = OffcpuSkelBuilder::default();
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

    eprintln!(
        "Tracing off-CPU time (us) of all threads by user + kernel stack... Hit Ctrl-C to end."
    );

    // Wait for the specified duration or until Ctrl+C (SIGINT interrupts sleep).
    if let Some(secs) = args.duration {
        std::thread::sleep(Duration::from_secs(secs));
    } else {
        std::thread::sleep(Duration::from_secs(3600));
    }

    // Print the aggregated report.
    println!();
    print_report(skel.object(), args.top)?;
    println!();

    Ok(())
}

/// Read all aggregation records from the counts map.
fn read_records(obj: &libbpf::Object) -> Result<Vec<Record>> {
    let counts = obj
        .maps()
        .find(|m| m.name() == "counts")
        .expect("counts map not found in BPF object");
    let mut records: Vec<Record> = Vec::new();
    for key in counts.keys() {
        if let Some(val) = counts.lookup(&key, libbpf::MapFlags::ANY)? {
            if val.len() == 8 {
                let total_us = u64::from_ne_bytes(val[..8].try_into().unwrap());
                records.push(parse_key(&key, total_us)?);
            }
        }
    }
    Ok(records)
}

/// Render the Prometheus text-format exposition for off-CPU time.
///
/// One counter per aggregation key (pid, comm, kernel stack id, user stack id).
/// Stack ids (not symbolized names) are used as labels to bound cardinality.
fn render_metrics(obj: &libbpf::Object) -> String {
    const NAME: &str = "periscope_offcpu_seconds_total";
    let mut out = String::new();
    out.push_str(&format!(
        "# HELP {NAME} Off-CPU (blocked) time per stack, in seconds.\n"
    ));
    out.push_str(&format!("# TYPE {NAME} counter\n"));

    let records = read_records(obj).unwrap_or_default();
    // Bound label cardinality: export only the top stacks by total off-CPU time.
    let mut sorted = records;
    sorted.sort_by_key(|r| std::cmp::Reverse(r.total_us));
    const EXPORT_TOP: usize = 50;
    sorted.truncate(EXPORT_TOP);
    for r in &sorted {
        // Escape any characters in comm that are special in label values.
        let comm = r.comm.replace('\\', "\\\\").replace('"', "\\\"");
        out.push_str(&format!(
            "{NAME}{{pid=\"{}\",comm=\"{}\",kernel_stack_id=\"{}\",user_stack_id=\"{}\"}} {}\n",
            r.pid,
            comm,
            r.kernel_stack_id,
            r.user_stack_id,
            r.total_us as f64 / 1e6
        ));
    }
    out
}

/// Parse one raw key from the counts map into a Record (total_us filled separately).
fn parse_key(key: &[u8], total_us: u64) -> Result<Record> {
    if key.len() != KEY_SIZE {
        bail!("unexpected key size {} (want {})", key.len(), KEY_SIZE);
    }
    let pid = u32::from_ne_bytes(key[0..4].try_into().unwrap());
    let kernel_stack_id = i64::from_ne_bytes(key[8..16].try_into().unwrap());
    let user_stack_id = i64::from_ne_bytes(key[16..24].try_into().unwrap());
    let comm_bytes = &key[24..40];
    let end = comm_bytes
        .iter()
        .position(|&b| b == 0)
        .unwrap_or(comm_bytes.len());
    let comm = String::from_utf8_lossy(&comm_bytes[..end]).into_owned();
    Ok(Record {
        pid,
        kernel_stack_id,
        user_stack_id,
        comm,
        total_us,
    })
}

/// Look up a stack id in the stackmap and symbolize each address.
fn print_stack(map: &libbpf::Map, stack_id: i64, ksyms: &Ksyms) {
    if stack_id < 0 {
        // Negative id is the -errno from bpf_get_stackid (e.g. -EFAULT).
        println!("    [stack unavailable: errno {}]", -stack_id);
        return;
    }
    let id_key = (stack_id as u32).to_ne_bytes();
    let raw = match map.lookup(&id_key, libbpf::MapFlags::ANY) {
        Ok(Some(v)) => v,
        _ => {
            println!("    [stack id {} not found]", stack_id);
            return;
        }
    };
    for chunk in raw.chunks_exact(8) {
        let addr = u64::from_ne_bytes(chunk.try_into().unwrap());
        if addr == 0 {
            break;
        }
        println!("    {}", ksyms.symbolize(addr));
    }
}

/// Minimal kernel symbolizer backed by /proc/kallsyms.
struct Ksyms {
    /// Sorted (address, name) pairs; address 0 entries removed.
    syms: Vec<(u64, String)>,
}

impl Ksyms {
    fn load() -> Ksyms {
        let mut syms: Vec<(u64, String)> = Vec::new();
        if let Ok(text) = std::fs::read_to_string("/proc/kallsyms") {
            for line in text.lines() {
                let mut parts = line.split_whitespace();
                let (Some(addr_s), Some(_ty), Some(name)) =
                    (parts.next(), parts.next(), parts.next())
                else {
                    continue;
                };
                if let Ok(addr) = u64::from_str_radix(addr_s, 16) {
                    if addr != 0 {
                        syms.push((addr, name.to_string()));
                    }
                }
            }
        }
        syms.sort_unstable_by_key(|(addr, _)| *addr);
        Ksyms { syms }
    }

    fn symbolize(&self, addr: u64) -> String {
        // Find the greatest symbol address <= addr.
        match self.syms.binary_search_by(|(a, _)| a.cmp(&addr)) {
            Ok(i) => self.syms[i].1.clone(),
            Err(0) => "[unknown]".to_string(),
            Err(i) => self.syms[i - 1].1.clone(),
        }
    }
}

fn print_report(obj: &libbpf::Object, top: usize) -> Result<()> {
    let counts = obj
        .maps()
        .find(|m| m.name() == "counts")
        .expect("counts map not found in BPF object");
    let stackmap = obj
        .maps()
        .find(|m| m.name() == "stackmap")
        .expect("stackmap not found in BPF object");

    // Drain the counts map into records.
    let mut records: Vec<Record> = Vec::new();
    for key in counts.keys() {
        if let Some(val) = counts.lookup(&key, libbpf::MapFlags::ANY)? {
            if val.len() == 8 {
                let total_us = u64::from_ne_bytes(val[..8].try_into().unwrap());
                records.push(parse_key(&key, total_us)?);
            }
        }
    }

    if records.is_empty() {
        println!("No data yet.");
        return Ok(());
    }

    // Sort by total off-CPU time, descending.
    records.sort_by_key(|r| std::cmp::Reverse(r.total_us));
    if top > 0 && records.len() > top {
        records.truncate(top);
    }

    let ksyms = Ksyms::load();

    for rec in &records {
        // Kernel stack first, then user stack (not symbolized; addresses only).
        if rec.kernel_stack_id >= 0 {
            print_stack(&stackmap, rec.kernel_stack_id, &ksyms);
        }
        if rec.user_stack_id >= 0 {
            let _ = &ksyms; // user addresses are printed raw below
            let id_key = (rec.user_stack_id as u32).to_ne_bytes();
            if let Ok(Some(raw)) = stackmap.lookup(&id_key, libbpf::MapFlags::ANY) {
                let mut printed = 0;
                for chunk in raw.chunks_exact(8) {
                    let addr = u64::from_ne_bytes(chunk.try_into().unwrap());
                    if addr == 0 {
                        break;
                    }
                    println!("    [user 0x{:x}]", addr);
                    printed += 1;
                    if printed >= MAX_STACK_DEPTH {
                        break;
                    }
                }
            }
        }
        println!(
            "    -                {} ({})",
            if rec.comm.is_empty() {
                "[unknown]"
            } else {
                &rec.comm
            },
            rec.pid
        );
        println!("        {}", rec.total_us);
        println!();
    }

    Ok(())
}
