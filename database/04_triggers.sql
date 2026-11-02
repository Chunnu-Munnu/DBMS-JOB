-- ============================================================
-- Triggers: rules a table CHECK cannot express because they span tables.
-- They hold even if someone bypasses the stored procedures.
-- ============================================================
USE railway_db;

DELIMITER $$

-- The same physical seat cannot be confirmed twice on one schedule. CHECK cannot
-- do this: schedule_id lives on BOOKING, one join away from seat_id.
CREATE TRIGGER trg_tp_seat_guard_ins BEFORE INSERT ON TICKET_PASSENGER
FOR EACH ROW
BEGIN
    IF NEW.seat_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM TICKET_PASSENGER tp
          JOIN BOOKING b  ON b.pnr = tp.pnr
          JOIN BOOKING me ON me.pnr = NEW.pnr
         WHERE tp.seat_id = NEW.seat_id AND b.schedule_id = me.schedule_id
           AND tp.current_status = 'CNF') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat already allotted on this schedule';
    END IF;
END$$

CREATE TRIGGER trg_tp_seat_guard_upd BEFORE UPDATE ON TICKET_PASSENGER
FOR EACH ROW
BEGIN
    IF NEW.seat_id IS NOT NULL AND NOT (NEW.seat_id <=> OLD.seat_id) AND EXISTS (
        SELECT 1 FROM TICKET_PASSENGER tp
          JOIN BOOKING b  ON b.pnr = tp.pnr
          JOIN BOOKING me ON me.pnr = NEW.pnr
         WHERE tp.seat_id = NEW.seat_id AND b.schedule_id = me.schedule_id
           AND tp.current_status = 'CNF' AND tp.passenger_id <> OLD.passenger_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat already allotted on this schedule';
    END IF;
END$$

-- Boarding must come before alighting on this train's route.
CREATE TRIGGER trg_booking_station_order BEFORE INSERT ON BOOKING
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM SCHEDULE s
          JOIN ROUTE r1 ON r1.train_no = s.train_no AND r1.station_code = NEW.from_station
          JOIN ROUTE r2 ON r2.train_no = s.train_no AND r2.station_code = NEW.to_station
         WHERE s.schedule_id = NEW.schedule_id AND r1.seq_no < r2.seq_no) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid station sequence for this train';
    END IF;
END$$

-- Refunds on a PNR can never add up to more than was paid.
CREATE TRIGGER trg_cancel_refund_cap BEFORE INSERT ON CANCELLATION
FOR EACH ROW
BEGIN
    DECLARE v_paid, v_refunded DECIMAL(10,2);
    SELECT COALESCE(SUM(amount), 0) INTO v_paid FROM PAYMENT
     WHERE pnr = NEW.pnr AND pay_status = 'SUCCESS';
    SELECT COALESCE(SUM(refund_amount), 0) INTO v_refunded FROM CANCELLATION
     WHERE pnr = NEW.pnr;
    IF v_refunded + NEW.refund_amount > v_paid + 0.05 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Refund exceeds amount paid';
    END IF;
END$$

-- Audit trail of every ticket status change.
CREATE TRIGGER trg_tp_history_ins AFTER INSERT ON TICKET_PASSENGER
FOR EACH ROW
BEGIN
    INSERT INTO TICKET_STATUS_HISTORY (passenger_id, pnr, old_status, new_status, seat_id)
    VALUES (NEW.passenger_id, NEW.pnr, NULL, NEW.current_status, NEW.seat_id);
END$$

CREATE TRIGGER trg_tp_history_upd AFTER UPDATE ON TICKET_PASSENGER
FOR EACH ROW
BEGIN
    IF NEW.current_status <> OLD.current_status THEN
        INSERT INTO TICKET_STATUS_HISTORY (passenger_id, pnr, old_status, new_status, seat_id)
        VALUES (NEW.passenger_id, NEW.pnr, OLD.current_status, NEW.current_status, NEW.seat_id);
    END IF;
END$$

DELIMITER ;
