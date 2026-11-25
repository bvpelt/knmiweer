#!/usr/bin/env bash
set -euo pipefail

# Configuration (override via environment variables if needed)
XLSX_FILE="${1:-./data/meetdata.xlsx}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-weerdata}"
PGUSER="${PGUSER:-bvpelt}"
TZ_NAME="${TZ_NAME:-Europe/Amsterdam}"

GAS_CHANNEL="871687400003829018"
ELEC_CHANNEL="871687400003829001"

if [[ ! -f "$XLSX_FILE" ]]; then
  echo "Error: file '$XLSX_FILE' not found." >&2
  exit 1
fi

if ! "$PYTHON_BIN" -c "import openpyxl" 2>/dev/null; then
  echo "Error: '$PYTHON_BIN' does not have 'openpyxl' installed." >&2
  exit 1
fi

TMP_CSV="$(mktemp --suffix=.csv)"
TMP_SQL="$(mktemp --suffix=.sql)"
trap 'rm -f "$TMP_CSV" "$TMP_SQL"' EXIT

# 1. Convert .xlsx rows to a clean pipe-delimited CSV
"$PYTHON_BIN" - "$XLSX_FILE" "$TMP_CSV" <<'PYEOF'
import csv
import datetime
import sys
import warnings
from openpyxl import load_workbook

warnings.filterwarnings("ignore", category=UserWarning, module="openpyxl")

xlsx_path, out_csv = sys.argv[1], sys.argv[2]
wb = load_workbook(xlsx_path, read_only=True, data_only=True)
ws = wb.active
ws.reset_dimensions()

def fmt_dt(val):
    if isinstance(val, datetime.datetime):
        return val.strftime("%d-%m-%Y %H:%M")
    return str(val).strip()

def fmt_num(val):
    if val is None or str(val).strip() == "":
        return ""
    if isinstance(val, (int, float)):
        return str(val)
    return str(val).strip().replace(",", ".")

with open(out_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f, delimiter="|")
    for idx, row in enumerate(ws.iter_rows(values_only=True)):
        if not row or all(v is None or str(v).strip() == "" for v in row):
            continue
        first = str(row[0]).strip() if row[0] is not None else ""
        # Skip header row(s)
        if first.lower() == "datakanaal":
            continue
        if len(row) < 8:
            continue

        channel = first
        omschrijving = str(row[1]).strip() if row[1] is not None else ""
        van = fmt_dt(row[2])
        tot = fmt_dt(row[3])
        laag = fmt_num(row[4])
        hoog = fmt_num(row[5])
        totaal = fmt_num(row[6])
        meterstand = fmt_num(row[7])

        writer.writerow([channel, omschrijving, van, tot, laag, hoog, totaal, meterstand])
PYEOF

# Optional: verify the temp CSV was generated and has rows
ls -lh "$TMP_CSV"
head -n 5 "$TMP_CSV"

# 2. Load into staging and upsert into gas_verbruik & electra_verbruik
cat <<SQLEOF >"$TMP_SQL"
BEGIN;

CREATE TEMP TABLE stage_metingen (
    datakanaal      text,
    omschrijving    text,
    tijdstip_van    text,
    tijdstip_tot    text,
    verbruik_laag   text,
    verbruik_hoog   text,
    verbruik_totaal text,
    meterstand      text
) ON COMMIT DROP;

\copy stage_metingen FROM '$TMP_CSV' WITH (FORMAT csv, DELIMITER '|', ENCODING 'UTF8')

INSERT INTO public.gas_verbruik (
    omschrijving,
    tijdstip_van,
    tijdstip_tot,
    verbruik_laag,
    verbruik_hoog,
    verbruik_totaal,
    meterstand
)
SELECT
    omschrijving,
    to_timestamp(tijdstip_van, 'DD-MM-YYYY HH24:MI') AT TIME ZONE '$TZ_NAME',
    to_timestamp(tijdstip_tot, 'DD-MM-YYYY HH24:MI') AT TIME ZONE '$TZ_NAME',
    NULLIF(verbruik_laag, '')::numeric(10,3),
    NULLIF(verbruik_hoog, '')::numeric(10,3),
    NULLIF(verbruik_totaal, '')::numeric(10,3),
    NULLIF(meterstand, '')::numeric(12,3)
FROM stage_metingen
WHERE datakanaal = '$GAS_CHANNEL'
ON CONFLICT (tijdstip_van) DO NOTHING;

INSERT INTO public.electra_verbruik (
    omschrijving,
    tijdstip_van,
    tijdstip_tot,
    verbruik_laag,
    verbruik_hoog,
    verbruik_totaal,
    meterstand
)
SELECT
    omschrijving,
    to_timestamp(tijdstip_van, 'DD-MM-YYYY HH24:MI') AT TIME ZONE '$TZ_NAME',
    to_timestamp(tijdstip_tot, 'DD-MM-YYYY HH24:MI') AT TIME ZONE '$TZ_NAME',
    NULLIF(verbruik_laag, '')::numeric(10,3),
    NULLIF(verbruik_hoog, '')::numeric(10,3),
    NULLIF(verbruik_totaal, '')::numeric(10,3),
    NULLIF(meterstand, '')::numeric(12,3)
FROM stage_metingen
WHERE datakanaal = '$ELEC_CHANNEL'
ON CONFLICT (tijdstip_van) DO NOTHING;

COMMIT;
SQLEOF

psql -v ON_ERROR_STOP=1 \
  -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
  -f "$TMP_SQL"