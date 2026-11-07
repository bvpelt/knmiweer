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

CREATE EXTENSION postgis;

CREATE TABLE stations (
    id       text PRIMARY KEY,
    naam     text NOT NULL,
    type     text,
    wmo_id   text,
    locatie  geography(Point, 4326),
    hoogte_m double precision
);

\set content `cat ./doc/stations.json`
\echo :content

INSERT INTO stations (id, naam, type, wmo_id, locatie, hoogte_m)
SELECT
    f ->> 'id',
    f -> 'properties' ->> 'name',
    f -> 'properties' ->> 'type',
    f -> 'properties' ->> 'wmoId',
    ST_SetSRID(ST_MakePoint(
        (f -> 'geometry' -> 'coordinates' ->> 0)::double precision,
        (f -> 'geometry' -> 'coordinates' ->> 1)::double precision
    ), 4326)::geography,
    (f -> 'properties' ->> 'height_above_mean_sea_level')::double precision
FROM jsonb_array_elements(:'content'::jsonb -> 'features') AS f
ON CONFLICT (id) DO NOTHING;
