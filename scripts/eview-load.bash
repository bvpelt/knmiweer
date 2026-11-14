#!/bin/bash
# Gebruik: ./eview-load.bash /home/bvpelt/Develop/knmiweer/doc/2025-energie-meetdata.csv

CSV="${1:?Gebruik: $0 <csv-bestand>}"
cd "$(dirname "$0")" || exit 1
echo "Inlezen CSV-bestand: $CSV"

# 1. Staging aanmaken (gewone tabel, geen TEMP: meerdere psql-sessies)
psql -d weerdata -v ON_ERROR_STOP=1 <<'SQL'
DROP TABLE IF EXISTS energie_staging;
CREATE TABLE energie_staging (
    kanaal text, omschrijving text,
    tijdstip_van text, tijdstip_tot text,
    verbruik_laag text, verbruik_hoog text,
    verbruik_totaal text, meterstand text
);
SQL

# 2. CSV via STDIN inladen; header overslaan met HEADER true
cat "$CSV" | psql -d weerdata -v ON_ERROR_STOP=1 \
  -c "COPY energie_staging FROM STDIN WITH (FORMAT csv, DELIMITER ';', HEADER true)"

# 3. Omzetten naar doeltabellen en staging opruimen
psql -d weerdata -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM energie_staging) = 0 THEN
        RAISE EXCEPTION 'Staging is leeg: CSV niet gelezen?';
    END IF;
END $$;

INSERT INTO electra_verbruik (
    omschrijving, tijdstip_van, tijdstip_tot,
    verbruik_laag, verbruik_hoog, verbruik_totaal, meterstand)
SELECT
    omschrijving,
    to_timestamp(tijdstip_van, 'DD-MM-YYYY HH24:MI'),
    to_timestamp(tijdstip_tot, 'DD-MM-YYYY HH24:MI'),
    replace(verbruik_laag,   ',', '.')::numeric,
    replace(verbruik_hoog,   ',', '.')::numeric,
    replace(verbruik_totaal, ',', '.')::numeric,
    replace(meterstand,      ',', '.')::numeric
FROM energie_staging
WHERE kanaal LIKE '%001'
ON CONFLICT (tijdstip_van) DO NOTHING;

INSERT INTO gas_verbruik (
    omschrijving, tijdstip_van, tijdstip_tot,
    verbruik_laag, verbruik_hoog, verbruik_totaal, meterstand)
SELECT
    omschrijving,
    to_timestamp(tijdstip_van, 'DD-MM-YYYY HH24:MI'),
    to_timestamp(tijdstip_tot, 'DD-MM-YYYY HH24:MI'),
    replace(verbruik_laag,   ',', '.')::numeric,
    replace(verbruik_hoog,   ',', '.')::numeric,
    replace(verbruik_totaal, ',', '.')::numeric,
    replace(meterstand,      ',', '.')::numeric
FROM energie_staging
WHERE kanaal LIKE '%018'
ON CONFLICT (tijdstip_van) DO NOTHING;

SELECT 'electra' AS tabel, COUNT(*) FROM electra_verbruik
UNION ALL
SELECT 'gas', COUNT(*) FROM gas_verbruik;

DROP TABLE energie_staging;
SQL