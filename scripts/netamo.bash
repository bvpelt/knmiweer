#!/bin/bash

#
# -A = unaligned, -t = geen header/footer, -F $'\t' = tab als scheidingsteken.
# to_char maakt van de timestamp een vaste tekstvorm; gnuplot kan die later als tijdas parsen.
#
psql -d weerdata -At -F $'\t' -c "
SELECT to_char(date_trunc('hour', gemeten_op), 'YYYY-MM-DD HH24:MI'),
       ROUND(AVG(temp_ruimte)::numeric, 1),
       ROUND(AVG(temp_inblaas)::numeric, 1),
       ROUND(AVG(temp_retour)::numeric, 1)
FROM kerkzaal_metingen
GROUP BY 1
ORDER BY 1
" > uurdata.dat

gnuplot netamo.gp