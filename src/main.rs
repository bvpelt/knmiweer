mod knmi;
use clap::Parser;
use clap::ValueEnum;
use knmi::edr::EdrError;
use knmi::opendata::KnmiOpenData;
use knmi::sink::{CsvSink, PgSink, Sink};
use knmi::state::{State, first_filename_of_day_before};
use tracing::{debug, error, info, warn};
use tracing_subscriber::EnvFilter;

/// Exit-codes voor scripting: 0 ok, 1 algemene fout, 2 ongeldige
/// datum, 3 quota overschreden, 4 geen data voor deze dag.
mod exitcode {
    pub const FOUT: i32 = 1;
    pub const ONGELDIGE_DATUM: i32 = 2;
    pub const QUOTA: i32 = 3;
    pub const GEEN_DATA: i32 = 4;
}

/// Geen enkel naburig station had data (niet hetzelfde als een fout).
#[derive(Debug, thiserror::Error)]
#[error("geen van de dichtstbijzijnde stations heeft temperatuurdata voor deze dag")]
struct GeenDataError;

#[derive(Parser, Debug)]
#[command(
    author,
    version,
    about = "KNMI 10-minuutstemperatuur naar CSV of Postgres (Open Data of EDR API)"
)]
struct Args {
    /// Startdag voor de EERSTE run (YYYY-MM-DD), als er nog geen state is.
    /// Bij een bestaande state wordt deze genegeerd.
    #[arg(short, long)]
    date: Option<String>,

    /// Databron: opendata (bestandssync) of edr (dagquery)
    #[arg(long, value_enum, default_value_t = Source::Edr)]
    source: Source,

    /// Uitvoerdoel: csv-bestand of postgres-database
    #[arg(long, value_enum, default_value_t = Storage::Database)]
    storage: Storage,

    /// Breedtegraad van de locatie (default: Veenendaal)
    #[arg(long, default_value_t = 52.030)]
    lat: f64,

    /// Lengtegraad van de locatie
    #[arg(long, default_value_t = 5.553)]
    lon: f64,

    /// CSV-uitvoerbestand (alleen bij --storage csv)
    #[arg(short, long, default_value = "temperatuur.csv")]
    output: String,

    /// Postgres-connectiestring (alleen bij --storage database).
    /// Default: $KNMI_PG_URL, anders postgresql://postgres@localhost/weerdata
    #[arg(short = 'D', long)]
    pg_url: Option<String>,

    /// Statebestand met de laatst verwerkte bestandsnaam
    #[arg(short, long, default_value = "knmi_state.json")]
    state: String,

    /// CSV-scheidingsteken (Excel NL verwacht vaak ';')
    #[arg(long, default_value = ";")]
    sep: String,

    /// Maximaal aantal bestanden per run (144 = één dag 10-min data)
    #[arg(short, long, default_value_t = 144)]
    max_files: usize,

    /// Logniveau (error, warn, info, debug, trace)
    #[arg(short = 'L', long, default_value = "info")]
    log_level: String,

    /// Locatie-wijziging toch toestaan (op eigen risico)
    #[arg(long)]
    force: bool,
}

#[derive(Clone, Debug, ValueEnum)]
enum Source {
    Opendata,
    Edr,
}

