pub mod csv_out;
pub mod edr;
pub mod extract;
pub mod opendata;
pub mod state;

/// Eén meetwaarde, brononafhankelijk. Dit is wat in de CSV belandt.
#[derive(Debug, Clone)]
pub struct Reading {
    /// Tijdstip van de meting (UTC).
    pub timestamp: chrono::NaiveDateTime,
    /// Station-id, bv. "06260" (De Bilt) of de EDR-location-id.
    pub station: String,
    /// Temperatuur in graden Celsius.
    pub celsius: f64,
}
