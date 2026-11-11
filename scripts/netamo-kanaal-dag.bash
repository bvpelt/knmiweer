#!/bin/bash

#!/bin/bash
# Gebruik: ./netamo-kanaal-dag.bash 2026-09-15 [output-prefix]

DAG="${1:?Gebruik: $0 <datum YYYY-MM-DD> [prefix]}"

plot_kanaal() {
    local kolom="$1" bestand="$2"
    local datbestand
    datbestand=$(mktemp /tmp/uurdata.XXXXXX.dat)

    psql -d weerdata -At -F $'\t' -c "
    SELECT to_char(date_trunc('hour', gemeten_op AT TIME ZONE 'Europe/Paris'), 'YYYY-MM-DD HH24:MI'),
           ROUND(MIN($kolom)::numeric, 1),
           ROUND(AVG($kolom)::numeric, 1),
           ROUND(MAX($kolom)::numeric, 1)
    FROM kerkzaal_metingen
    WHERE DATE(gemeten_op AT TIME ZONE 'Europe/Paris') = '$DAG'
    GROUP BY 1 ORDER BY 1" > "$datbestand"

    gnuplot -e "OUTFILE='$bestand'; DATFILE='$datbestand'; \
                XMIN='${DAG} 00:00'; XMAX='${DAG} 23:00'" netamo-kanaal-dag.gp

    rm -f "$datbestand"
}

PREFIX="${2:-netamo-$DAG}"
plot_kanaal temp_ruimte  "$PREFIX-temp-ruimte.png"
plot_kanaal temp_inblaas "$PREFIX-temp-inblaas.png"
plot_kanaal temp_retour  "$PREFIX-temp-retour.png"