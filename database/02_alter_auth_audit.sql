-- ============================================================
-- Schema evolution after the Week 4 design.
-- Staff need to log in, and every ticket status change must be auditable.
-- ============================================================
USE railway_db;

ALTER TABLE STAFF
    ADD COLUMN email         VARCHAR(100) NOT NULL AFTER staff_name,
    ADD COLUMN password_hash CHAR(60)     NOT NULL AFTER phone,
    ADD CONSTRAINT uq_staff_email UNIQUE (email),
    ADD CONSTRAINT chk_staff_email CHECK (email LIKE '%_@_%._%');

-- ---------- 18. TICKET_STATUS_HISTORY  (written only by triggers) ----------
CREATE TABLE TICKET_STATUS_HISTORY (
    history_id   BIGINT AUTO_INCREMENT PRIMARY KEY,
    passenger_id INT       NOT NULL,
    pnr          CHAR(10)  NOT NULL,
    old_status   ENUM('CNF','RAC','WL','CAN'),            -- NULL on first insert
    new_status   ENUM('CNF','RAC','WL','CAN') NOT NULL,
    seat_id      INT,
    changed_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_hist_pass FOREIGN KEY (passenger_id) REFERENCES TICKET_PASSENGER(passenger_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_hist_pnr  FOREIGN KEY (pnr) REFERENCES BOOKING(pnr)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_hist_pnr ON TICKET_STATUS_HISTORY (pnr, changed_at);
