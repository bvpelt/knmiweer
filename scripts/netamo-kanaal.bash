#!/bin/bash

plot_kanaal() {
    local kolom="$1" bestand="$2"
    psql -d weerdata -At -F $'\t' -c "
    SELECT to_char(DATE(gemeten_op), 'YYYY-MM-DD'),
           ROUND(MIN($kolom)::numeric, 1),
           ROUND(AVG($kolom)::numeric, 1),
           ROUND(MAX($kolom)::numeric, 1)
    FROM kerkzaal_metingen
    GROUP BY 1 ORDER BY 1" > uurdata.dat

    gnuplot -e "OUTFILE='$bestand'" netamo-kanaal.gp
}

plot_kanaal temp_ruimte  netamo-temp-ruimte.png
plot_kanaal temp_inblaas netamo-temp-inblaas.png
plot_kanaal temp_retour  netamo-temp-retour.png