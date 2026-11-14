#!/bin/bash

debug=${DEBUG:-0}

plot_kanaal() {
    local kolom="$1" bestand="$2"
    local datbestand
    datbestand=$(mktemp /tmp/uurdata.XXXXXX.dat)

    QUERY="SELECT to_char(DATE(tijdstip_van), 'YYYY-MM-DD') AS datum,
        SUM($kolom)
    FROM energie
    GROUP BY 1
    ORDER BY 1"

    if [ $debug -eq 1 ]; then
        echo "Query: $QUERY"
    fi

    psql -d weerdata -At -F $'\t' -c "$QUERY" > "$datbestand"

    gnuplot -e "OUTFILE='$bestand'; DATFILE='$datbestand'" eview.gp

    rm -f "$datbestand"
}

plot_kanaal gas_verbruik gas_verbruik.png
plot_kanaal electra_verbruik electra_verbruik.png
