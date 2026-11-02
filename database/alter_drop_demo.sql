-- ============================================================
-- ALTER, TRUNCATE and DROP demonstration, on a scratch table so it is safe to
-- run at any time:  mysql -u root -p railway_db < database/alter_drop_demo.sql
-- ============================================================
USE railway_db;

CREATE TABLE demo_announcement (
    id      INT AUTO_INCREMENT PRIMARY KEY,
    message VARCHAR(50)
);

ALTER TABLE demo_announcement ADD COLUMN station_code CHAR(5);
ALTER TABLE demo_announcement MODIFY message VARCHAR(200) NOT NULL;
ALTER TABLE demo_announcement
    ADD CONSTRAINT fk_demo_station FOREIGN KEY (station_code) REFERENCES STATION(station_code);
ALTER TABLE demo_announcement RENAME COLUMN message TO announcement;
ALTER TABLE demo_announcement ADD INDEX idx_demo_station (station_code);
DESCRIBE demo_announcement;

INSERT INTO demo_announcement (announcement, station_code) VALUES ('Platform 4 is under repair', 'SBC');
SELECT COUNT(*) AS rows_before_truncate FROM demo_announcement;
TRUNCATE TABLE demo_announcement;
SELECT COUNT(*) AS rows_after_truncate FROM demo_announcement;

ALTER TABLE demo_announcement DROP FOREIGN KEY fk_demo_station;
ALTER TABLE demo_announcement DROP COLUMN station_code;
DROP TABLE demo_announcement;
