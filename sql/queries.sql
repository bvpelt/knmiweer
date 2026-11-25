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



SELECT
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
) t
GROUP BY datum
ORDER BY datum;

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

---
--- Drie losse queries die de min, max en mean temperatuur per dag geven, ongeacht het station
---

SELECT
    datum,
    EXTRACT(YEAR FROM datum) AS jaar,
    EXTRACT(MONTH FROM datum) AS maand,
    EXTRACT(DAY FROM datum) AS dag,
    MIN(temperature)                          AS buiten_min_temp,
    MIN(tijd) FILTER (WHERE temperature = mn) AS buiten_tijd_min,
    ROUND(AVG(temperature), 2)                AS buiten_mean_temp,
    MAX(temperature)                          AS buiten_max_temp,
    MIN(tijd) FILTER (WHERE temperature = mx) AS buiten_tijd_max,
    COUNT(temperature) AS aantal_buiten 
FROM (
    SELECT
        station, datum, tijd, temperature,
        MIN(temperature) OVER (PARTITION BY station, datum) AS mn,
        MAX(temperature) OVER (PARTITION BY station, datum) AS mx
    FROM metingen
) t
GROUP BY datum
ORDER BY datum;


SELECT
    DATE(gemeten_op) as datum, 
    min(temp_ruimte) as min_temp_kerk_ruimte, 
    ROUND(avg(temp_ruimte)::numeric, 1) as avg_temp_kerk_ruimte, 
    max(temp_ruimte) as max_temp_kerk_ruimte, 
    min(temp_inblaas) as min_temp_kerk_inblaas, 
    ROUND(avg(temp_inblaas)::numeric, 1) as avg_temp_kerk_inblaas, 
    max(temp_inblaas) as max_temp_kerk_inblaas, 
    min(temp_retour) as min_temp_kerk_retour, 
    ROUND(avg(temp_retour)::numeric, 1) as avg_temp_kerk_retour, 
    max(temp_retour) as max_temp_kerk_retour, 
    count(temp_ruimte) as aantal_kerk
from kerkzaal_metingen 
group by DATE(gemeten_op)
order by datum;


SELECT
    DATE(tijdstip_van)                  AS datum,

    MIN(electra_verbruik)               AS min_electra,
    ROUND(AVG(electra_verbruik)::numeric, 3) AS avg_electra,
    MAX(electra_verbruik)               AS max_electra,

    MIN(gas_verbruik)                   AS min_gas,
    ROUND(AVG(gas_verbruik)::numeric, 3)     AS avg_gas,
    MAX(gas_verbruik)                   AS max_gas

FROM energie
GROUP BY 1
ORDER BY 1;

---
--- Gecombineerde query die de min, max en mean temperatuur per dag geeft, ongeacht het station, en de min, max en mean electra- en gasverbruik per dag
---
WITH buiten AS (
    SELECT
        datum,
        MIN(temperature)                          AS buiten_min_temp,
        MIN(tijd) FILTER (WHERE temperature = mn) AS buiten_tijd_min,
        ROUND(AVG(temperature), 2)                AS buiten_mean_temp,
        MAX(temperature)                          AS buiten_max_temp,
        MIN(tijd) FILTER (WHERE temperature = mx) AS buiten_tijd_max,
        COUNT(temperature)                        AS aantal_buiten
    FROM (
        SELECT
            station, datum, tijd, temperature,
            MIN(temperature) OVER (PARTITION BY station, datum) AS mn,
            MAX(temperature) OVER (PARTITION BY station, datum) AS mx
        FROM metingen
    ) t
    GROUP BY datum
),
kerk AS (
    SELECT
        DATE(gemeten_op)                          AS datum,
        MIN(temp_ruimte)                          AS min_temp_kerk_ruimte,
        ROUND(AVG(temp_ruimte)::numeric, 1)       AS avg_temp_kerk_ruimte,
        MAX(temp_ruimte)                          AS max_temp_kerk_ruimte,
        MIN(temp_inblaas)                         AS min_temp_kerk_inblaas,
        ROUND(AVG(temp_inblaas)::numeric, 1)      AS avg_temp_kerk_inblaas,
        MAX(temp_inblaas)                         AS max_temp_kerk_inblaas,
        MIN(temp_retour)                          AS min_temp_kerk_retour,
        ROUND(AVG(temp_retour)::numeric, 1)       AS avg_temp_kerk_retour,
        MAX(temp_retour)                          AS max_temp_kerk_retour,
        COUNT(temp_ruimte)                        AS aantal_kerk
    FROM kerkzaal_metingen
    GROUP BY 1
),
energie AS (
    SELECT
        DATE(tijdstip_van)                        AS datum,
        MIN(electra_verbruik)                     AS min_electra,
        ROUND(AVG(electra_verbruik)::numeric, 3)  AS avg_electra,
        MAX(electra_verbruik)                     AS max_electra,
        MIN(gas_verbruik)                         AS min_gas,
        ROUND(AVG(gas_verbruik)::numeric, 3)      AS avg_gas,
        MAX(gas_verbruik)                         AS max_gas
    FROM energie
    GROUP BY 1
)
SELECT
    COALESCE(b.datum, k.datum, e.datum) AS datum,
    EXTRACT(YEAR FROM COALESCE(b.datum, k.datum, e.datum)) AS jaar,
    EXTRACT(MONTH FROM COALESCE(b.datum, k.datum, e.datum)) AS maand,
    EXTRACT(DAY FROM COALESCE(b.datum, k.datum, e.datum)) AS dag,
    b.buiten_min_temp, b.buiten_tijd_min, b.buiten_mean_temp,
    b.buiten_max_temp, b.buiten_tijd_max, b.aantal_buiten,
    k.min_temp_kerk_ruimte, k.avg_temp_kerk_ruimte, k.max_temp_kerk_ruimte,
    k.min_temp_kerk_inblaas, k.avg_temp_kerk_inblaas, k.max_temp_kerk_inblaas,
    k.min_temp_kerk_retour, k.avg_temp_kerk_retour, k.max_temp_kerk_retour,
    k.aantal_kerk,
    e.min_electra, e.avg_electra, e.max_electra,
    e.min_gas, e.avg_gas, e.max_gas
