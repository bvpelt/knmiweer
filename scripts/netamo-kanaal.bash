#!/bin/bash

debug=$DEBUG

plot_kanaal() {
    local kolom="$1" bestand="$2"
    local datbestand
    datbestand=$(mktemp /tmp/uurdata.XXXXXX.dat)

    QUERY="SELECT to_char(DATE(gemeten_op), 'YYYY-MM-DD'),
           ROUND(MIN($kolom)::numeric, 1),
           ROUND(AVG($kolom)::numeric, 1),
           ROUND(MAX($kolom)::numeric, 1)
    FROM kerkzaal_metingen
 --   where extract(month from gemeten_op) = 10
    GROUP BY 1 ORDER BY 1"

    if [ $debug -eq 1 ]; then
        echo "Query: $QUERY"
    fi

    psql -d weerdata -At -F $'\t' -c "$QUERY" > "$datbestand"

    gnuplot -e "OUTFILE='$bestand'; DATFILE='$datbestand'" netamo-kanaal.gp

    rm -f "$datbestand"
}

plot_kanaal temp_ruimte  netamo-temp-ruimte.png
plot_kanaal temp_inblaas netamo-temp-inblaas.png
plot_kanaal temp_retour  netamo-temp-retour.png