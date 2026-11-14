DROP TABLE IF EXISTS electra_verbruik;
CREATE TABLE electra_verbruik (
    omschrijving    text,
    tijdstip_van    timestamptz NOT NULL,
    tijdstip_tot    timestamptz NOT NULL,
    verbruik_laag   numeric(10,3),
    verbruik_hoog   numeric(10,3),
    verbruik_totaal numeric(10,3),
    meterstand      numeric(12,3),
    PRIMARY KEY (tijdstip_van)
);

DROP TABLE IF EXISTS gas_verbruik;
CREATE TABLE gas_verbruik (
    omschrijving    text,
    tijdstip_van    timestamptz NOT NULL,
    tijdstip_tot    timestamptz NOT NULL,
    verbruik_laag   numeric(10,3),
    verbruik_hoog   numeric(10,3),
    verbruik_totaal numeric(10,3),
    meterstand      numeric(12,3),
    PRIMARY KEY (tijdstip_van)
);

DROP TABLE IF EXISTS energie;
CREATE TABLE energie (
    tijdstip_van    timestamptz NOT NULL,
    tijdstip_tot    timestamptz NOT NULL,
    electra_verbruik   numeric(10,3),
    gas_verbruik   numeric(10,3),
    PRIMARY KEY (tijdstip_van)
);

INSERT INTO energie (tijdstip_van, tijdstip_tot, electra_verbruik, gas_verbruik)
SELECT e.tijdstip_van, e.tijdstip_tot, e.verbruik_totaal, g.verbruik_totaal 
FROM electra_verbruik e 
JOIN gas_verbruik g 
ON (e.tijdstip_van = g.tijdstip_van);

--
-- Min, Avg, Max per dag 
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