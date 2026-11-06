CREATE DATABASE weerdata;

-- daarna verbinden met de nieuwe database en:
CREATE TABLE metingen (
    datum        date        NOT NULL,
    tijd         time        NOT NULL,
    station      text        NOT NULL,
    temperature numeric(5,2),
    PRIMARY KEY (station, datum, tijd)
);

COPY metingen (datum, tijd, station, temperature)
FROM '/home/bvpelt/Develop/knmiweeer/temperatuur.csv' WITH (
    FORMAT csv,
    DELIMITER ';',
    HEADER true,
    NULL ''
);
