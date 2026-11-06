mod knmi;
use clap::Parser;
use clap::ValueEnum;
use knmi::Reading;
use knmi::opendata::KnmiOpenData;
use knmi::state::{State, first_filename_of_day_before};
use tracing::{debug, error, info, warn};
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(
    author,
    version,
    about = "KNMI 10-minuutstemperatuur als CSV (Open Data of EDR API)"
)]
struct Args {
    /// Startdag voor de EERSTE run (YYYY-MM-DD), als er nog geen state is.
    /// Bij een bestaande state wordt deze genegeerd.
    #[arg(short, long)]
    date: Option<String>,

    /// Databron: opendata (bestandssync) of edr (dagquery)
    #[arg(long, value_enum, default_value_t = Source::Opendata)]
    source: Source,

    /// Breedtegraad van de locatie (default: Veenendaal)
    #[arg(long, default_value_t = 52.030)]
    lat: f64,

    /// Lengtegraad van de locatie
    #[arg(long, default_value_t = 5.553)]
    lon: f64,

    /// CSV-uitvoerbestand (rijen worden toegevoegd)
    #[arg(short, long, default_value = "temperatuur.csv")]
    output: String,

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

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    // RUST_LOG bepaalt het niveau; default info.
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::new(&args.log_level))
        .init();

    let sep = args.sep.as_bytes().first().copied().unwrap_or(b',');

    match args.source {
        Source::Opendata => run_opendata(&args, sep)?,
        Source::Edr => run_edr(&args, sep)?,
    }
    Ok(())
}

// ------------------------------------------------------------
// Open Data API — incrementele bestandssync
// ------------------------------------------------------------
fn run_opendata(args: &Args, sep: u8) -> Result<(), Box<dyn std::error::Error>> {
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

    // 3. Per bestand: download -> extract -> CSV -> state.
    // Rerun-bescherming: rijen die al in de CSV staan worden overgeslagen.
    let mut seen = knmi::csv_out::existing_keys(&args.output)?;

    let mut total_rows = 0usize;
    for (i, filename) in files.iter().enumerate() {
        let bytes = client.download_file(filename)?;
        match knmi::extract::extract_temperature(&bytes, args.lat, args.lon) {
            Ok(rows) => {
                let nieuw: Vec<knmi::Reading> = rows
                    .into_iter()
                    .filter(|r| seen.insert(knmi::csv_out::row_key(r)))
                    .collect();
                if !nieuw.is_empty() {
                    knmi::csv_out::append_rows(&args.output, sep, &nieuw)?;
                    total_rows += nieuw.len();
                    debug!(bestand = %filename, metingen = nieuw.len(), "verwerkt");
                } else {
                    debug!(bestand = %filename, "alle metingen stonden er al in");
                }
            }
            Err(e) => {
                error!(bestand = %filename, fout = %e, "extract mislukt, ga door");
            }
        }
        state.set_last_filename(filename.clone());
        state.set_loc(args.lat, args.lon);
        state.save(&args.state)?;
    }

    info!(
        rijen = total_rows,
        laatste = state.last_filename().cloned().unwrap_or_default(),
        doel = &args.output,
        "klaar (opendata)"
    );
    Ok(())
}

// ------------------------------------------------------------
// EDR API — dagquery, incrementeel per dag
// ------------------------------------------------------------
fn run_edr(args: &Args, sep: u8) -> Result<(), Box<dyn std::error::Error>> {
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

    // 2. Dichtstbijzijnde station + temperatuurreeks voor die dag.
    // 2. Dichtstbijzijnde stations op afstand proberen tot er data is.
    let mut rows: Option<Vec<knmi::Reading>> = None;
    let mut station_used = String::new();
    // Rerun-bescherming: rijen die al in de CSV staan worden overgeslagen.
    let mut seen = knmi::csv_out::existing_keys(&args.output)?;

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
            Err(e) => warn!(station = %station, fout = %e, "mislukt, volgend station proberen"),
        }
    }

    let rows =
        rows.ok_or("geen van de dichtstbijzijnde stations heeft temperatuurdata voor deze dag")?;
    info!(station = %station_used, "station met data gevonden");
    let rows: Vec<Reading> = rows
        .into_iter()
        .filter(|r| seen.insert(knmi::csv_out::row_key(r)))
        .collect();
    if rows.is_empty() {
        info!("alle metingen voor deze dag stonden al in de CSV — niets toegevoegd");
        return Ok(());
    }
    // 3. CSV + state bijwerken.
    knmi::csv_out::append_rows(&args.output, sep, &rows)?;
    state.set_last_edr_day(day.clone());
    state.set_loc(args.lat, args.lon);
    state.save(&args.state)?;

    info!(
        rijen = rows.len(),
        dag = %day,
        station = %station_used,
        doel = &args.output,
        "klaar (edr)"
    );
    Ok(())
}

fn check_loc(state: &knmi::state::State, args: &Args) -> Result<(), Box<dyn std::error::Error>> {
    if let Some((slat, slon)) = state.loc() {
        if (slat - args.lat).abs() > 1e-6 || (slon - args.lon).abs() > 1e-6 {
            if !args.force {
                return Err(format!(
                    "Deze state/CSV hoort bij locatie ({slat}, {slon}), \
                     maar je vroeg ({}, {}). Gebruik een apart --state/--output, \
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
