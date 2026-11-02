-- ============================================================
-- Functions and stored procedures: the booking engine.
-- All seat movement happens here, inside one transaction, so the web
-- layer cannot leave AVAILABILITY, TICKET_PASSENGER and WAITLIST out of step.
-- ============================================================
USE railway_db;

DELIMITER $$

-- Fare for ONE passenger, using the rule valid on the journey date.
CREATE FUNCTION fn_compute_fare(p_class VARCHAR(4), p_quota VARCHAR(4),
                                p_type VARCHAR(20), p_km INT, p_on DATE)
RETURNS DECIMAL(10,2) READS SQL DATA
BEGIN
    DECLARE v_fare DECIMAL(10,2) DEFAULT NULL;
    SELECT (fr.base_fare + fr.rate_per_km * p_km + fr.reservation_chg)
           * (1 + q.surcharge_pct / 100)
      INTO v_fare
      FROM FARE_RULE fr
      JOIN QUOTA q ON q.quota_code = fr.quota_code
     WHERE fr.class_code = p_class AND fr.quota_code = p_quota AND fr.train_type = p_type
       AND fr.effective_from <= p_on
       AND (fr.effective_to IS NULL OR fr.effective_to >= p_on)
     ORDER BY fr.effective_from DESC
     LIMIT 1;
    IF v_fare IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No fare rule for this class, quota and date';
    END IF;
    RETURN ROUND(v_fare, 2);
END$$

-- Share of a confirmed fare returned, by hours left before departure.
CREATE FUNCTION fn_refund_pct(p_hours DECIMAL(10,2))
RETURNS DECIMAL(5,2) DETERMINISTIC
BEGIN
    RETURN CASE
        WHEN p_hours >= 48 THEN 90.00
        WHEN p_hours >= 12 THEN 75.00
        WHEN p_hours >= 4  THEN 50.00
        ELSE 0.00
    END;
END$$

-- First free seat of a class on a schedule, preferring the requested berth.
-- NOT EXISTS here is a correlated subquery: it runs once per candidate seat.
CREATE FUNCTION fn_free_seat(p_schedule INT, p_train CHAR(5), p_class VARCHAR(4), p_pref VARCHAR(12))
RETURNS INT READS SQL DATA
BEGIN
    DECLARE v_seat INT DEFAULT NULL;
    SELECT st.seat_id INTO v_seat
      FROM SEAT st
      JOIN COACH c ON c.coach_id = st.coach_id
     WHERE c.train_no = p_train AND c.class_code = p_class
       AND NOT EXISTS (SELECT 1
                         FROM TICKET_PASSENGER tp
                         JOIN BOOKING b ON b.pnr = tp.pnr
                        WHERE tp.seat_id = st.seat_id
                          AND b.schedule_id = p_schedule
                          AND tp.current_status = 'CNF')
     ORDER BY (st.berth_type = p_pref) DESC, c.coach_code, st.seat_no
     LIMIT 1;
    RETURN v_seat;
END$$

-- Random unused 10-digit PNR.
CREATE FUNCTION fn_new_pnr()
RETURNS CHAR(10) NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_pnr CHAR(10);
    REPEAT
        SET v_pnr = CAST(FLOOR(1000000000 + RAND() * 8999999999) AS CHAR);
    UNTIL NOT EXISTS (SELECT 1 FROM BOOKING WHERE pnr = v_pnr) END REPEAT;
    RETURN v_pnr;
END$$

-- Booking-level status derived from its passengers.
CREATE PROCEDURE sp_refresh_booking_status(IN p_pnr CHAR(10))
BEGIN
    DECLARE v_cnf, v_rac, v_wl, v_can, v_all INT;
    SELECT SUM(current_status = 'CNF'), SUM(current_status = 'RAC'),
           SUM(current_status = 'WL'),  SUM(current_status = 'CAN'), COUNT(*)
      INTO v_cnf, v_rac, v_wl, v_can, v_all
      FROM TICKET_PASSENGER WHERE pnr = p_pnr;
    UPDATE BOOKING SET booking_status = CASE
            WHEN v_can = v_all THEN 'CANCELLED'
            WHEN v_cnf = v_all THEN 'CONFIRMED'
            WHEN v_rac = v_all THEN 'RAC'
            WHEN v_wl  = v_all THEN 'WAITLISTED'
            ELSE 'PARTIAL' END
     WHERE pnr = p_pnr;