#[derive(Clone, Debug, ValueEnum)]
enum Storage {
    Csv,
    Database,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::new(&args.log_level))
        .init();

    // Invoervalidatie vóór alles: --date moet een geldige
    // kalenderdatum in YYYY-MM-DD zijn.
    if let Some(d) = &args.date {
        if chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").is_err() {
            error!(
                "Fout: ongeldige startdatum '{d}' — gebruik een geldige kalenderdatum in formaat YYYY-MM-DD"
            );
            std::process::exit(exitcode::ONGELDIGE_DATUM);
        }
    }

    // 2. Sink pas ná validatie (geen DB-connectie bij foute invoer).
    let mut sink: Box<dyn knmi::sink::Sink> = match args.storage {
        Storage::Csv => {
            let sep = args.sep.as_bytes().first().copied().unwrap_or(b',');
            Box::new(CsvSink::new(&args.output, sep)?)
        }
        Storage::Database => {
            let url = args
                .pg_url
                .clone()
                .or_else(|| std::env::var("KNMI_PG_URL").ok())
                .unwrap_or_else(|| "postgresql://postgres@localhost/weerdata".to_string());
            info!(doel = "weerdata", "verbinden met Postgres");
            Box::new(PgSink::connect(&url)?)
        }
    };

    // 3. Runnen en fouten op exit codes mappen.
    let result = match args.source {
        Source::Opendata => run_opendata(&args, sink.as_mut()),
        Source::Edr => run_edr(&args, sink.as_mut()),
    };

    if let Err(e) = result {
        if e.downcast_ref::<EdrError>()
            .is_some_and(|x| matches!(x, EdrError::QuotaExceeded))
        {
            error!(
                "KNMI-quota overschreden — stoppen. Overweeg minder aanvragen per tijdseenheid."
            );
            std::process::exit(exitcode::QUOTA);
        }
        if e.downcast_ref::<GeenDataError>().is_some() {
            warn!("geen station met data voor deze dag — dag overslaan");
            std::process::exit(exitcode::GEEN_DATA);
        }

        // Alle overige fouten: expliciet exit 1 met de foutenketen.
        error!("onherstelbare fout: {e}");
        let mut bron = std::error::Error::source(&*e);
        while let Some(b) = bron {
            error!("  veroorzaakt door: {b}");
            bron = b.source();
        }
        std::process::exit(exitcode::FOUT);
    }
    Ok(())
}

// ------------------------------------------------------------
// Open Data API — incrementele bestandssync
// ------------------------------------------------------------
fn run_opendata(args: &Args, sink: &mut dyn Sink) -> Result<(), Box<dyn std::error::Error>> {
    let client = KnmiOpenData::new(std::env::var("KNMI_API_KEY")?);
    let mut state = State::load(&args.state)?;
    check_loc(&state, args)?;

    // 1. Waar starten we: state, --date, of fout.
    let start_after: String = match (state.last_filename(), &args.date) {
        (Some(last), _) => {
            info!(laatste = %last, "bestaande state, vervolg hiermee");
            last.clone()
        }
        (None, Some(date)) => {
            let first = first_filename_of_day_before(date)?;
            info!(vanaf = %date, "geen state, eerste run");
            first
        }
        (None, None) => {
            warn!(
                "nog geen state. Geef voor de eerste run een startdag op: \
                 cargo run -- --date 2026-10-01"
            );
            return Ok(());
        }
    };

    // 2. Bestandslijst na de laatst verwerkte naam.
    let files = client.list_files_after(&start_after, args.max_files)?;
    info!(aantal = files.len(), "nieuwe bestanden opgehaald");
    if files.is_empty() {
        info!("niets te doen — dataset is bijgewerkt");
        return Ok(());
    }

    // 3. Per bestand: download -> extract -> sink -> state.
    let mut total_rows = 0usize;
    for filename in files.iter() {
        let bytes = client.download_file(filename)?;
        match knmi::extract::extract_temperature(&bytes, args.lat, args.lon) {
            Ok(rows) => {
                let nieuw = sink.write(&rows)?;
                total_rows += nieuw;
                if nieuw > 0 {
                    debug!(bestand = %filename, metingen = nieuw, "verwerkt");
                } else {
                    debug!(bestand = %filename, "alle metingen bestonden al");
                }
            }
            Err(e) => {
                error!(
                    bestand = %filename,
                    fout = %e,
                    "WEGSCHRIJVEN MISLUKT — state NIET opgeslagen, \
                     dit bestand wordt bij herstart opnieuw verwerkt"
                );
                // Wegschrijven is structureel (database weg,
                // schijf vol): stoppen, niet doorgaan.
                return Err(e.into());
            }
        }
        state.set_last_filename(filename.clone());
        state.set_loc(args.lat, args.lon);
        state.save(&args.state)?;
    }

    info!(
        rijen = total_rows,
        laatste = state.last_filename().cloned().unwrap_or_default(),
        "klaar (opendata)"
    );
    Ok(())
}

