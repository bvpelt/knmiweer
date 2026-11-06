// ============================================================
// src/knmi/csv_out.rs — CSV voor spreadsheets (append-modus)
// ============================================================

use super::Reading;
use std::collections::HashSet;
use std::io::Write;
use std::path::Path;

/// Voegt rijen toe aan de CSV. Bestaat het bestand nog niet, dan
/// krijgt het een UTF-8 BOM (Excel herkent dit) en een headerregel.
/// Kolommen: date,time,station,temperature
pub fn append_rows(path: &str, sep: u8, rows: &[Reading]) -> Result<(), std::io::Error> {
    let is_new = !Path::new(path).exists();

    let mut w = std::io::BufWriter::new(
        std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)?,
    );

    if is_new {
        w.write_all(&[0xEF, 0xBB, 0xBF])?; // UTF-8 BOM
        writeln!(
            w,
            "date{}time{}station{}temperature",
            sep as char, sep as char, sep as char
        )?;
    }

    for r in rows {
        writeln!(
            w,
            "{}{}{}{}{}{}{:.2}",
            r.timestamp.format("%Y-%m-%d"),
            sep as char,
            r.timestamp.format("%H:%M:%S"),
            sep as char,
            r.station,
            sep as char,
            r.celsius
        )?;
    }
    w.flush()?;
    Ok(())
}

/// Sleutel van één rij: (tijdstip, station).
pub fn row_key(r: &Reading) -> (String, String) {
    (
        r.timestamp.format("%Y-%m-%dT%H:%M:%S").to_string(),
        r.station.clone(),
    )
}

/// Leest de al aanwezige rijen in de CSV als sleutels.
pub fn existing_keys(path: &str) -> Result<HashSet<(String, String)>, std::io::Error> {
    let mut set = HashSet::new();
    let Ok(f) = std::fs::File::open(path) else {
        return Ok(set); // bestaat nog niet -> lege set
    };
    for line in std::io::BufRead::lines(std::io::BufReader::new(f)) {
        let line = line?;
        // BOM en header overslaan
        if line.is_empty() || line.starts_with("date") {
            continue;
        }
        // kolommen: date,time,station,temperature
        let mut parts = line
            .trim_start_matches('\u{feff}')
            .split(|c| c == ',' || c == ';');
        if let (Some(d), Some(t), Some(s)) = (parts.next(), parts.next(), parts.next()) {
            set.insert((format!("{d}T{t}"), s.to_string()));
        }
    }
    Ok(set)
}
