--- alle metingen
select * from metingen order by datum, tijd, station;

--- metingen per dag, per uur, per station
SELECT
    datum,
    EXTRACT(HOUR FROM tijd) AS uur,
    station,
    ROUND(AVG(temperature), 2) AS gem_temp
FROM metingen
GROUP BY datum, EXTRACT(HOUR FROM tijd), station
ORDER BY datum, uur, station;

--- metingen per dag, per station
SELECT
    datum,
    station,
    ROUND(AVG(temperature), 2) AS gem_temp
FROM metingen
GROUP BY datum, station
ORDER BY datum, station;