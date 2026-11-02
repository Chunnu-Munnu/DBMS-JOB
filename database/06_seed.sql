-- ============================================================
-- Demo data. Coaches are deliberately small so RAC and waitlist are easy to
-- reach during a demo. Schedules are relative to today, so the data never expires.
-- Every seeded account's password is: Demo@1234
-- ============================================================
USE railway_db;

INSERT INTO STATION VALUES
('SBC','KSR Bengaluru','Bengaluru','Karnataka','SWR'),
('YPR','Yesvantpur Junction','Bengaluru','Karnataka','SWR'),
('MYS','Mysuru Junction','Mysuru','Karnataka','SWR'),
('MAS','MGR Chennai Central','Chennai','Tamil Nadu','SR'),
('SC','Secunderabad Junction','Hyderabad','Telangana','SCR'),
('NGP','Nagpur Junction','Nagpur','Maharashtra','CR'),
('BPL','Bhopal Junction','Bhopal','Madhya Pradesh','WCR'),
('JHS','Jhansi Junction','Jhansi','Uttar Pradesh','NCR'),
('NDLS','New Delhi','Delhi','Delhi','NR'),
('CSMT','Chhatrapati Shivaji Terminus','Mumbai','Maharashtra','CR'),
('PUNE','Pune Junction','Pune','Maharashtra','CR'),
('HWH','Howrah Junction','Kolkata','West Bengal','ER');

INSERT INTO TRAVEL_CLASS VALUES
('1A','First AC',TRUE,TRUE),('2A','AC 2 Tier',TRUE,TRUE),('3A','AC 3 Tier',TRUE,TRUE),
('SL','Sleeper',FALSE,TRUE),('CC','AC Chair Car',TRUE,FALSE),('2S','Second Sitting',FALSE,FALSE);

INSERT INTO QUOTA VALUES
('GN','General',0),('TQ','Tatkal',30),('LD','Ladies',0),('SS','Senior Citizen',0),('PH','Divyangjan',0);

INSERT INTO TRAIN VALUES
('12627','Karnataka Express','SUPERFAST','SBC','NDLS','YYYYYYY',2444),
('12628','Karnataka Express','SUPERFAST','NDLS','SBC','YYYYYYY',2444),
('12007','Mysuru Shatabdi','SHATABDI','MAS','MYS','YYYYYNY',497),
('11014','Coimbatore LTT Express','EXPRESS','SBC','CSMT','YYYYYYY',1211),
('12245','Duronto Express','SUPERFAST','HWH','YPR','NYNYNYN',1871);

INSERT INTO ROUTE (train_no,seq_no,station_code,arrival_time,departure_time,day_offset,dist_from_src,halt_minutes) VALUES
('12627',1,'SBC',NULL,'19:20:00',0,0,0),
('12627',2,'YPR','19:35:00','19:40:00',0,12,5),
('12627',3,'SC','07:30:00','07:40:00',1,700,10),
('12627',4,'NGP','16:00:00','16:10:00',1,1270,10),
('12627',5,'BPL','22:40:00','22:50:00',1,1660,10),
('12627',6,'JHS','02:00:00','02:10:00',2,1950,10),
('12627',7,'NDLS','09:00:00',NULL,2,2444,0),
('12628',1,'NDLS',NULL,'20:15:00',0,0,0),
('12628',2,'JHS','03:00:00','03:10:00',1,494,10),
('12628',3,'BPL','06:20:00','06:30:00',1,784,10),
('12628',4,'NGP','12:50:00','13:00:00',1,1174,10),
('12628',5,'SC','21:30:00','21:40:00',1,1744,10),
('12628',6,'YPR','09:20:00','09:25:00',2,2432,5),
('12628',7,'SBC','09:50:00',NULL,2,2444,0),
('12007',1,'MAS',NULL,'06:00:00',0,0,0),
('12007',2,'SBC','10:50:00','10:55:00',0,359,5),
('12007',3,'MYS','13:00:00',NULL,0,497,0),
('11014',1,'SBC',NULL,'08:30:00',0,0,0),
('11014',2,'YPR','08:45:00','08:50:00',0,12,5),
('11014',3,'PUNE','05:10:00','05:20:00',1,1020,10),
('11014',4,'CSMT','09:30:00',NULL,1,1211,0),
('12245',1,'HWH',NULL,'10:50:00',0,0,0),
('12245',2,'MAS','05:40:00','05:50:00',1,1659,10),
('12245',3,'YPR','11:30:00',NULL,1,1871,0);

