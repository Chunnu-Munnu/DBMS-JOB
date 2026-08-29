-- ============================================================
-- Railway Reservation & PNR Management System
-- DDL  |  Target: MySQL 8.0 (InnoDB, utf8mb4)
-- ============================================================

DROP DATABASE IF EXISTS railway_db;
CREATE DATABASE railway_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE railway_db;

-- ---------- 1. STATION ----------
CREATE TABLE STATION (
    station_code   CHAR(5)      PRIMARY KEY,
    station_name   VARCHAR(80)  NOT NULL,
    city           VARCHAR(50)  NOT NULL,
    state          VARCHAR(50)  NOT NULL,
    zone           VARCHAR(10),
    CONSTRAINT uq_station_name UNIQUE (station_name, city)
) ENGINE=InnoDB;

-- ---------- 2. TRAIN ----------
CREATE TABLE TRAIN (
    train_no        CHAR(5)     PRIMARY KEY,
    train_name      VARCHAR(80) NOT NULL,
    train_type      ENUM('EXPRESS','SUPERFAST','RAJDHANI','SHATABDI','PASSENGER','VANDE_BHARAT')
                                NOT NULL DEFAULT 'EXPRESS',
    source_code     CHAR(5)     NOT NULL,
    dest_code       CHAR(5)     NOT NULL,
    runs_on         CHAR(7)     NOT NULL DEFAULT 'YYYYYYY',   -- Mon..Sun flags
    total_distance  INT         NOT NULL,
    CONSTRAINT fk_train_src  FOREIGN KEY (source_code) REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_train_dest FOREIGN KEY (dest_code)   REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_train_ends CHECK (source_code <> dest_code),
    CONSTRAINT chk_train_dist CHECK (total_distance > 0),
    CONSTRAINT chk_runs_on    CHECK (runs_on REGEXP '^[YN]{7}$')
) ENGINE=InnoDB;

-- ---------- 3. ROUTE  (weak entity: identified by TRAIN + stop sequence) ----------
CREATE TABLE ROUTE (
    train_no        CHAR(5)  NOT NULL,
    seq_no          SMALLINT NOT NULL,
    station_code    CHAR(5)  NOT NULL,
    arrival_time    TIME,                       -- NULL at originating station
    departure_time  TIME,                       -- NULL at terminating station
    day_offset      TINYINT  NOT NULL DEFAULT 0,
    dist_from_src   INT      NOT NULL,
    halt_minutes    SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (train_no, seq_no),
    CONSTRAINT fk_route_train   FOREIGN KEY (train_no)     REFERENCES TRAIN(train_no)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_route_station FOREIGN KEY (station_code) REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_route_stop  UNIQUE (train_no, station_code),
    CONSTRAINT chk_seq        CHECK (seq_no > 0),
    CONSTRAINT chk_route_dist CHECK (dist_from_src >= 0),
    CONSTRAINT chk_halt       CHECK (halt_minutes BETWEEN 0 AND 240)
) ENGINE=InnoDB;

