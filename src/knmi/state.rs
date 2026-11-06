// ============================================================
// src/knmi/state.rs — sync-state (laatst verwerkte bestand)
// ============================================================

use super::opendata::FILE_PREFIX;
use chrono::NaiveDate;

#[derive(Debug, thiserror::Error)]
pub enum StateError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("ongeldige datum '{0}' — gebruik YYYY-MM-DD")]
    BadDate(String),
}

#[derive(Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct State {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_filename: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_edr_day: Option<String>,
    /// Laatst gebruikte locatie; bewaking tegen per ongeluk
    /// andere --lat/--lon tegen dezelfde CSV.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    loc: Option<(f64, f64)>,
}

impl State {
    pub fn load(path: &str) -> Result<Self, StateError> {
        match std::fs::read_to_string(path) {
            Ok(text) => Ok(serde_json::from_str(&text)?),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(e.into()),
        }
    }

    pub fn save(&self, path: &str) -> Result<(), StateError> {
        let text = serde_json::to_string_pretty(self)?;
        std::fs::write(path, text)?;
        Ok(())
    }

    pub fn last_filename(&self) -> Option<&String> {
        self.last_filename.as_ref()
    }

    pub fn set_last_filename(&mut self, filename: String) {
        self.last_filename = Some(filename);
    }

    pub fn last_edr_day(&self) -> Option<&String> {
        self.last_edr_day.as_ref()
    }

    pub fn set_last_edr_day(&mut self, day: String) {
        self.last_edr_day = Some(day);
    }

    pub fn loc(&self) -> Option<(f64, f64)> {
        self.loc
    }

    pub fn set_loc(&mut self, lat: f64, lon: f64) {
        self.loc = Some((lat, lon));
    }
}

/// Bouwt de bestandsnaam van 00:00 op de dag VÓÓR `date`:
/// de eerste run met --date moet immers alles na die naam ophalen.
/// Voor --date 2026-10-01 wordt dit KMDS__OPER_P___10M_OBS_L2_202609300000.nc
pub fn first_filename_of_day_before(date: &str) -> Result<String, StateError> {
    let d = NaiveDate::parse_from_str(date, "%Y-%m-%d")
        .map_err(|_| StateError::BadDate(date.to_string()))?;
    let prev = d
        .pred_opt()
        .ok_or_else(|| StateError::BadDate(date.into()))?;
    Ok(format!("{}{}0000.nc", FILE_PREFIX, prev.format("%Y%m%d")))
}
