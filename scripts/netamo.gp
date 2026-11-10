set terminal png size 1200,600
set output 'temp.png'
set datafile separator "\t"
set xdata time
set timefmt "%Y-%m-%d %H:%M"
set format x "%d-%b %H:%M"
set xtics rotate by -45
set ylabel "Temperatuur (°C)"
set title "Temperatuur per uur: ruimte / inblaas / retour"
set key top right

plot 'uurdata.dat' using 1:2 with lines lw 2 title "Ruimte", \
     'uurdata.dat' using 1:3 with lines lw 2 title "Inblaas", \
     'uurdata.dat' using 1:4 with lines lw 2 title "Retour"