END$$

-- Moves the queue forward after capacity is freed. Called inside a caller's
-- transaction, which already holds the AVAILABILITY row locks.
-- Order: a free seat goes to the earliest RAC, else the earliest WL;
-- a free RAC place goes to the earliest WL.
CREATE PROCEDURE sp_promote_queue(IN p_schedule INT, IN p_class VARCHAR(4), IN p_quota VARCHAR(4))
BEGIN
    DECLARE v_train CHAR(5);
    DECLARE v_seats, v_rac, v_pass, v_seat, v_wlid, v_pos INT;
    DECLARE v_pnr CHAR(10);
    DECLARE v_queue VARCHAR(3);
    DECLARE v_pref VARCHAR(12);

    SELECT train_no INTO v_train FROM SCHEDULE WHERE schedule_id = p_schedule;

    promote: LOOP
        SELECT seats_available, rac_available INTO v_seats, v_rac
          FROM AVAILABILITY
         WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota;

        SET v_wlid = NULL;
        IF v_seats > 0 THEN
            -- ENUM order is RAC, WL, so ORDER BY queue_type serves RAC first.
            SELECT waitlist_id, passenger_id, pnr, queue_type INTO v_wlid, v_pass, v_pnr, v_queue
              FROM WAITLIST
             WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota
               AND is_active
             ORDER BY queue_type, position LIMIT 1;

            IF v_wlid IS NOT NULL THEN
                SELECT berth_pref INTO v_pref FROM TICKET_PASSENGER WHERE passenger_id = v_pass;
                SET v_seat = fn_free_seat(p_schedule, v_train, p_class, v_pref);
                UPDATE TICKET_PASSENGER
                   SET seat_id = v_seat, current_status = 'CNF', status_number = NULL
                 WHERE passenger_id = v_pass;
                UPDATE WAITLIST SET is_active = FALSE WHERE waitlist_id = v_wlid;
                UPDATE AVAILABILITY
                   SET seats_available = seats_available - 1,
                       rac_available   = rac_available + IF(v_queue = 'RAC', 1, 0),
                       waitlist_count  = waitlist_count - IF(v_queue = 'WL', 1, 0)
                 WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota;
                CALL sp_refresh_booking_status(v_pnr);
                ITERATE promote;
            END IF;
        END IF;

        IF v_rac > 0 THEN
            SELECT waitlist_id, passenger_id, pnr INTO v_wlid, v_pass, v_pnr
              FROM WAITLIST
             WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota
               AND is_active AND queue_type = 'WL'
             ORDER BY position LIMIT 1;
            IF v_wlid IS NOT NULL THEN
                SELECT COALESCE(MAX(position), 0) + 1 INTO v_pos
                  FROM WAITLIST
                 WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota
                   AND queue_type = 'RAC';
                UPDATE WAITLIST SET queue_type = 'RAC', position = v_pos WHERE waitlist_id = v_wlid;
                UPDATE TICKET_PASSENGER SET current_status = 'RAC', status_number = v_pos
                 WHERE passenger_id = v_pass;
                UPDATE AVAILABILITY
                   SET rac_available = rac_available - 1, waitlist_count = waitlist_count - 1
                 WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota;
                CALL sp_refresh_booking_status(v_pnr);
                ITERATE promote;
            END IF;
        END IF;

        LEAVE promote;
    END LOOP;
END$$

-- Books up to six passengers atomically. p_passengers is a JSON array of
-- {name, age, gender, berth_pref}. Result set: pnr, total_fare, booking_status.
CREATE PROCEDURE sp_book_ticket(
    IN p_user INT, IN p_schedule INT, IN p_from CHAR(5), IN p_to CHAR(5),
    IN p_class VARCHAR(4), IN p_quota VARCHAR(4), IN p_staff INT,
    IN p_mode VARCHAR(12), IN p_passengers JSON)
