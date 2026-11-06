// ============================================================
// src/knmi/edr.rs — KNMI EDR API v1
// (dichtstbijzijnde station zoeken + dagreeks als CoverageJSON)
// ============================================================

use super::Reading;
use chrono::{Duration as ChDuration, NaiveDate, NaiveDateTime};
use serde::Deserialize;
use std::collections::BTreeMap;
use std::time::Duration;
use tracing::trace;

/// Trailing slash vanwege Url::join()-semantiek.
pub const BASE: &str = "https://api.dataplatform.knmi.nl/edr/v1/";
pub const COLLECTION_10MIN: &str = "10-minute-in-situ-meteorological-observations";
pub const PARAM_TEMPERATURE: &str = "ta";

#[derive(Debug, thiserror::Error)]
pub enum EdrError {
    #[error("http: {0}")]
    Http(#[from] reqwest::Error),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("url: {0}")]
    Url(#[from] url::ParseError),
    #[error("API-fout (HTTP {status}): {body}")]
    Api {
        status: reqwest::StatusCode,
        body: String,
    },
    #[error("ongeldige datum '{0}' — gebruik YYYY-MM-DD")]
    BadDate(String),
    #[error("geen bruikbare response (CoverageJSON onvolledig): {0}")]
    BadShape(String),
    #[error("geen temperatuurwaarden gevonden")]
    NoData,
    #[error("KNMI-quota overschreden")]
    QuotaExceeded,
}

// ---------------- CoverageJSON (minimale parsing) ----------------

#[derive(Debug, Deserialize)]
struct CoverageCollection {
    #[serde(default)]
    coverages: Vec<Coverage>,
}

#[derive(Debug, Deserialize)]
struct Coverage {
    #[serde(default)]
    domain: Option<Domain>,
    #[serde(default)]
    ranges: BTreeMap<String, SerdeRange>,
}

#[derive(Debug, Deserialize)]
struct Domain {
    #[serde(default)]
    axes: BTreeMap<String, SerdeAxis>,
}

#[derive(Debug, Deserialize)]
struct SerdeAxis {
    #[serde(default)]
    values: Vec<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct SerdeRange {
    #[serde(default)]
    values: Vec<Option<f64>>,
}

// ---------------- Client ----------------

pub struct KnmiEdr {
    http: reqwest::blocking::Client,
    api_key: String,
}

impl KnmiEdr {
    pub fn new(api_key: String) -> Self {
        Self {
            http: reqwest::blocking::Client::builder()
                .user_agent("knmi-weather/0.1")
                .timeout(Duration::from_secs(120))
                .build()
                .expect("reqwest client"),
            api_key,
        }
    }

    /// Alle stations gesorteerd op afstand tot (lon, lat), dichtst eerst.
    /// Geeft (location-id, kwadratische afstand) paren.
    pub fn nearest_stations(&self, lon: f64, lat: f64) -> Result<Vec<(String, f64)>, EdrError> {
        let url = reqwest::Url::parse(BASE)?
            .join(&format!("collections/{COLLECTION_10MIN}/locations"))?;
        let geo: serde_json::Value = self.get_json(url)?;

        let mut stations: Vec<(String, f64)> = Vec::new();
        if let Some(features) = geo["features"].as_array() {
            for f in features {
                let Some(id) = f["id"].as_str() else { continue };
                let Some(c) = f["geometry"]["coordinates"].as_array() else {
                    continue;
                };
                let (Some(slon), Some(slat)) = (
                    c.first().and_then(|v| v.as_f64()),
                    c.get(1).and_then(|v| v.as_f64()),
                ) else {
                    continue;
                };
                stations.push((id.to_string(), dist2(slat, slon, lat, lon)));
            }
        }
        stations.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
        if stations.is_empty() {
            return Err(EdrError::BadShape("geen locations gevonden".into()));
        }
        Ok(stations)
    }

    /// Temperatuurreeks voor één dag (UTC) voor het gegeven station.
    /// Geeft Readings met daarin dezelfde station-id.
    pub fn temperature_for_day(
        &self,
        date: &str,
        station: &str,
        _lat: f64,
        _lon: f64,
    ) -> Result<Vec<Reading>, EdrError> {
        let d = NaiveDate::parse_from_str(date, "%Y-%m-%d")
            .map_err(|_| EdrError::BadDate(date.to_string()))?;
        let fmt = "%Y-%m-%dT%H:%M:%SZ";
        let begin = d.and_hms_opt(0, 0, 0).unwrap().format(fmt).to_string();
        let end = (d.and_hms_opt(0, 0, 0).unwrap() + ChDuration::days(1))
            .format(fmt)
            .to_string();

        let mut url = reqwest::Url::parse(BASE)?.join(&format!(
            "collections/{COLLECTION_10MIN}/locations/{station}"
        ))?;
        {
            let mut q = url.query_pairs_mut();
            q.append_pair("datetime", &format!("{begin}/{end}"));
            q.append_pair("parameter-name", PARAM_TEMPERATURE);
        }

        trace!(url = %url, "EDR-query");
        let json: serde_json::Value = self.get_json(url)?;
        //trace!(url = %url, "EDR-response binnengehaald");

        // De KNMI EDR levert óf een losse Coverage, óf een
        // CoverageCollection met coverages[]. Ondersteun beide.
        let coverages: Vec<Coverage> =
            if let Ok(coll) = serde_json::from_value::<CoverageCollection>(json.clone()) {
                if coll.coverages.is_empty() {
                    Vec::new()
                } else {
                    coll.coverages
                }
            } else {
                vec![
                    serde_json::from_value(json)
                        .map_err(|e| EdrError::BadShape(format!("geen CoverageJSON: {e}")))?,
                ]
            };

        let mut rows: Vec<Reading> = Vec::new();

        for cov in coverages {
            let Some(domain) = cov.domain else { continue };
            let Some(axis) = domain.axes.get("t").or_else(|| domain.axes.get("time")) else {
                continue;
            };

            let times: Vec<NaiveDateTime> = axis
                .values
                .iter()
                .filter_map(|v| v.as_str())
                .filter_map(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                .map(|dt| dt.naive_utc())
                .collect();

            let Some(range) = cov
                .ranges
                .get(PARAM_TEMPERATURE)
                .or_else(|| cov.ranges.values().next())
            else {
                continue;
            };

            if times.len() != range.values.len() {
                return Err(EdrError::BadShape(format!(
                    "lengtes komen niet overeen: {} tijdstippen vs {} waarden",
                    times.len(),
                    range.values.len()
                )));
            }

            rows.extend(
                times
                    .into_iter()
                    .zip(range.values.iter())
                    .filter_map(|(timestamp, c)| {
                        c.map(|celsius| Reading {
                            timestamp,
                            station: station.to_string(),
                            celsius,
                        })
                    }),
            );
        }

        if rows.is_empty() {
            return Err(EdrError::NoData);
        }
        Ok(rows)
    }

    fn get_json<T: serde::de::DeserializeOwned>(&self, url: reqwest::Url) -> Result<T, EdrError> {
        let resp = self
            .http
            .get(url)
            .header("Authorization", &self.api_key)
            .send()?;
        let status = resp.status();
        let body = resp.text()?;
        if !status.is_success() {
            // Quota: herkenbaar en niet herstelbaar door een ander station
            // te proberen — direct stoppen.
            if status == reqwest::StatusCode::FORBIDDEN && body.contains("Quota exceeded") {
                return Err(EdrError::QuotaExceeded);
            }
            return Err(EdrError::Api {
                status,
                body: body.chars().take(300).collect(),
            });
        }
        Ok(serde_json::from_str(&body)?)
    }
}

fn dist2(a_lat: f64, a_lon: f64, b_lat: f64, b_lon: f64) -> f64 {
    let dlat = a_lat - b_lat;
    let dlon = (a_lon - b_lon) * a_lat.to_radians().cos();
    dlat * dlat + dlon * dlon
}
