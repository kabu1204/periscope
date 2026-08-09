//! Minimal Prometheus /metrics HTTP exporter, shared by the periscope eBPF tools.
//!
//! Hand-rolled (no external crates) per the M2 coding standards and the P-001
//! proposal: a blocking listener that serves `GET /metrics` with a caller-rendered
//! Prometheus text body, and 404 for anything else. A sequential accept loop is
//! sufficient because Prometheus scrapes on a 15s interval.

use std::io::{Read, Write};
use std::net::TcpListener;

/// Serve Prometheus metrics on `addr` forever, calling `render` on each scrape.
///
/// `render` is invoked once per `GET /metrics` request and must return the full
/// Prometheus text-format body. This function never returns under normal
/// operation; the process is expected to be killed (SIGINT/SIGTERM) to stop it.
pub fn serve<F>(addr: &str, render: F) -> std::io::Result<()>
where
    F: Fn() -> String,
{
    let listener = TcpListener::bind(addr)?;
    eprintln!("Exporter listening on {addr} (GET /metrics)");
    for stream in listener.incoming() {
        match stream {
            Ok(mut s) => {
                // Best-effort per-connection handling; a slow/failed client must
                // not take down the exporter, so errors are ignored.
                let _ = handle(&mut s, &render);
            }
            Err(_) => continue,
        }
    }
    Ok(())
}

fn handle<F>(stream: &mut std::net::TcpStream, render: &F) -> std::io::Result<()>
where
    F: Fn() -> String,
{
    let mut buf = [0u8; 2048];
    let n = stream.read(&mut buf)?;
    let req = String::from_utf8_lossy(&buf[..n]);
    // Only the request line's method and path matter.
    let mut parts = req.split_whitespace();
    let method = parts.next().unwrap_or("");
    let path = parts.next().unwrap_or("");

    if method == "GET" && (path == "/metrics" || path == "/") {
        let body = render();
        let resp = format!(
            "HTTP/1.0 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\nContent-Length: {}\r\n\r\n{}",
            body.len(),
            body
        );
        stream.write_all(resp.as_bytes())?;
    } else {
        let body = "not found\n";
        let resp = format!(
            "HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: {}\r\n\r\n{}",
            body.len(),
            body
        );
        stream.write_all(resp.as_bytes())?;
    }
    stream.flush()?;
    Ok(())
}
