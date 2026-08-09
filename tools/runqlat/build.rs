use libbpf_cargo::SkeletonBuilder;
use std::path::PathBuf;
use std::process::Command;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let out_dir = PathBuf::from(std::env::var("OUT_DIR")?);

    // Generate vmlinux.h from kernel BTF if it doesn't exist.
    let vmlinux_path = PathBuf::from("src/bpf/vmlinux.h");
    if !vmlinux_path.exists() {
        let status = Command::new("bpftool")
            .args([
                "btf",
                "dump",
                "file",
                "/sys/kernel/btf/vmlinux",
                "format",
                "c",
            ])
            .stdout(std::fs::File::create(&vmlinux_path)?)
            .status()?;
        if !status.success() {
            return Err("Failed to generate vmlinux.h from kernel BTF".into());
        }
    }

    // Build the BPF program and generate the skeleton.
    SkeletonBuilder::new()
        .source("src/bpf/runqlat.bpf.c")
        .clang_args(["-Isrc/bpf", "-I/usr/include"])
        .build_and_generate(out_dir.join("runqlat.skel.rs"))?;

    println!("cargo:rerun-if-changed=src/bpf/runqlat.bpf.c");
    println!("cargo:rerun-if-changed=src/bpf/vmlinux.h");
    Ok(())
}
