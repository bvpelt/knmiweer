if (!exists("OUTFILE")) OUTFILE = "temp.png"
if (!exists("DATFILE")) DATFILE = "uurdata.dat"
if (!exists("XMIN"))    XMIN = "1970-01-01 00:00"
if (!exists("XMAX"))    XMAX = "1970-01-01 23:00"
set output OUTFILE
set terminal png size 1920,1200
set datafile separator "\t"
set xdata time
set timefmt "%Y-%m-%d %H:%M"
set format x "%H:%M"
set xtics 3600
set xrange [XMIN:XMAX]
set ylabel "Temperatuur (°C)"
set title "Temperatuur per uur: min / avg / max"
set key top right

plot DATFILE using 1:2 with lines lw 2 title "Min", \
     DATFILE using 1:3 with lines lw 2 title "Avg", \
     DATFILE using 1:4 with lines lw 2 title "Max"