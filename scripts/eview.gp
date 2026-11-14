if (!exists("OUTFILE")) OUTFILE = "temp.png"
if (!exists("DATFILE")) DATFILE = "uurdata.dat"
set output OUTFILE
set terminal png size 1920,1200
set datafile separator "\t"
set xdata time
set timefmt "%Y-%m-%d"
set format x "%d-%b-%Y"
set xtics rotate by -45
set ylabel "Verbruik"
set title "Verbruik per dag: min / avg / max"
set key top right

plot DATFILE using 1:2 with lines lw 2 title "Verbruik"