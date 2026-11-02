-- ============================================================
-- Reporting views and the admin operations behind the dashboard.
-- ============================================================
USE railway_db;

-- Class-wise occupancy per run. Capacity comes from AVAILABILITY; occupied seats
-- are counted from the tickets themselves, so this also cross-checks the counters.
CREATE OR REPLACE VIEW v_occupancy AS
SELECT s.schedule_id, s.train_no, t.train_name, s.journey_date, a.class_code,
       SUM(a.total_seats) AS total_seats,
       (SELECT COUNT(*)
          FROM TICKET_PASSENGER tp JOIN BOOKING b ON b.pnr = tp.pnr
         WHERE b.schedule_id = s.schedule_id AND b.class_code = a.class_code
           AND tp.current_status = 'CNF') AS seats_booked,
       SUM(a.waitlist_count) AS waitlisted
  FROM SCHEDULE s
  JOIN TRAIN t        ON t.train_no = s.train_no
  JOIN AVAILABILITY a ON a.schedule_id = s.schedule_id
 GROUP BY s.schedule_id, s.train_no, t.train_name, s.journey_date, a.class_code;

-- Money in and out per train and month.
CREATE OR REPLACE VIEW v_revenue AS
SELECT s.train_no, t.train_name, DATE_FORMAT(p.paid_at, '%Y-%m') AS month,
       SUM(CASE WHEN p.pay_status = 'SUCCESS'  THEN p.amount ELSE 0 END) AS collected,
       SUM(CASE WHEN p.pay_status = 'REFUNDED' THEN p.amount ELSE 0 END) AS refunded,
       SUM(CASE p.pay_status WHEN 'SUCCESS' THEN p.amount WHEN 'REFUNDED' THEN -p.amount ELSE 0 END) AS net_revenue
  FROM PAYMENT p
  JOIN BOOKING b  ON b.pnr = p.pnr
  JOIN SCHEDULE s ON s.schedule_id = b.schedule_id
  JOIN TRAIN t    ON t.train_no = s.train_no
 GROUP BY s.train_no, t.train_name, DATE_FORMAT(p.paid_at, '%Y-%m');

-- Bookings with their cancellation totals. LEFT JOIN keeps uncancelled bookings.
CREATE OR REPLACE VIEW v_passenger_history AS
SELECT b.user_id, b.pnr, b.booking_ts, b.booking_status, b.total_fare, s.journey_date, t.train_name,
       b.from_station, b.to_station,
       COALESCE(SUM(c.refund_amount), 0) AS refunded,
       MAX(c.cancelled_at) AS last_cancelled_at
  FROM BOOKING b
  JOIN SCHEDULE s ON s.schedule_id = b.schedule_id
  JOIN TRAIN t    ON t.train_no = s.train_no
  LEFT JOIN CANCELLATION c ON c.pnr = b.pnr
 GROUP BY b.user_id, b.pnr, b.booking_ts, b.booking_status, b.total_fare, s.journey_date,
          t.train_name, b.from_station, b.to_station;

DELIMITER $$

-- Changing a price never edits history: it closes the current rule and starts a new one.
CREATE PROCEDURE sp_set_fare(IN p_class VARCHAR(4), IN p_quota VARCHAR(4), IN p_type VARCHAR(20),
                             IN p_base DECIMAL(8,2), IN p_rate DECIMAL(6,3), IN p_res DECIMAL(6,2),
                             IN p_from DATE)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    START TRANSACTION;
    UPDATE FARE_RULE
       SET effective_to = p_from - INTERVAL 1 DAY
     WHERE class_code = p_class AND quota_code = p_quota AND train_type = p_type
       AND effective_to IS NULL AND effective_from < p_from;
    INSERT INTO FARE_RULE (class_code, quota_code, train_type, base_fare, rate_per_km, reservation_chg, effective_from)
    VALUES (p_class, p_quota, p_type, p_base, p_rate, p_res, p_from);
    COMMIT;
END$$

-- A run with no tickets can be withdrawn. AVAILABILITY rows go with it through ON DELETE CASCADE;
-- a run with tickets is protected by fk_bk_sched (ON DELETE RESTRICT).
CREATE PROCEDURE sp_delete_schedule(IN p_schedule INT)
BEGIN
    DELETE FROM SCHEDULE WHERE schedule_id = p_schedule;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Schedule not found';
    END IF;
END$$

DELIMITER ;
