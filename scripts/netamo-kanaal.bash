#!/bin/bash

# temp_ruimte
#
# -A = unaligned, -t = geen header/footer, -F $'\t' = tab als scheidingsteken.
# to_char maakt van de timestamp een vaste tekstvorm; gnuplot kan die later als tijdas parsen.
#
psql -d weerdata -At -F $'\t' -c "
SELECT to_char(DATE(gemeten_op), 'YYYY-MM-DD'),
       ROUND(MIN(temp_ruimte)::numeric, 1),
       ROUND(AVG(temp_ruimte)::numeric, 1),
       ROUND(MAX(temp_ruimte)::numeric, 1)
FROM kerkzaal_metingen
GROUP BY 1
ORDER BY 1
" > uurdata.dat


OUTFILE=netamo-temp-ruimte.png
gnuplot -e "OUTFILE='$OUTFILE'" netamo-kanaal.gp

# temp_inblaas
#
# -A = unaligned, -t = geen header/footer, -F $'\t' = tab als scheidingsteken.
# to_char maakt van de timestamp een vaste tekstvorm; gnuplot kan die later als tijdas parsen.
#
psql -d weerdata -At -F $'\t' -c "
SELECT to_char(DATE(gemeten_op), 'YYYY-MM-DD'),
       ROUND(MIN(temp_inblaas)::numeric, 1),
       ROUND(AVG(temp_inblaas)::numeric, 1),
       ROUND(MAX(temp_inblaas)::numeric, 1)
FROM kerkzaal_metingen
GROUP BY 1
ORDER BY 1
" > uurdata.dat

OUTFILE=netamo-temp-inblaas.png
gnuplot -e "OUTFILE='$OUTFILE'" netamo-kanaal.gp


# temp_retour
#
# -A = unaligned, -t = geen header/footer, -F $'\t' = tab als scheidingsteken.
# to_char maakt van de timestamp een vaste tekstvorm; gnuplot kan die later als tijdas parsen.
#
psql -d weerdata -At -F $'\t' -c "
SELECT to_char(DATE(gemeten_op), 'YYYY-MM-DD'),
       ROUND(MIN(temp_retour)::numeric, 1),
       ROUND(AVG(temp_retour)::numeric, 1),
       ROUND(MAX(temp_retour)::numeric, 1)
FROM kerkzaal_metingen
GROUP BY 1
ORDER BY 1
" > uurdata.dat

OUTFILE=netamo-temp-retour.png
gnuplot -e "OUTFILE='$OUTFILE'" netamo-kanaal.gp