// ------------------------------------------------------------
// EDR API — dagquery, incrementeel per dag
// ------------------------------------------------------------
fn run_edr(args: &Args, sink: &mut dyn Sink) -> Result<(), Box<dyn std::error::Error>> {
    let client = knmi::edr::KnmiEdr::new(std::env::var("KNMI_EDR_API_KEY")?);
    let mut state = State::load(&args.state)?;
    check_loc(&state, args)?;

    // 1. Welke dag? --date wint; anders de dag na de laatste edr-run.
    let day = match &args.date {
        Some(d) => d.clone(),
        None => match state.last_edr_day() {
            Some(last) => {
                let next = chrono::NaiveDate::parse_from_str(last, "%Y-%m-%d")?
                    .succ_opt()
                    .ok_or("datum na laatste run valt buiten bereik")?;
                next.format("%Y-%m-%d").to_string()
            }
            None => {
                warn!(
                    "nog geen state en geen --date. Geef een startdag op: \
                     cargo run --source edr --date 2026-10-01"
                );
                return Ok(());
            }
        },
    };

    // 2. Dichtstbijzijnde stations op afstand proberen tot er data is.
    let mut rows: Option<Vec<knmi::Reading>> = None;
    let mut station_used = String::new();

    for (station, _afstand) in client
        .nearest_stations(args.lon, args.lat)?
        .into_iter()
        .take(3)
    {
        info!(dag = %day, station = %station, "EDR-query");
        match client.temperature_for_day(&day, &station, args.lat, args.lon) {
            Ok(r) if !r.is_empty() => {
                rows = Some(r);
                station_used = station;
                break;
            }
            Ok(_) => warn!(station = %station, "lege reeks, volgend station proberen"),
            // Quota is niet station-gebonden: meteen stoppen, state NIET bijwerken.
            Err(EdrError::QuotaExceeded) => return Err(EdrError::QuotaExceeded.into()),
            Err(e) => warn!(station = %station, fout = %e, "mislukt, volgend station proberen"),
        }
    }

    let rows = match rows {
        Some(r) => r,
        None => {
            // Geen enkel station had data. Daar kan het programma niets
            // aan veranderen: de dag telt als verwerkt, zodat een run
            // zonder --date naar de VOLGENDE dag gaat in plaats van
            // eeuwig op deze dag te blijven steken.
            state.set_last_edr_day(day.clone());
            state.set_loc(args.lat, args.lon);
            state.save(&args.state)?;
            warn!(dag = %day, "geen station met data — dag gemarkeerd als verwerkt");
            return Err(GeenDataError.into());
        }
    };
    info!(station = %station_used, "station met data gevonden");

    // 3. Wegschrijven + state bijwerken.
    let nieuw = sink.write(&rows).map_err(|e| {
        error!(
            dag = %day,
            station = %station_used,
            fout = %e,
            "WEGSCHRIJVEN MISLUKT — dag NIET in de state opgeslagen, \
             transactie teruggedraaid. Run later opnieuw met: \
             cargo run -- --date {day}"
        );
        e
    })?;
    if nieuw == 0 {
        info!("alle metingen voor deze dag bestonden al — niets toegevoegd");
    }
    // Pas hier, ná succesvol wegschrijven:
    state.set_last_edr_day(day.clone());
    state.set_loc(args.lat, args.lon);
    state.save(&args.state)?;

    info!(
        rijen = nieuw,
        dag = %day,
        station = %station_used,
        "klaar (edr)"
    );
    Ok(())
}

fn check_loc(state: &knmi::state::State, args: &Args) -> Result<(), Box<dyn std::error::Error>> {
    if let Some((slat, slon)) = state.loc() {
        if (slat - args.lat).abs() > 1e-6 || (slon - args.lon).abs() > 1e-6 {
            if !args.force {
                return Err(format!(
                    "Deze state hoort bij locatie ({slat}, {slon}), \
                     maar je vroeg ({}, {}). Gebruik een apart --state, \
                     of geef --force als dit echt de bedoeling is.",
                    args.lat, args.lon
                )
                .into());
            }
            warn!("locatie verschilt van de state, --force gegeven");
        }
    }
    Ok(())
}
