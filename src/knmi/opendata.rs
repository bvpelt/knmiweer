// ============================================================
// src/knmi/opendata.rs — KNMI Open Data API v1
// ============================================================

use serde::Deserialize;
use std::time::Duration;
use tracing::{info, trace};

/// Let op de trailing slash: Url::join() vervangt anders het
/// laatste segment ("v1") van de basis.
pub const BASE: &str = "https://api.dataplatform.knmi.nl/open-data/v1/";
pub const DATASET_10MIN: &str = "10-minute-in-situ-meteorological-observations";
pub const VERSION: &str = "1.0";
pub const PAGE_SIZE: usize = 250;

/// Bestandsnaam-prefix van deze dataset:
/// KMDS__OPER_P___10M_OBS_L2_YYYYMMDDHHMM.nc
pub const FILE_PREFIX: &str = "KMDS__OPER_P___10M_OBS_L2_";

#[derive(Debug, thiserror::Error)]
pub enum OpenDataError {
    #[error("http: {0}")]
    Http(#[from] reqwest::Error),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("url: {0}")]
    Url(#[from] url::ParseError),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("API-fout (HTTP {status}): {body}")]
    Api {
        status: reqwest::StatusCode,
        body: String,
    },
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FileListResponse {
    #[serde(default)]
    files: Vec<FileEntry>,
    #[serde(default)]
    next_page_token: Option<String>,
}

#[derive(Debug, Deserialize)]
struct FileEntry {
    filename: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DownloadUrlResponse {
    temporary_download_url: String,
}

pub struct KnmiOpenData {
    http: reqwest::blocking::Client,
    api_key: String,
}

impl KnmiOpenData {
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

    /// Alle bestanden ná `after` (exclusief), oplopend, tot max `max` stuks.
    /// Paginatie via startAfterFilename: de cursor is de laatst
    /// opgehaalde bestandsnaam zelf (mag niet gecombineerd worden met
    /// orderBy/sorting/begin/end/nextPageToken volgens de API).
    pub fn list_files_after(&self, after: &str, max: usize) -> Result<Vec<String>, OpenDataError> {
        let mut files: Vec<String> = Vec::new();
        let mut cursor: String = after.to_string();

        loop {
            if files.len() >= max {
                break;
            }

            let page_size = std::cmp::min(PAGE_SIZE, max - files.len());
            let mut url = reqwest::Url::parse(BASE)?.join(&format!(
                "datasets/{DATASET_10MIN}/versions/{VERSION}/files"
            ))?;
            {
                let mut q = url.query_pairs_mut();
                q.append_pair("maxKeys", &page_size.to_string());
                q.append_pair("startAfterFilename", &cursor);
                // GEEN orderBy/sorting/begin/end/nextPageToken hier
            }

            let page: FileListResponse = self.get_json(url)?;

            if page.files.is_empty() {
                break; // dataset op (of verder dan de cursor)
            }

            // Onthoud de laatste naam vóór we ze verplaatsen.
            let last = page
                .files
                .last()
                .map(|f| f.filename.clone())
                .expect("files is niet leeg");
            info!(
                "Pagina opgehaald: {} bestanden, laatste: {}",
                page.files.len(),
                last
            );

            let truncated = page.next_page_token.is_some();

            for f in page.files {
                if files.len() >= max {
                    break;
                }
                files.push(f.filename);
            }

            if !truncated || files.len() >= max {
                break;
            }
            cursor = last; // volgende pagina start ná dit bestand
        }
        trace!("{:?} bestanden opgehaald", files);
        Ok(files)
    }

    /// Eén bestand downloaden via de tijdelijke signed URL
    /// (5 minuten geldig; de download zelf heeft geen API-key nodig).
    pub fn download_file(&self, filename: &str) -> Result<Vec<u8>, OpenDataError> {
        let url = reqwest::Url::parse(BASE)?.join(&format!(
            "datasets/{DATASET_10MIN}/versions/{VERSION}/files/{filename}/url"
        ))?;
        info!("download_file: {}", url);
        let resp: DownloadUrlResponse = self.get_json(url)?;

        let bytes = self
            .http
            .get(resp.temporary_download_url)
            .send()?
            .error_for_status()?
            .bytes()?;
        Ok(bytes.to_vec())
    }

    fn get_json<T: serde::de::DeserializeOwned>(
        &self,
        url: reqwest::Url,
    ) -> Result<T, OpenDataError> {
        let resp = self
            .http
            .get(url)
            .header("Authorization", &self.api_key)
            .send()?;
        let status = resp.status();
        let body = resp.text()?;
        if !status.is_success() {
            return Err(OpenDataError::Api {
                status,
                body: body.chars().take(300).collect(),
            });
        }
        Ok(serde_json::from_str(&body)?)
    }
}
