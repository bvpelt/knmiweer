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
WHERE station = '0-20000-0-06275'
GROUP BY datum, station
ORDER BY datum, station;

--- per station per dag: minimumtemperatuur en het tijdstip daarvan
SELECT DISTINCT ON (station, datum)
    station,
    datum,
    temperature AS min_temp,
    tijd         AS tijd_min
FROM metingen
WHERE station = '0-20000-0-06275'
ORDER BY station, datum, temperature, tijd;

--- per station per dag: minimum, maximum en de tijdstippen daarvan
SELECT * FROM (
    SELECT DISTINCT ON (station, datum)
        station,
        datum,
        'min' AS soort,
        temperature AS temp,
        tijd
    FROM metingen
    WHERE station = '0-20000-0-06275'
    ORDER BY station, datum, temperature, tijd
) mn
UNION ALL
SELECT * FROM (
    SELECT DISTINCT ON (station, datum)
        station,
        datum,
        'max' AS soort,
        temperature AS temp,
        tijd
    FROM metingen
    WHERE station = '0-20000-0-06275'
    ORDER BY station, datum, temperature DESC, tijd
) mx
ORDER BY station, datum, soort DESC;


--- per station per dag: minimum, maximum (met tijdstippen) en gemiddelde
SELECT
    station,
    datum,
    EXTRACT(YEAR FROM datum) AS jaar,
    EXTRACT(MONTH FROM datum) AS maand,
    EXTRACT(DAY FROM datum) AS dag,
    MIN(temperature)                          AS min_temp,
    MIN(tijd) FILTER (WHERE temperature = mn) AS tijd_min,
    MAX(temperature)                          AS max_temp,
    MIN(tijd) FILTER (WHERE temperature = mx) AS tijd_max,
    ROUND(AVG(temperature), 2)                AS mean_temp,
    COUNT(temperature) AS aantal 
FROM (
    SELECT
        station, datum, tijd, temperature,
        MIN(temperature) OVER (PARTITION BY station, datum) AS mn,
        MAX(temperature) OVER (PARTITION BY station, datum) AS mx
    FROM metingen
    WHERE station = '0-20000-0-06275'
) t
GROUP BY station, datum
ORDER BY station, datum;

// output to csv

\copy (SELECT 
    station, 
    datum, 
    MIN(temperature) AS min_temp, MIN(tijd) FILTER (WHERE temperature = mn) AS tijd_min, 
    MAX(temperature) AS max_temp, MIN(tijd) FILTER (WHERE temperature = mx) AS tijd_max, 
    ROUND(AVG(temperature), 2) AS mean_temp, 
    COUNT(temperature) AS aantal 
    FROM (
        SELECT 
            station, 
            datum, 
            tijd, 
            temperature, 
            MIN(temperature) OVER (PARTITION BY station, datum) AS mn, 
            MAX(temperature) OVER (PARTITION BY station, datum) AS mx 
            FROM metingen) t 
            GROUP BY station, datum 
            ORDER BY station, datum) 
            TO 'dagstatistiek.csv' 
            WITH (FORMAT csv, DELIMITER ';', HEADER true)

-- aantal dagen per maand
SELECT jaar, maand, COUNT(*) AS aantal_dagen
FROM (
    SELECT
        station,
        datum,
        EXTRACT(YEAR FROM datum)  AS jaar,
        EXTRACT(MONTH FROM datum) AS maand,
        EXTRACT(DAY FROM datum)   AS dag,
        MIN(temperature)                          AS min_temp,
        MIN(tijd) FILTER (WHERE temperature = mn) AS tijd_min,
        MAX(temperature)                          AS max_temp,
        MIN(tijd) FILTER (WHERE temperature = mx) AS tijd_max,
        ROUND(AVG(temperature), 2)                AS mean_temp,
        COUNT(temperature)                        AS aantal
    FROM (
        SELECT
            station, datum, tijd, temperature,
            MIN(temperature) OVER (PARTITION BY station, datum) AS mn,
            MAX(temperature) OVER (PARTITION BY station, datum) AS mx
        FROM metingen
        WHERE station = '0-20000-0-06275'
    ) t
    GROUP BY station, datum
) x
GROUP BY jaar, maand
ORDER BY jaar, maand;

SELECT
    date_trunc('month', datum) AS maand,
    COUNT(DISTINCT datum)      AS aantal_dagen
FROM metingen
GROUP BY date_trunc('month', datum)
ORDER BY maand;

-- geef alle stations waarvoor er metingen zijn
SELECT s.*
FROM stations s
WHERE EXISTS (
    SELECT 1 FROM metingen m WHERE m.station = s.id
)
ORDER BY s.naam;