FROM buiten b
FULL OUTER JOIN kerk     k ON k.datum = b.datum
FULL OUTER JOIN energie  e ON e.datum = COALESCE(b.datum, k.datum)
ORDER BY 1;

---
---
--- Gecombineerde query die de min, max en mean temperatuur per dag geeft, ongeacht het station, en de min, max en mean electra- en gasverbruik per dag
--- en die als view wordt opgeslagen
CREATE VIEW dagoverzicht AS
WITH buiten AS (
    SELECT
        datum,
        MIN(temperature)                          AS buiten_min_temp,
        MIN(tijd) FILTER (WHERE temperature = mn) AS buiten_tijd_min,
        ROUND(AVG(temperature), 2)                AS buiten_mean_temp,
        MAX(temperature)                          AS buiten_max_temp,
        MIN(tijd) FILTER (WHERE temperature = mx) AS buiten_tijd_max,
        COUNT(temperature)                        AS aantal_buiten
    FROM (
        SELECT
            station, datum, tijd, temperature,
            MIN(temperature) OVER (PARTITION BY station, datum) AS mn,
            MAX(temperature) OVER (PARTITION BY station, datum) AS mx
        FROM metingen
    ) t
    GROUP BY datum
),
kerk AS (
    SELECT
        DATE(gemeten_op)                          AS datum,
        MIN(temp_ruimte)                          AS min_temp_kerk_ruimte,
        ROUND(AVG(temp_ruimte)::numeric, 1)       AS avg_temp_kerk_ruimte,
        MAX(temp_ruimte)                          AS max_temp_kerk_ruimte,
        MIN(temp_inblaas)                         AS min_temp_kerk_inblaas,
        ROUND(AVG(temp_inblaas)::numeric, 1)      AS avg_temp_kerk_inblaas,
        MAX(temp_inblaas)                         AS max_temp_kerk_inblaas,
        MIN(temp_retour)                          AS min_temp_kerk_retour,
        ROUND(AVG(temp_retour)::numeric, 1)       AS avg_temp_kerk_retour,
        MAX(temp_retour)                          AS max_temp_kerk_retour,
        COUNT(temp_ruimte)                        AS aantal_kerk
    FROM kerkzaal_metingen
    GROUP BY 1
),
energie AS (
    SELECT
        DATE(tijdstip_van)                        AS datum,
        MIN(electra_verbruik)                     AS min_electra,
        ROUND(AVG(electra_verbruik)::numeric, 3)  AS avg_electra,
        MAX(electra_verbruik)                     AS max_electra,
        MIN(gas_verbruik)                         AS min_gas,
        ROUND(AVG(gas_verbruik)::numeric, 3)      AS avg_gas,
        MAX(gas_verbruik)                         AS max_gas
    FROM energie
    GROUP BY 1
)
SELECT
    COALESCE(b.datum, k.datum, e.datum) AS datum,
    EXTRACT(YEAR FROM COALESCE(b.datum, k.datum, e.datum)) AS jaar,
    EXTRACT(MONTH FROM COALESCE(b.datum, k.datum, e.datum)) AS maand,
    EXTRACT(DAY FROM COALESCE(b.datum, k.datum, e.datum)) AS dag,
    b.buiten_min_temp, b.buiten_tijd_min, b.buiten_mean_temp,
    b.buiten_max_temp, b.buiten_tijd_max, b.aantal_buiten,
    k.min_temp_kerk_ruimte, k.avg_temp_kerk_ruimte, k.max_temp_kerk_ruimte,
    k.min_temp_kerk_inblaas, k.avg_temp_kerk_inblaas, k.max_temp_kerk_inblaas,
    k.min_temp_kerk_retour, k.avg_temp_kerk_retour, k.max_temp_kerk_retour,
    k.aantal_kerk,
    e.min_electra, e.avg_electra, e.max_electra,
    e.min_gas, e.avg_gas, e.max_gas
FROM buiten b
FULL OUTER JOIN kerk     k ON k.datum = b.datum
FULL OUTER JOIN energie  e ON e.datum = COALESCE(b.datum, k.datum)
ORDER BY 1;

---
--- Overzicht als csv-bestand
---
--- psql -d weerdata --csv -c "SELECT * FROM dagoverzicht ORDER BY datum" -o dagoverzicht.csv