set terminal png size 1920,1200
if (!exists("OUTFILE")) OUTFILE = "temp.png"
set output OUTFILE
set datafile separator "\t"
set xdata time
set timefmt "%Y-%m-%d"
set format x "%d-%b-%Y"
set xtics rotate by -45
set ylabel "Temperatuur (°C)"
set title "Temperatuur per uur: min / avg / max"
set key top right

plot 'uurdata.dat' using 1:2 with lines lw 2 title "Min", \
     'uurdata.dat' using 1:3 with lines lw 2 title "Avg", \
     'uurdata.dat' using 1:4 with lines lw 2 title "Max"