INSERT INTO COACH (train_no,coach_code,class_code,total_seats) VALUES
('12627','A1','2A',4),('12627','B1','3A',6),('12627','S1','SL',8),('12627','S2','SL',8),
('12628','A1','2A',4),('12628','B1','3A',6),('12628','S1','SL',8),
('12007','C1','CC',10),('12007','D1','2S',12),
('11014','B1','3A',6),('11014','S1','SL',10),
('12245','A1','2A',4),('12245','B1','3A',8);

-- One SEAT row per seat, generated with a recursive CTE.
INSERT INTO SEAT (coach_id, seat_no, berth_type)
WITH RECURSIVE n AS (SELECT 1 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 100)
SELECT c.coach_id, n.i,
       CASE WHEN tc.has_berth THEN ELT(((n.i - 1) MOD 5) + 1, 'LOWER','MIDDLE','UPPER','SIDE_LOWER','SIDE_UPPER')
            ELSE ELT(((n.i - 1) MOD 2) + 1, 'WINDOW','AISLE') END
  FROM COACH c
  JOIN TRAVEL_CLASS tc ON tc.class_code = c.class_code
  JOIN n ON n.i <= c.total_seats;

-- Fare rules for every class/train-type pair in use, General and Tatkal.
INSERT INTO FARE_RULE (class_code,quota_code,train_type,base_fare,rate_per_km,reservation_chg,effective_from)
SELECT p.class_code, q.quota_code, p.train_type, p.base, p.rate, p.res, '2026-01-01'
  FROM (SELECT 'GN' AS quota_code UNION ALL SELECT 'TQ') q
 CROSS JOIN (
    SELECT '2A' AS class_code,'SUPERFAST' AS train_type,300 AS base,1.900 AS rate,50 AS res UNION ALL
    SELECT '3A','SUPERFAST',200,1.350,40 UNION ALL
    SELECT 'SL','SUPERFAST',80,0.550,20 UNION ALL
    SELECT 'CC','SHATABDI',150,1.300,40 UNION ALL
    SELECT '2S','SHATABDI',40,0.400,15 UNION ALL
    SELECT '3A','EXPRESS',180,1.200,40 UNION ALL
    SELECT 'SL','EXPRESS',60,0.480,20) p;

SET @pw = '$2b$10$ytwkmSq5kWkhZGr2bpyQquOKPxcieyrN7tEKPX1PMkhrgbDXC9Aoy';

INSERT INTO STAFF (staff_name,email,role,station_code,phone,password_hash) VALUES
('Asha Admin','admin@rail.test','ADMIN','SBC','9000000001',@pw),
('Chetan Clerk','clerk@rail.test','CLERK','SBC','9000000002',@pw),
('Tara Examiner','tte@rail.test','TTE','NDLS','9000000003',@pw);

INSERT INTO USER_ACCOUNT (full_name,email,phone,password_hash) VALUES
('Priya Nair','priya@rail.test','9876500001',@pw),
('Rahul Verma','rahul@rail.test','9876500002',@pw),
('Sneha Rao','sneha@rail.test','9876500003',@pw),
('Vikram Singh','vikram@rail.test','9876500004',@pw);