-- ---------- 4. TRAVEL_CLASS ----------
CREATE TABLE TRAVEL_CLASS (
    class_code   VARCHAR(4)  PRIMARY KEY,       -- 1A, 2A, 3A, SL, CC, 2S
    class_name   VARCHAR(40) NOT NULL UNIQUE,
    is_ac        BOOLEAN     NOT NULL DEFAULT FALSE,
    has_berth    BOOLEAN     NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

-- ---------- 5. QUOTA ----------
CREATE TABLE QUOTA (
    quota_code    VARCHAR(4)   PRIMARY KEY,     -- GN, TQ, LD, SS, PH
    quota_name    VARCHAR(40)  NOT NULL UNIQUE,
    surcharge_pct DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT chk_surcharge CHECK (surcharge_pct BETWEEN 0 AND 100)
) ENGINE=InnoDB;

-- ---------- 6. COACH ----------
CREATE TABLE COACH (
    coach_id     INT AUTO_INCREMENT PRIMARY KEY,
    train_no     CHAR(5)    NOT NULL,
    coach_code   VARCHAR(5) NOT NULL,           -- B1, A2, S4
    class_code   VARCHAR(4) NOT NULL,
    total_seats  SMALLINT   NOT NULL,
    CONSTRAINT fk_coach_train FOREIGN KEY (train_no)   REFERENCES TRAIN(train_no)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_coach_class FOREIGN KEY (class_code) REFERENCES TRAVEL_CLASS(class_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_coach UNIQUE (train_no, coach_code),
    CONSTRAINT chk_coach_seats CHECK (total_seats BETWEEN 1 AND 100)
) ENGINE=InnoDB;

-- ---------- 7. SEAT ----------
CREATE TABLE SEAT (
    seat_id     INT AUTO_INCREMENT PRIMARY KEY,
    coach_id    INT      NOT NULL,
    seat_no     SMALLINT NOT NULL,
    berth_type  ENUM('LOWER','MIDDLE','UPPER','SIDE_LOWER','SIDE_UPPER','WINDOW','AISLE') NOT NULL,
    CONSTRAINT fk_seat_coach FOREIGN KEY (coach_id) REFERENCES COACH(coach_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT uq_seat UNIQUE (coach_id, seat_no),
    CONSTRAINT chk_seat_no CHECK (seat_no > 0)
) ENGINE=InnoDB;

-- ---------- 8. SCHEDULE  (one running instance of a train on a date) ----------
CREATE TABLE SCHEDULE (
    schedule_id    INT AUTO_INCREMENT PRIMARY KEY,
    train_no       CHAR(5) NOT NULL,
    journey_date   DATE    NOT NULL,
    run_status     ENUM('SCHEDULED','RUNNING','COMPLETED','CANCELLED') NOT NULL DEFAULT 'SCHEDULED',
    chart_prepared BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_sched_train FOREIGN KEY (train_no) REFERENCES TRAIN(train_no)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT uq_schedule UNIQUE (train_no, journey_date)
) ENGINE=InnoDB;

-- ---------- 9. AVAILABILITY  (seats left per schedule / class / quota) ----------
CREATE TABLE AVAILABILITY (
    schedule_id     INT        NOT NULL,
    class_code      VARCHAR(4) NOT NULL,
    quota_code      VARCHAR(4) NOT NULL,
    total_seats     SMALLINT   NOT NULL,
    seats_available SMALLINT   NOT NULL,
    rac_available   SMALLINT   NOT NULL DEFAULT 0,
    waitlist_count  SMALLINT   NOT NULL DEFAULT 0,
    PRIMARY KEY (schedule_id, class_code, quota_code),
    CONSTRAINT fk_avl_sched FOREIGN KEY (schedule_id) REFERENCES SCHEDULE(schedule_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_avl_class FOREIGN KEY (class_code) REFERENCES TRAVEL_CLASS(class_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_avl_quota FOREIGN KEY (quota_code) REFERENCES QUOTA(quota_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_avl    CHECK (seats_available >= 0 AND seats_available <= total_seats),
    CONSTRAINT chk_avl_wl CHECK (waitlist_count >= 0 AND rac_available >= 0)
) ENGINE=InnoDB;

-- ---------- 10. STAFF ----------
CREATE TABLE STAFF (
    staff_id     INT AUTO_INCREMENT PRIMARY KEY,
    staff_name   VARCHAR(60) NOT NULL,
    role         ENUM('CLERK','TTE','ADMIN') NOT NULL,
    station_code CHAR(5),
    phone        CHAR(10)    NOT NULL UNIQUE,
    CONSTRAINT fk_staff_station FOREIGN KEY (station_code) REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_staff_phone CHECK (phone REGEXP '^[6-9][0-9]{9}$')
) ENGINE=InnoDB;

-- ---------- 11. USER_ACCOUNT ----------
CREATE TABLE USER_ACCOUNT (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(60)  NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,
    phone         CHAR(10)     NOT NULL UNIQUE,
    password_hash CHAR(60)     NOT NULL,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_user_phone CHECK (phone REGEXP '^[6-9][0-9]{9}$'),
    CONSTRAINT chk_user_email CHECK (email LIKE '%_@_%._%')
) ENGINE=InnoDB;

-- ---------- 12. BOOKING  (the PNR) ----------
CREATE TABLE BOOKING (
    pnr             CHAR(10)   PRIMARY KEY,
    user_id         INT        NOT NULL,
    schedule_id     INT        NOT NULL,
    from_station    CHAR(5)    NOT NULL,
    to_station      CHAR(5)    NOT NULL,
    class_code      VARCHAR(4) NOT NULL,
    quota_code      VARCHAR(4) NOT NULL,
    booked_by_staff INT,                                  -- NULL => online booking
    booking_ts      TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    distance_km     INT        NOT NULL,
    total_fare      DECIMAL(10,2) NOT NULL,
    booking_status  ENUM('CONFIRMED','RAC','WAITLISTED','PARTIAL','CANCELLED') NOT NULL DEFAULT 'WAITLISTED',
    CONSTRAINT fk_bk_user   FOREIGN KEY (user_id)      REFERENCES USER_ACCOUNT(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_sched  FOREIGN KEY (schedule_id)  REFERENCES SCHEDULE(schedule_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_from   FOREIGN KEY (from_station) REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_to     FOREIGN KEY (to_station)   REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_class  FOREIGN KEY (class_code)   REFERENCES TRAVEL_CLASS(class_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_quota  FOREIGN KEY (quota_code)   REFERENCES QUOTA(quota_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_staff  FOREIGN KEY (booked_by_staff) REFERENCES STAFF(staff_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_bk_stations CHECK (from_station <> to_station),
    CONSTRAINT chk_bk_fare     CHECK (total_fare >= 0),
    CONSTRAINT chk_bk_dist     CHECK (distance_km > 0),
    CONSTRAINT chk_pnr_fmt     CHECK (pnr REGEXP '^[0-9]{10}$')
) ENGINE=InnoDB;

-- ---------- 13. TICKET_PASSENGER  (multivalued: passengers under one PNR) ----------
CREATE TABLE TICKET_PASSENGER (
    passenger_id   INT AUTO_INCREMENT PRIMARY KEY,
    pnr            CHAR(10)    NOT NULL,
    passenger_name VARCHAR(60) NOT NULL,
    age            TINYINT     NOT NULL,
    gender         ENUM('M','F','O') NOT NULL,
    berth_pref     ENUM('LOWER','MIDDLE','UPPER','SIDE_LOWER','SIDE_UPPER','NONE') NOT NULL DEFAULT 'NONE',
    seat_id        INT,                                   -- NULL until a seat is allotted
    current_status ENUM('CNF','RAC','WL','CAN') NOT NULL DEFAULT 'WL',
    status_number  SMALLINT,                              -- WL/RAC position; NULL when CNF
    CONSTRAINT fk_tp_pnr  FOREIGN KEY (pnr)     REFERENCES BOOKING(pnr)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_tp_seat FOREIGN KEY (seat_id) REFERENCES SEAT(seat_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT uq_tp_name UNIQUE (pnr, passenger_name),
    CONSTRAINT chk_tp_age CHECK (age BETWEEN 0 AND 120),
    CONSTRAINT chk_tp_status CHECK (
        (current_status = 'CNF' AND seat_id IS NOT NULL) OR current_status <> 'CNF')
) ENGINE=InnoDB;

-- ---------- 14. WAITLIST  (FIFO queue per schedule/class/quota) ----------
CREATE TABLE WAITLIST (
    waitlist_id  INT AUTO_INCREMENT PRIMARY KEY,
    schedule_id  INT        NOT NULL,
    class_code   VARCHAR(4) NOT NULL,
    quota_code   VARCHAR(4) NOT NULL,
    pnr          CHAR(10)   NOT NULL,
    passenger_id INT        NOT NULL,
    queue_type   ENUM('RAC','WL') NOT NULL,
    position     SMALLINT   NOT NULL,
    enqueued_at  TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active    BOOLEAN    NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_wl_sched FOREIGN KEY (schedule_id)  REFERENCES SCHEDULE(schedule_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_wl_class FOREIGN KEY (class_code)   REFERENCES TRAVEL_CLASS(class_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_wl_quota FOREIGN KEY (quota_code)   REFERENCES QUOTA(quota_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_wl_pnr   FOREIGN KEY (pnr)          REFERENCES BOOKING(pnr)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_wl_pass  FOREIGN KEY (passenger_id) REFERENCES TICKET_PASSENGER(passenger_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT uq_wl_passenger UNIQUE (passenger_id),
    CONSTRAINT uq_wl_position  UNIQUE (schedule_id, class_code, quota_code, queue_type, position),
    CONSTRAINT chk_wl_pos CHECK (position > 0)
) ENGINE=InnoDB;

-- ---------- 15. FARE_RULE ----------
CREATE TABLE FARE_RULE (
    rule_id         INT AUTO_INCREMENT PRIMARY KEY,
    class_code      VARCHAR(4) NOT NULL,
    quota_code      VARCHAR(4) NOT NULL,
    train_type      ENUM('EXPRESS','SUPERFAST','RAJDHANI','SHATABDI','PASSENGER','VANDE_BHARAT') NOT NULL,
    base_fare       DECIMAL(8,2) NOT NULL,
    rate_per_km     DECIMAL(6,3) NOT NULL,
    reservation_chg DECIMAL(6,2) NOT NULL DEFAULT 0.00,
    effective_from  DATE NOT NULL,
    effective_to    DATE,
    CONSTRAINT fk_fr_class FOREIGN KEY (class_code) REFERENCES TRAVEL_CLASS(class_code)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_fr_quota FOREIGN KEY (quota_code) REFERENCES QUOTA(quota_code)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT uq_fare UNIQUE (class_code, quota_code, train_type, effective_from),
    CONSTRAINT chk_fare_pos    CHECK (base_fare >= 0 AND rate_per_km >= 0),
    CONSTRAINT chk_fare_period CHECK (effective_to IS NULL OR effective_to > effective_from)
) ENGINE=InnoDB;

-- ---------- 16. PAYMENT ----------
CREATE TABLE PAYMENT (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    pnr        CHAR(10)      NOT NULL,
    amount     DECIMAL(10,2) NOT NULL,
    mode       ENUM('UPI','CARD','NETBANKING','WALLET','CASH') NOT NULL,
    txn_ref    VARCHAR(40)   NOT NULL UNIQUE,
    pay_status ENUM('SUCCESS','FAILED','PENDING','REFUNDED') NOT NULL DEFAULT 'PENDING',
    paid_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pay_pnr FOREIGN KEY (pnr) REFERENCES BOOKING(pnr)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_pay_amt CHECK (amount > 0)
) ENGINE=InnoDB;

-- ---------- 17. CANCELLATION ----------
CREATE TABLE CANCELLATION (
    cancel_id        INT AUTO_INCREMENT PRIMARY KEY,
    pnr              CHAR(10)  NOT NULL,
    passenger_id     INT,                                 -- NULL => whole PNR cancelled
    cancelled_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cancellation_chg DECIMAL(8,2)  NOT NULL DEFAULT 0.00,
    refund_amount    DECIMAL(10,2) NOT NULL,
    reason           VARCHAR(120),
    CONSTRAINT fk_cn_pnr  FOREIGN KEY (pnr)          REFERENCES BOOKING(pnr)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_cn_pass FOREIGN KEY (passenger_id) REFERENCES TICKET_PASSENGER(passenger_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_cn_amt CHECK (refund_amount >= 0 AND cancellation_chg >= 0)
) ENGINE=InnoDB;

-- ============================================================
-- Secondary indexes supporting the five key queries
-- ============================================================
CREATE INDEX idx_route_station ON ROUTE (station_code, train_no);
CREATE INDEX idx_sched_date    ON SCHEDULE (journey_date, train_no);
CREATE INDEX idx_booking_user  ON BOOKING (user_id, booking_ts);
CREATE INDEX idx_booking_sched ON BOOKING (schedule_id, class_code, booking_status);
CREATE INDEX idx_tp_status     ON TICKET_PASSENGER (pnr, current_status);
CREATE INDEX idx_wl_queue      ON WAITLIST (schedule_id, class_code, quota_code, queue_type, is_active, position);
CREATE INDEX idx_pay_status    ON PAYMENT (pay_status, paid_at);
CREATE INDEX idx_coach_train   ON COACH (train_no, class_code);
