#!/usr/bin/env bash
# export_dagoverzicht.bash — exporteer view dagoverzicht naar CSV.
# Gebruik: ./export_dagoverzicht.bash [doelbestand]
set -euo pipefail          # stop bij fouten,290 ongebonden variabelen, falen in pijplijnen

OUT="${1:-dagoverzicht.csv}"

# Doelmap bepalen; temp-bestand in dezelfde map zodat mv atomair is
DIR="$(dirname "$OUT")"
[ -d "$DIR" ] || { echo "Doelmap $DIR bestaat niet" >&2; exit 1; }

TMP="$(mktemp "$DIR/.dagoverzicht.XXXXXX")"
trap 'rm -f "$TMP"' EXIT   # ruim temp op (ook bij fout of Ctrl-C)

psql -X -v ON_ERROR_STOP=1 -d weerdata -c "\\copy (SELECT * FROM dagoverzicht ORDER BY datum) TO '$TMP' WITH (FORMAT csv, HEADER true)"

# psql gaf exit 0, maar wees kritisch op het resultaat:
if [ ! -s "$TMP" ]; then
  echo "Export leeg (alleen kopregel of helemaal niets); $OUT blijft onaangetast" >&2
  exit 1
fi

mv "$TMP" "$OUT"
trap - EXIT                # mv is gelukt, trap mag er nu uit
echo "Geëxporteerd: $(wc -l < "$OUT") regels naar $OUT"