// ============================================================
// src/knmi/extract.rs — NetCDF-verwerking (ongewijzigd t.o.v. de
// werkende versie met netcdf 0.12.1)
// ============================================================

use super::Reading;
use chrono::{Duration as ChDuration, NaiveDateTime};
use netcdf::Extents;
use tracing::{debug, info, trace};

#[derive(Debug, thiserror::Error)]
pub enum ExtractError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("netcdf: {0}")]
    Netcdf(#[from] netcdf::Error),
    #[error("variabele '{0}' ontbreekt in het bestand")]
    Missing(String),
    #[error("onverwachte shape van variabele '{0}': {1}")]
    Shape(String, String),
    #[error("tijdseenheid niet te parseren: {0}")]
    TimeUnits(String),
}

/// Kandidaten voor de temperatuurvariabele, in volgorde van voorkeur.
const TEMP_VARS: &[&str] = &["ta", "air_temperature", "temperature", "temp"];

/// Haal uit de NetCDF-bytes de temperatuur van het dichtstbijzijnde
/// station. Geeft (tijdstip, temperatuur °C) paren.
pub fn extract_temperature(bytes: &[u8], lat: f64, lon: f64) -> Result<Vec<Reading>, ExtractError> {
    let mut tmp = tempfile::Builder::new()
        .prefix("knmi10min")
        .suffix(".nc")
        .tempfile()?;
    std::io::Write::write_all(&mut tmp, bytes)?;
    let path = tmp.path().to_string_lossy().to_string();
    info!("extract_temperature: tijdelijk bestand {}", path);
    extract_from_path(&path, lat, lon)
}

fn extract_from_path(path: &str, lat: f64, lon: f64) -> Result<Vec<Reading>, ExtractError> {
    let file = netcdf::open(path)?;

    // 1. Stationcoördinaten en dichtstbijzijnde station.
    let lats: Vec<f64> = read_var(&file, "lat")?;
    let lons: Vec<f64> = read_var(&file, "lon")?;
    if lats.len() != lons.len() || lats.is_empty() {
        return Err(ExtractError::Shape(
            "lat/lon".into(),
            format!("{} vs {}", lats.len(), lons.len()),
        ));
    }
    let station_idx = lats
        .iter()
        .zip(&lons)
        .map(|(a, b)| dist2(*a, *b, lat, lon))
        .enumerate()
        .min_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
        .map(|(i, _)| i)
        .ok_or_else(|| ExtractError::Missing("stations".into()))?;

    info!(
        "Dichtstbijzijnde station: index {} (lat {}, lon {})",
        station_idx, lats[station_idx], lons[station_idx]
    );

    // 2. Station-id bij die index (voor de CSV-kolom 'station').
    let station = read_station_id(&file, station_idx);
    trace!(station = %station, idx = station_idx, "dichtstbijzijnde station");

    // 3. Tijdas: get_values + Extents::All; units via attribute_value.
    let time_var = file
        .variable("time")
        .ok_or_else(|| ExtractError::Missing("time".into()))?;
    let tvals: Vec<f64> = time_var.get_values(Extents::All)?;
    info!("{} tijdstippen in het bestand", tvals.len());

    let units: Option<String> = match time_var.attribute_value("units") {
        Some(Ok(v)) => v.try_into().ok(),
        Some(Err(_)) => None,
        None => None,
    };
    let units =
        units.ok_or_else(|| ExtractError::TimeUnits("geen/ongeldige units-attribute".into()))?;
    info!("Unit van de tijdvariabele: {}", units);

    let epoch = parse_units(&units)?;

    // 4. Temperatuurvariabele: hele variabele in één keer lezen
    //    (één bestand = één tijdstip × alle stations, dus klein).
    let temp_name = TEMP_VARS
        .iter()
        .find(|name| file.variable(name).is_some())
        .ok_or_else(|| ExtractError::Missing("temperatuurvariabele (ta, ...)".into()))?;
    let temp_var = file.variable(temp_name).unwrap();
    let temps: Vec<f64> = temp_var.get_values(Extents::All)?;

    let n_stations = lats.len();
    let mut out = Vec::with_capacity(tvals.len());
    for (t_i, tv) in tvals.iter().enumerate() {
        let idx = t_i * n_stations + station_idx;
        if let Some(v) = temps.get(idx) {
            if v.is_finite() {
                out.push(Reading {
                    timestamp: epoch + ChDuration::seconds(*tv as i64),
                    station: station.clone(),
                    celsius: *v,
                });
            }
        }
    }
    Ok(out)
}

/// Leest station_id op de gegeven index. Probeert eerst numeriek
/// (meest voorkomend), anders string, anders "onbekend".
fn read_station_id(file: &netcdf::File, idx: usize) -> String {
    if let Some(v) = file.variable("station_id") {
        if let Ok(vals) = v.get_values::<i32, _>(Extents::All) {
            if let Some(s) = vals.get(idx) {
                return format!("{s}");
            }
        }
        if let Ok(s) = v.get_string(Extents::from(&[idx..idx + 1])) {
            return s;
        }
    }
    "onbekend".into()
}

fn read_var(file: &netcdf::File, name: &str) -> Result<Vec<f64>, ExtractError> {
    let var = file
        .variable(name)
        .ok_or_else(|| ExtractError::Missing(name.into()))?;
    Ok(var.get_values(Extents::All)?)
}

/// "seconds since 1970-01-01 00:00:00" -> epoch als NaiveDateTime.
fn parse_units(units: &str) -> Result<NaiveDateTime, ExtractError> {
    let rest = units
        .strip_prefix("seconds since ")
        .or_else(|| units.strip_prefix("second since "))
        .ok_or_else(|| ExtractError::TimeUnits(units.to_string()))?;
    let d = rest.trim();
    for fmt in ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M:%S UTC", "%Y-%m-%d"] {
        if let Ok(dt) = NaiveDateTime::parse_from_str(d, fmt) {
            return Ok(dt);
        }
        if let Ok(d0) = chrono::NaiveDate::parse_from_str(d, fmt) {
            return Ok(d0.and_hms_opt(0, 0, 0).unwrap());
        }
    }
    Err(ExtractError::TimeUnits(units.to_string()))
}

/// Kwadratische afstand (goed genoeg om het dichtstbijzijnde
/// station te vinden op de schaal van Nederland).
fn dist2(a_lat: f64, a_lon: f64, b_lat: f64, b_lon: f64) -> f64 {
    let dlat = a_lat - b_lat;
    let dlon = (a_lon - b_lon) * a_lat.to_radians().cos();
    dlat * dlat + dlon * dlon
}