BEGIN
    DECLARE v_n, v_i, v_km, v_pass, v_lock INT DEFAULT 0;
    DECLARE v_seat, v_pos, v_seq1, v_seq2, v_d1, v_d2, v_seats, v_rac INT;
    DECLARE v_train CHAR(5);
    DECLARE v_type VARCHAR(20);
    DECLARE v_status VARCHAR(12);
    DECLARE v_date DATE;
    DECLARE v_fare, v_total DECIMAL(10,2);
    DECLARE v_pnr CHAR(10);
    DECLARE v_name VARCHAR(60);
    DECLARE v_age INT;
    DECLARE v_gender CHAR(1);
    DECLARE v_pref VARCHAR(12);
    DECLARE v_outcome VARCHAR(3);

    -- Any SQL error undoes the whole booking; RESIGNAL passes it on to the API.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_n = JSON_LENGTH(p_passengers);
    IF v_n IS NULL OR v_n NOT BETWEEN 1 AND 6 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A booking must have 1 to 6 passengers';
    END IF;

    SELECT s.train_no, s.journey_date, s.run_status, t.train_type
      INTO v_train, v_date, v_status, v_type
      FROM SCHEDULE s JOIN TRAIN t ON t.train_no = s.train_no
     WHERE s.schedule_id = p_schedule;
    IF v_train IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Schedule not found';
    END IF;
    IF v_status <> 'SCHEDULED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This train is not open for booking';
    END IF;
    -- @rail_seed is set only by 06_seed.sql, to create past journeys for reports.
    IF v_date < CURDATE() AND @rail_seed IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot book a past journey';
    END IF;

    SELECT MAX(CASE WHEN station_code = p_from THEN seq_no END),
           MAX(CASE WHEN station_code = p_to   THEN seq_no END),
           MAX(CASE WHEN station_code = p_from THEN dist_from_src END),
           MAX(CASE WHEN station_code = p_to   THEN dist_from_src END)
      INTO v_seq1, v_seq2, v_d1, v_d2
      FROM ROUTE WHERE train_no = v_train;
    IF v_seq1 IS NULL OR v_seq2 IS NULL OR v_seq1 >= v_seq2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This train does not run between those stations in that order';
    END IF;

    SET v_km    = v_d2 - v_d1;
    SET v_fare  = fn_compute_fare(p_class, p_quota, v_type, v_km, v_date);
    SET v_total = v_fare * v_n;

    START TRANSACTION;

    -- Seats are shared across quotas, so every writer locks ALL the quota rows of
    -- this schedule+class in one fixed order. Same order everywhere = no deadlock here.
    SELECT COUNT(*) INTO v_lock FROM (
        SELECT quota_code FROM AVAILABILITY
         WHERE schedule_id = p_schedule AND class_code = p_class
         ORDER BY quota_code FOR UPDATE) locked;

    SELECT seats_available, rac_available INTO v_seats, v_rac
      FROM AVAILABILITY
     WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota;
    IF v_seats IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This class or quota is not available on this train';
    END IF;

    SET v_pnr = fn_new_pnr();
    INSERT INTO BOOKING (pnr, user_id, schedule_id, from_station, to_station, class_code,
                         quota_code, booked_by_staff, distance_km, total_fare, booking_status)
    VALUES (v_pnr, p_user, p_schedule, p_from, p_to, p_class, p_quota, p_staff, v_km, v_total, 'WAITLISTED');

    WHILE v_i < v_n DO
        SET v_name   = JSON_UNQUOTE(JSON_EXTRACT(p_passengers, CONCAT('$[', v_i, '].name')));
        SET v_age    = JSON_EXTRACT(p_passengers, CONCAT('$[', v_i, '].age'));
        SET v_gender = JSON_UNQUOTE(JSON_EXTRACT(p_passengers, CONCAT('$[', v_i, '].gender')));
        SET v_pref   = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(p_passengers, CONCAT('$[', v_i, '].berth_pref'))), 'NONE');

        IF v_seats > 0 THEN
            SET v_seat = fn_free_seat(p_schedule, v_train, p_class, v_pref);
            SET v_outcome = 'CNF';
            SET v_pos = NULL;
            SET v_seats = v_seats - 1;
            UPDATE AVAILABILITY SET seats_available = seats_available - 1
             WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota;
        ELSE
            SET v_seat = NULL;
            SET v_outcome = IF(v_rac > 0, 'RAC', 'WL');
            SELECT COALESCE(MAX(position), 0) + 1 INTO v_pos
              FROM WAITLIST
             WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota
               AND queue_type = v_outcome;
            IF v_outcome = 'RAC' THEN
                SET v_rac = v_rac - 1;
                UPDATE AVAILABILITY SET rac_available = rac_available - 1
                 WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota;
            ELSE
                UPDATE AVAILABILITY SET waitlist_count = waitlist_count + 1
                 WHERE schedule_id = p_schedule AND class_code = p_class AND quota_code = p_quota;
            END IF;
        END IF;

        INSERT INTO TICKET_PASSENGER (pnr, passenger_name, age, gender, berth_pref, seat_id, current_status, status_number)
        VALUES (v_pnr, v_name, v_age, v_gender, v_pref, v_seat, v_outcome, v_pos);
        SET v_pass = LAST_INSERT_ID();

        IF v_outcome <> 'CNF' THEN
            INSERT INTO WAITLIST (schedule_id, class_code, quota_code, pnr, passenger_id, queue_type, position)
            VALUES (p_schedule, p_class, p_quota, v_pnr, v_pass, v_outcome, v_pos);
        END IF;

        SET v_i = v_i + 1;
    END WHILE;

    CALL sp_refresh_booking_status(v_pnr);

    -- Payment is simulated: the row is real, no money gateway is contacted.
    INSERT INTO PAYMENT (pnr, amount, mode, txn_ref, pay_status)
    VALUES (v_pnr, v_total, p_mode, CONCAT('TXN', v_pnr, UNIX_TIMESTAMP()), 'SUCCESS');

    COMMIT;

    SELECT b.pnr, b.total_fare, b.booking_status FROM BOOKING b WHERE b.pnr = v_pnr;
