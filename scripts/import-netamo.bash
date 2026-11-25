#!/usr/bin/env bash
# import_netatmo.sh — importeer Netatmo-export in public.kerkzaal_metingen
# Gebruik: ./import_netatmo.sh data/netamo-2026-01-06-to-2026-08-20.csv
set -euo pipefail

FILE="${1:?Gebruik: $0 <netatmo-csv>}"
[ -r "$FILE" ] || { echo "Kan $FILE niet lezen" >&2; exit 1; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Verwerk: kolommen uit het Netatmo-CSV omzetten naar platte CSV.
# Deel 1: ruimte      -> $3 temp, $4 rh, $5 co2, $6 geluid, $7 luchtdruk
# Deel 2: inblaas     -> $9 temp, $10 rh
# Deel 3: retour      -> $12 temp, $13 rh, $14 co2
awk -F, '
  NR > 4 && $1 ~ /^[0-9]+$/ {
    print $1","$3","$4","$5","$6","$7","$9","$10","$12","$13","$14
  }
' "$FILE" > "$TMP"

ROWS=$(wc -l < "$TMP")
if [ "$ROWS" -eq 0 ]; then
  echo "Geen datarijen gevonden in $FILE" >&2
  exit 1
fi

psql weerdata -X -v ON_ERROR_STOP=1 <<SQL
BEGIN;

CREATE TEMP TABLE netatmo_raw (
    gemeten_op   bigint,
    temp_ruimte  numeric,
    rh_ruimte    int,
    co2_ruimte   int,
    geluid_db    int,
    luchtdruk_pa numeric,
    temp_inblaas numeric,
    rh_inblaas   int,
    temp_retour  numeric,
    rh_retour    int,
    co2_retour   int
);

\\copy netatmo_raw FROM '$TMP' WITH (FORMAT csv)

INSERT INTO kerkzaal_metingen AS m (
    gemeten_op, temp_ruimte, rh_ruimte, co2_ruimte, geluid_db, luchtdruk_pa,
    temp_inblaas, rh_inblaas, temp_retour, rh_retour, co2_retour
)
SELECT
    to_timestamp(gemeten_op),
    temp_ruimte::numeric(4,1),
    rh_ruimte,
    co2_ruimte,
    geluid_db,
    luchtdruk_pa::numeric(6,1),
    temp_inblaas::numeric(4,1),
    rh_inblaas,
    temp_retour::numeric(4,1),
    rh_retour,
    co2_retour
FROM netatmo_raw
ON CONFLICT (gemeten_op) DO NOTHING;

COMMIT;
SQL

echo "Klaar: $ROWS rijen verwerkt uit $FILE (dubbele timestamps overgeslagen)."