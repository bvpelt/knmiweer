// ============================================================
// src/knmi/sink.rs — uitvoer-abstractie: CSV of Postgres
// ============================================================

use super::Reading;
use chrono::{NaiveDate, NaiveTime};
use postgres::{Client, NoTls, Statement};
use tracing::debug;

#[derive(Debug, thiserror::Error)]
pub enum SinkError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("postgres: {0}")]
    Pg(#[from] postgres::Error),
}

/// Één uitvoerdoel. `write` geeft het aantal NIEUW toegevoegde
/// rijen terug (dubbele rijen worden overgeslagen).
pub trait Sink {
    fn write(&mut self, rows: &[Reading]) -> Result<usize, SinkError>;
}

// ------------------------------------------------------------
// CSV (bestaande logica, nu achter de Sink-trait)
// ------------------------------------------------------------

pub struct CsvSink {
    path: String,
    sep: u8,
    seen: std::collections::HashSet<(String, String)>,
}

impl CsvSink {
    /// Leest bestaande rijen in als dedup-sleutels.
    pub fn new(path: &str, sep: u8) -> Result<Self, SinkError> {
        let seen = super::csv_out::existing_keys(path)?;
        Ok(Self {
            path: path.to_string(),
            sep,
            seen,
        })
    }
}

impl Sink for CsvSink {
    fn write(&mut self, rows: &[Reading]) -> Result<usize, SinkError> {
        let nieuw: Vec<Reading> = rows
            .iter()
            .filter(|r| self.seen.insert(super::csv_out::row_key(r)))
            .cloned()
            .collect();
        if nieuw.is_empty() {
            debug!("CSV: alle metingen stonden er al in");
            return Ok(0);
        }
        super::csv_out::append_rows(&self.path, self.sep, &nieuw)?;
        Ok(nieuw.len())
    }
}

// ------------------------------------------------------------
// Postgres: database weerdata, tabel metingen
// ------------------------------------------------------------

pub struct PgSink {
    client: Client,
    insert: Statement,
}

impl PgSink {
    /// Verbindt met de database en prepares de insert-statement.
    /// Verwacht dat de tabel `metingen` al bestaat.
    pub fn connect(url: &str) -> Result<Self, SinkError> {
        let mut client = Client::connect(url, NoTls)?;
        let insert = client.prepare(
            "INSERT INTO metingen (datum, tijd, station, temperature) \
             VALUES ($1, $2, $3, $4::text::numeric) \
             ON CONFLICT (station, datum, tijd) DO NOTHING",
        )?;
        Ok(Self { client, insert })
    }
}

impl Sink for PgSink {
    fn write(&mut self, rows: &[Reading]) -> Result<usize, SinkError> {
        if rows.is_empty() {
            return Ok(0);
        }
        let mut nieuw = 0usize;

        let mut tx = self.client.transaction()?;
        for r in rows {
            let datum: NaiveDate = r.timestamp.date();
            let tijd: NaiveTime = r.timestamp.time();
            let temp = format!("{:.2}", r.celsius);

            let n = tx.execute(&self.insert, &[&datum, &tijd, &r.station, &temp])?;
            nieuw += n as usize;
        }
        tx.commit()?;

        if nieuw == 0 {
            debug!("DB: alle metingen stonden er al in");
        }
        Ok(nieuw)
    }
}