END$$

-- Cancels one passenger, or every active passenger when p_passenger is NULL,
-- refunds them, then promotes the queue. Result set 1: refund summary.
-- Result set 2: every passenger moved by the promotion.
CREATE PROCEDURE sp_cancel_ticket(IN p_pnr CHAR(10), IN p_passenger INT, IN p_reason VARCHAR(120))
BEGIN
    DECLARE v_schedule, v_pass INT;
    DECLARE v_lock, v_pax, v_count INT DEFAULT 0;
    DECLARE v_class, v_quota VARCHAR(4);
    DECLARE v_total, v_share, v_refund, v_charge, v_sum DECIMAL(10,2) DEFAULT 0;
    DECLARE v_from CHAR(5);
    DECLARE v_status VARCHAR(3);
    DECLARE v_hours DECIMAL(10,2);
    DECLARE v_run VARCHAR(12);
    DECLARE v_mark BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT schedule_id, class_code, quota_code, total_fare, from_station
      INTO v_schedule, v_class, v_quota, v_total, v_from
      FROM BOOKING WHERE pnr = p_pnr;
    IF v_schedule IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PNR not found';
    END IF;

    SELECT s.run_status,
           TIMESTAMPDIFF(MINUTE, NOW(),
               TIMESTAMP(s.journey_date + INTERVAL r.day_offset DAY, r.departure_time)) / 60
      INTO v_run, v_hours
      FROM SCHEDULE s
      JOIN ROUTE r ON r.train_no = s.train_no AND r.station_code = v_from
     WHERE s.schedule_id = v_schedule;
    IF v_run <> 'SCHEDULED' OR v_hours <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This train has already departed';
    END IF;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_lock FROM (
        SELECT quota_code FROM AVAILABILITY
         WHERE schedule_id = v_schedule AND class_code = v_class
         ORDER BY quota_code FOR UPDATE) locked;

    SELECT COALESCE(MAX(history_id), 0) INTO v_mark FROM TICKET_STATUS_HISTORY;
    SELECT COUNT(*) INTO v_pax FROM TICKET_PASSENGER WHERE pnr = p_pnr;
    SET v_share = v_total / v_pax;

    cancel_each: LOOP
        SET v_pass = NULL;
        SELECT MIN(passenger_id) INTO v_pass
          FROM TICKET_PASSENGER
         WHERE pnr = p_pnr AND current_status <> 'CAN'
           AND (p_passenger IS NULL OR passenger_id = p_passenger);
        IF v_pass IS NULL THEN
            LEAVE cancel_each;
        END IF;

        SELECT current_status INTO v_status FROM TICKET_PASSENGER WHERE passenger_id = v_pass;

        IF v_status = 'CNF' THEN
            SET v_refund = ROUND(v_share * fn_refund_pct(v_hours) / 100, 2);
            UPDATE AVAILABILITY SET seats_available = seats_available + 1
             WHERE schedule_id = v_schedule AND class_code = v_class AND quota_code = v_quota;
        ELSE
            -- RAC and WL hold no berth, so only a flat clerkage is kept.
            SET v_refund = GREATEST(v_share - 20, 0);
            IF v_status = 'RAC' THEN
                UPDATE AVAILABILITY SET rac_available = rac_available + 1
                 WHERE schedule_id = v_schedule AND class_code = v_class AND quota_code = v_quota;
            ELSE
                UPDATE AVAILABILITY SET waitlist_count = waitlist_count - 1
                 WHERE schedule_id = v_schedule AND class_code = v_class AND quota_code = v_quota;
            END IF;
            UPDATE WAITLIST SET is_active = FALSE WHERE passenger_id = v_pass;
        END IF;

        SET v_charge = v_share - v_refund;
        UPDATE TICKET_PASSENGER SET current_status = 'CAN', seat_id = NULL, status_number = NULL
         WHERE passenger_id = v_pass;
        INSERT INTO CANCELLATION (pnr, passenger_id, cancellation_chg, refund_amount, reason)
        VALUES (p_pnr, v_pass, v_charge, v_refund, p_reason);

        SET v_sum = v_sum + v_refund;
        SET v_count = v_count + 1;
    END LOOP;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nothing to cancel: passenger not found or already cancelled';
    END IF;

    IF v_sum > 0 THEN
        INSERT INTO PAYMENT (pnr, amount, mode, txn_ref, pay_status)
        SELECT p_pnr, v_sum, mode, CONCAT('RFD', p_pnr, UNIX_TIMESTAMP(), v_mark), 'REFUNDED'
          FROM PAYMENT WHERE pnr = p_pnr AND pay_status = 'SUCCESS' LIMIT 1;
    END IF;

    CALL sp_refresh_booking_status(p_pnr);
    CALL sp_promote_queue(v_schedule, v_class, v_quota);

    COMMIT;

    SELECT p_pnr AS pnr, v_count AS cancelled, v_sum AS refund_amount,
           (SELECT booking_status FROM BOOKING WHERE pnr = p_pnr) AS booking_status;

    SELECT h.pnr, h.passenger_id, tp.passenger_name, h.old_status, h.new_status, h.seat_id,
           b.schedule_id, b.class_code, b.quota_code
      FROM TICKET_STATUS_HISTORY h
      JOIN TICKET_PASSENGER tp ON tp.passenger_id = h.passenger_id
      JOIN BOOKING b ON b.pnr = h.pnr
     WHERE h.history_id > v_mark AND h.new_status <> 'CAN'
     ORDER BY h.history_id;