-- Schedules for the next 45 days, past runs and booking history for the reports.
DELIMITER $$
CREATE PROCEDURE sp_seed_data()
BEGIN
    DECLARE v_day INT DEFAULT -170;
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_id, v_user INT;
    DECLARE v_date DATE;
    DECLARE v_train CHAR(5);
    DECLARE v_runs CHAR(7);
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_ts DATETIME;
    DECLARE cur CURSOR FOR SELECT train_no, runs_on FROM TRAIN ORDER BY train_no;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    SET @rail_seed = 1;
    WHILE v_day <= 45 DO
        SET v_date = CURDATE() + INTERVAL v_day DAY;
        -- Past dates: one run every ten days is enough for monthly reports.
        IF v_day >= 0 OR v_day MOD 10 = 0 THEN
            SET v_done = 0;
            OPEN cur;
            each_train: LOOP
                FETCH cur INTO v_train, v_runs;
                IF v_done THEN LEAVE each_train; END IF;
                IF SUBSTRING(v_runs, WEEKDAY(v_date) + 1, 1) = 'Y' THEN
                    CALL sp_create_schedule(v_train, v_date, v_id);
                    IF v_day < 0 THEN
                        -- Fill most of each past run. Fixed pattern, so reports are repeatable.
                        SET v_i = 0;
                        WHILE v_i < 3 + (ABS(v_day) MOD 4) DO
                            SET v_user = 1 + (v_i MOD 4);
                            CALL sp_seed_booking(v_user, v_id, v_train, v_i);
                            SET v_i = v_i + 1;
                        END WHILE;
                    END IF;
                END IF;
            END LOOP;
            CLOSE cur;
            SET v_done = 0;
        END IF;
        SET v_day = v_day + 1;
    END WHILE;
    SET @rail_seed = NULL;

    -- Booking times follow the journey date, ten days earlier.
    UPDATE BOOKING b JOIN SCHEDULE s ON s.schedule_id = b.schedule_id
       SET b.booking_ts = TIMESTAMP(s.journey_date - INTERVAL 10 DAY, '10:00:00')
     WHERE s.journey_date < CURDATE();
    UPDATE PAYMENT p JOIN BOOKING b ON b.pnr = p.pnr
       SET p.paid_at = b.booking_ts
     WHERE b.booking_ts < NOW() - INTERVAL 1 DAY;
    UPDATE SCHEDULE SET run_status = 'COMPLETED' WHERE journey_date < CURDATE();
END$$

-- One past booking: origin to terminus in a class this train has, General quota.
CREATE PROCEDURE sp_seed_booking(IN p_user INT, IN p_sched INT, IN p_train CHAR(5), IN p_i INT)
BEGIN
    DECLARE v_from, v_to CHAR(5);
    DECLARE v_class VARCHAR(4);
    SELECT source_code, dest_code INTO v_from, v_to FROM TRAIN WHERE train_no = p_train;
    SELECT class_code INTO v_class FROM COACH WHERE train_no = p_train
     ORDER BY coach_id LIMIT 1 OFFSET 1;
    CALL sp_seed_call(p_user, p_sched, v_from, v_to, v_class,
        JSON_ARRAY(JSON_OBJECT('name', CONCAT('Traveller ', p_sched, '-', p_i),
                               'age', 20 + (p_i * 7) MOD 50,
                               'gender', ELT(1 + p_i MOD 2, 'M', 'F'))));
END$$

-- sp_book_ticket ends in a SELECT; a stored-program caller cannot swallow that,
-- so the seed runner simply discards result sets.
CREATE PROCEDURE sp_seed_call(IN p_user INT, IN p_sched INT, IN p_from CHAR(5), IN p_to CHAR(5),
                              IN p_class VARCHAR(4), IN p_pax JSON)
BEGIN
    CALL sp_book_ticket(p_user, p_sched, p_from, p_to, p_class, 'GN', NULL, 'UPI', p_pax);
END$$
DELIMITER ;

CALL sp_seed_data();
DROP PROCEDURE sp_seed_data;
DROP PROCEDURE sp_seed_booking;
DROP PROCEDURE sp_seed_call;
