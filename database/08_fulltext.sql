-- ============================================================
-- Full-text index for the station finder. Boolean mode with a trailing *
-- matches word prefixes, so "beng*" finds both Bengaluru stations.
-- ============================================================
USE railway_db;

CREATE FULLTEXT INDEX ft_station ON STATION (station_name, city);
