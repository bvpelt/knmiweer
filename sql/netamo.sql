CREATE TABLE kerkzaal_metingen (
    gemeten_op      timestamptz PRIMARY KEY,
    -- Ruimte kerkzaal (Weather Station)
    temp_ruimte     numeric(4,1),
    rh_ruimte       int,
    co2_ruimte      int,
    geluid_db       int,
    luchtdruk_pa    numeric(6,1),
    -- Inblaaslucht kerkzaal (Outdoor Module)
    temp_inblaas    numeric(4,1),
    rh_inblaas      int,
    -- Retourlucht kerkzaal (Indoor Module)
    temp_retour     numeric(4,1),
    rh_retour       int,
    co2_retour      int
);

CREATE TEMP TABLE staging (
    c1 text, c2 text, c3 text, c4 text, c5 text, c6 text, c7 text,
    c8 text, c9 text, c10 text, c11 text, c12 text, c13 text, c14 text, c15 text
);

COPY staging FROM '/home/bvpelt/Develop/knmiweer/doc/metingen.csv'
WITH (FORMAT csv, HEADER false);


INSERT INTO kerkzaal_metingen (
    gemeten_op, temp_ruimte, rh_ruimte, co2_ruimte, geluid_db, luchtdruk_pa,
    temp_inblaas, rh_inblaas, temp_retour, rh_retour, co2_retour
)
SELECT
    to_timestamp(c1::bigint),
    c3::numeric, c4::int, c5::int, c6::int, c7::numeric,
    c9::numeric, c10::int,
    c12::numeric, c13::int, c14::int
FROM staging
WHERE c1 ~ '^\d+$'
ON CONFLICT (gemeten_op) DO NOTHING;

DROP TABLE staging;

select 
    DATE(gemeten_op) as datum, 
    min(temp_ruimte) as min_temp_ruimte, 
    ROUND(avg(temp_ruimte)::numeric, 1) as avg_temp_ruimte, 
    max(temp_ruimte) as max_temp_ruimte, 
    min(temp_inblaas) as min_temp_inblaas, 
    ROUND(avg(temp_inblaas)::numeric, 1) as avg_temp_inblaas, 
    max(temp_inblaas) as max_temp_inblaas, 
    min(temp_retour) as min_temp_retour, 
    ROUND(avg(temp_retour)::numeric, 1) as avg_temp_retour, 
    max(temp_retour) as max_temp_retour, 
    count(temp_ruimte) as count_temp_ruimte
from kerkzaal_metingen 
group by DATE(gemeten_op)
order by datum;

select 
    DATE(gemeten_op) as datum, 
    EXTRACT(HOUR FROM gemeten_op) AS uur,
    min(temp_ruimte) as min_temp_ruimte, 
    ROUND(avg(temp_ruimte)::numeric, 1) as avg_temp_ruimte, 
    max(temp_ruimte) as max_temp_ruimte, 
    min(temp_inblaas) as min_temp_inblaas, 
    ROUND(avg(temp_inblaas)::numeric, 1) as avg_temp_inblaas, 
    max(temp_inblaas) as max_temp_inblaas, 
    min(temp_retour) as min_temp_retour, 
    ROUND(avg(temp_retour)::numeric, 1) as avg_temp_retour, 
    max(temp_retour) as max_temp_retour, 
    count(temp_ruimte) as count_temp_ruimte
from kerkzaal_metingen 
group by DATE(gemeten_op),uur
order by datum, uur;