END$$

-- Opens a train for one date, creating the AVAILABILITY rows.
-- Seats per class are split 70/30 between General and Tatkal. RAC places: General only.
CREATE PROCEDURE sp_create_schedule(IN p_train CHAR(5), IN p_date DATE, OUT p_schedule INT)
BEGIN
    DECLARE v_runs CHAR(7);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT runs_on INTO v_runs FROM TRAIN WHERE train_no = p_train;
    IF v_runs IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Train not found';
    END IF;
    IF SUBSTRING(v_runs, WEEKDAY(p_date) + 1, 1) <> 'Y' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This train does not run on that weekday';
    END IF;

    START TRANSACTION;
    INSERT INTO SCHEDULE (train_no, journey_date) VALUES (p_train, p_date);
    SET p_schedule = LAST_INSERT_ID();

    INSERT INTO AVAILABILITY (schedule_id, class_code, quota_code, total_seats, seats_available, rac_available)
    SELECT p_schedule, c.class_code, 'GN', CEIL(SUM(c.total_seats) * 0.7), CEIL(SUM(c.total_seats) * 0.7),
           IF(tc.has_berth, 2, 0)
      FROM COACH c JOIN TRAVEL_CLASS tc ON tc.class_code = c.class_code
     WHERE c.train_no = p_train
     GROUP BY c.class_code, tc.has_berth;

    INSERT INTO AVAILABILITY (schedule_id, class_code, quota_code, total_seats, seats_available, rac_available)
    SELECT p_schedule, c.class_code, 'TQ', SUM(c.total_seats) - CEIL(SUM(c.total_seats) * 0.7),
           SUM(c.total_seats) - CEIL(SUM(c.total_seats) * 0.7), 0
      FROM COACH c
     WHERE c.train_no = p_train
     GROUP BY c.class_code
    HAVING SUM(c.total_seats) - CEIL(SUM(c.total_seats) * 0.7) > 0;
    COMMIT;
END$$

DELIMITER ;
