-- ============================================================
-- Railway Reservation & PNR Management System
-- DDL  |  SQLite-compatible port of ddl_mysql.sql (for execution/verification)
-- Differences: ENUM -> TEXT + CHECK IN, AUTO_INCREMENT -> INTEGER PRIMARY KEY
--              AUTOINCREMENT, REGEXP -> GLOB, no ENGINE clause.
-- ============================================================

PRAGMA foreign_keys = ON;

CREATE TABLE STATION (
    station_code   CHAR(5)      PRIMARY KEY,
    station_name   VARCHAR(80)  NOT NULL,
    city           VARCHAR(50)  NOT NULL,
    state          VARCHAR(50)  NOT NULL,
    zone           VARCHAR(10),
    CONSTRAINT uq_station_name UNIQUE (station_name, city)
);

CREATE TABLE TRAIN (
    train_no        CHAR(5)     PRIMARY KEY,
    train_name      VARCHAR(80) NOT NULL,
    train_type      VARCHAR(15) NOT NULL DEFAULT 'EXPRESS',
    source_code     CHAR(5)     NOT NULL,
    dest_code       CHAR(5)     NOT NULL,
    runs_on         CHAR(7)     NOT NULL DEFAULT 'YYYYYYY',
    total_distance  INTEGER     NOT NULL,
    CONSTRAINT fk_train_src  FOREIGN KEY (source_code) REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_train_dest FOREIGN KEY (dest_code)   REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_train_type CHECK (train_type IN
        ('EXPRESS','SUPERFAST','RAJDHANI','SHATABDI','PASSENGER','VANDE_BHARAT')),
    CONSTRAINT chk_train_ends CHECK (source_code <> dest_code),
    CONSTRAINT chk_train_dist CHECK (total_distance > 0),
    CONSTRAINT chk_runs_on    CHECK (runs_on GLOB '[YN][YN][YN][YN][YN][YN][YN]')
);

CREATE TABLE ROUTE (
    train_no        CHAR(5)  NOT NULL,
    seq_no          SMALLINT NOT NULL,
    station_code    CHAR(5)  NOT NULL,
    arrival_time    TIME,
    departure_time  TIME,
    day_offset      SMALLINT NOT NULL DEFAULT 0,
    dist_from_src   INTEGER  NOT NULL,
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
);

CREATE TABLE TRAVEL_CLASS (
    class_code   VARCHAR(4)  PRIMARY KEY,
    class_name   VARCHAR(40) NOT NULL UNIQUE,
    is_ac        INTEGER     NOT NULL DEFAULT 0 CHECK (is_ac IN (0,1)),
    has_berth    INTEGER     NOT NULL DEFAULT 1 CHECK (has_berth IN (0,1))
);

CREATE TABLE QUOTA (
    quota_code    VARCHAR(4)   PRIMARY KEY,
    quota_name    VARCHAR(40)  NOT NULL UNIQUE,
    surcharge_pct DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT chk_surcharge CHECK (surcharge_pct BETWEEN 0 AND 100)
);

CREATE TABLE COACH (
    coach_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    train_no     CHAR(5)    NOT NULL,
    coach_code   VARCHAR(5) NOT NULL,
    class_code   VARCHAR(4) NOT NULL,
    total_seats  SMALLINT   NOT NULL,
    CONSTRAINT fk_coach_train FOREIGN KEY (train_no)   REFERENCES TRAIN(train_no)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_coach_class FOREIGN KEY (class_code) REFERENCES TRAVEL_CLASS(class_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_coach UNIQUE (train_no, coach_code),
    CONSTRAINT chk_coach_seats CHECK (total_seats BETWEEN 1 AND 100)
);

CREATE TABLE SEAT (
    seat_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    coach_id    INTEGER  NOT NULL,
    seat_no     SMALLINT NOT NULL,
    berth_type  VARCHAR(12) NOT NULL,
    CONSTRAINT fk_seat_coach FOREIGN KEY (coach_id) REFERENCES COACH(coach_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_berth CHECK (berth_type IN
        ('LOWER','MIDDLE','UPPER','SIDE_LOWER','SIDE_UPPER','WINDOW','AISLE')),
    CONSTRAINT uq_seat UNIQUE (coach_id, seat_no),
    CONSTRAINT chk_seat_no CHECK (seat_no > 0)
);

CREATE TABLE SCHEDULE (
    schedule_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    train_no       CHAR(5) NOT NULL,
    journey_date   DATE    NOT NULL,
    run_status     VARCHAR(10) NOT NULL DEFAULT 'SCHEDULED',
    chart_prepared INTEGER NOT NULL DEFAULT 0 CHECK (chart_prepared IN (0,1)),
    CONSTRAINT fk_sched_train FOREIGN KEY (train_no) REFERENCES TRAIN(train_no)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_run_status CHECK (run_status IN ('SCHEDULED','RUNNING','COMPLETED','CANCELLED')),
    CONSTRAINT uq_schedule UNIQUE (train_no, journey_date)
);

CREATE TABLE AVAILABILITY (
    schedule_id     INTEGER    NOT NULL,
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
);

CREATE TABLE STAFF (
    staff_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    staff_name   VARCHAR(60) NOT NULL,
    role         VARCHAR(6)  NOT NULL,
    station_code CHAR(5),
    phone        CHAR(10)    NOT NULL UNIQUE,
    CONSTRAINT fk_staff_station FOREIGN KEY (station_code) REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_staff_role  CHECK (role IN ('CLERK','TTE','ADMIN')),
    CONSTRAINT chk_staff_phone CHECK (phone GLOB '[6-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]')
);

CREATE TABLE USER_ACCOUNT (
    user_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name     VARCHAR(60)  NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,
    phone         CHAR(10)     NOT NULL UNIQUE,
    password_hash CHAR(60)     NOT NULL,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_user_phone CHECK (phone GLOB '[6-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT chk_user_email CHECK (email LIKE '%_@_%._%')
);

CREATE TABLE BOOKING (
    pnr             CHAR(10)   PRIMARY KEY,
    user_id         INTEGER    NOT NULL,
    schedule_id     INTEGER    NOT NULL,
    from_station    CHAR(5)    NOT NULL,
    to_station      CHAR(5)    NOT NULL,
    class_code      VARCHAR(4) NOT NULL,
    quota_code      VARCHAR(4) NOT NULL,
    booked_by_staff INTEGER,
    booking_ts      TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    distance_km     INTEGER    NOT NULL,
    total_fare      DECIMAL(10,2) NOT NULL,
    booking_status  VARCHAR(10) NOT NULL DEFAULT 'WAITLISTED',
    CONSTRAINT fk_bk_user  FOREIGN KEY (user_id)      REFERENCES USER_ACCOUNT(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_sched FOREIGN KEY (schedule_id)  REFERENCES SCHEDULE(schedule_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_from  FOREIGN KEY (from_station) REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_to    FOREIGN KEY (to_station)   REFERENCES STATION(station_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_class FOREIGN KEY (class_code)   REFERENCES TRAVEL_CLASS(class_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_quota FOREIGN KEY (quota_code)   REFERENCES QUOTA(quota_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bk_staff FOREIGN KEY (booked_by_staff) REFERENCES STAFF(staff_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_bk_status   CHECK (booking_status IN
        ('CONFIRMED','RAC','WAITLISTED','PARTIAL','CANCELLED')),
    CONSTRAINT chk_bk_stations CHECK (from_station <> to_station),
    CONSTRAINT chk_bk_fare     CHECK (total_fare >= 0),
    CONSTRAINT chk_bk_dist     CHECK (distance_km > 0),
    CONSTRAINT chk_pnr_fmt     CHECK (pnr GLOB '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]')
);

CREATE TABLE TICKET_PASSENGER (
    passenger_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    pnr            CHAR(10)    NOT NULL,
    passenger_name VARCHAR(60) NOT NULL,
    age            SMALLINT    NOT NULL,
    gender         CHAR(1)     NOT NULL,
    berth_pref     VARCHAR(12) NOT NULL DEFAULT 'NONE',
    seat_id        INTEGER,
    current_status VARCHAR(3)  NOT NULL DEFAULT 'WL',
    status_number  SMALLINT,
    CONSTRAINT fk_tp_pnr  FOREIGN KEY (pnr)     REFERENCES BOOKING(pnr)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_tp_seat FOREIGN KEY (seat_id) REFERENCES SEAT(seat_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT uq_tp_name    UNIQUE (pnr, passenger_name),
    CONSTRAINT chk_tp_gender CHECK (gender IN ('M','F','O')),
    CONSTRAINT chk_tp_berth  CHECK (berth_pref IN
        ('LOWER','MIDDLE','UPPER','SIDE_LOWER','SIDE_UPPER','NONE')),
    CONSTRAINT chk_tp_cs     CHECK (current_status IN ('CNF','RAC','WL','CAN')),
    CONSTRAINT chk_tp_age    CHECK (age BETWEEN 0 AND 120),
    CONSTRAINT chk_tp_status CHECK (
        (current_status = 'CNF' AND seat_id IS NOT NULL) OR current_status <> 'CNF')
);

CREATE TABLE WAITLIST (
    waitlist_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    schedule_id  INTEGER    NOT NULL,
    class_code   VARCHAR(4) NOT NULL,
    quota_code   VARCHAR(4) NOT NULL,
    pnr          CHAR(10)   NOT NULL,
    passenger_id INTEGER    NOT NULL,
    queue_type   VARCHAR(3) NOT NULL,
    position     SMALLINT   NOT NULL,
    enqueued_at  TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active    INTEGER    NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
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
    CONSTRAINT chk_wl_queue    CHECK (queue_type IN ('RAC','WL')),
    CONSTRAINT uq_wl_passenger UNIQUE (passenger_id),
    CONSTRAINT uq_wl_position  UNIQUE (schedule_id, class_code, quota_code, queue_type, position),
    CONSTRAINT chk_wl_pos CHECK (position > 0)
);

CREATE TABLE FARE_RULE (
    rule_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    class_code      VARCHAR(4) NOT NULL,
    quota_code      VARCHAR(4) NOT NULL,
    train_type      VARCHAR(15) NOT NULL,
    base_fare       DECIMAL(8,2) NOT NULL,
    rate_per_km     DECIMAL(6,3) NOT NULL,
    reservation_chg DECIMAL(6,2) NOT NULL DEFAULT 0.00,
    effective_from  DATE NOT NULL,
    effective_to    DATE,
    CONSTRAINT fk_fr_class FOREIGN KEY (class_code) REFERENCES TRAVEL_CLASS(class_code)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_fr_quota FOREIGN KEY (quota_code) REFERENCES QUOTA(quota_code)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_fr_type CHECK (train_type IN
        ('EXPRESS','SUPERFAST','RAJDHANI','SHATABDI','PASSENGER','VANDE_BHARAT')),
    CONSTRAINT uq_fare UNIQUE (class_code, quota_code, train_type, effective_from),
    CONSTRAINT chk_fare_pos    CHECK (base_fare >= 0 AND rate_per_km >= 0),
    CONSTRAINT chk_fare_period CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE TABLE PAYMENT (
    payment_id INTEGER PRIMARY KEY AUTOINCREMENT,
    pnr        CHAR(10)      NOT NULL,
    amount     DECIMAL(10,2) NOT NULL,
    mode       VARCHAR(10)   NOT NULL,
    txn_ref    VARCHAR(40)   NOT NULL UNIQUE,
    pay_status VARCHAR(8)    NOT NULL DEFAULT 'PENDING',
    paid_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pay_pnr FOREIGN KEY (pnr) REFERENCES BOOKING(pnr)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_pay_mode   CHECK (mode IN ('UPI','CARD','NETBANKING','WALLET','CASH')),
    CONSTRAINT chk_pay_status CHECK (pay_status IN ('SUCCESS','FAILED','PENDING','REFUNDED')),
    CONSTRAINT chk_pay_amt    CHECK (amount > 0)
);

CREATE TABLE CANCELLATION (
    cancel_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    pnr              CHAR(10)  NOT NULL,
    passenger_id     INTEGER,
    cancelled_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cancellation_chg DECIMAL(8,2)  NOT NULL DEFAULT 0.00,
    refund_amount    DECIMAL(10,2) NOT NULL,
    reason           VARCHAR(120),
    CONSTRAINT fk_cn_pnr  FOREIGN KEY (pnr)          REFERENCES BOOKING(pnr)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_cn_pass FOREIGN KEY (passenger_id) REFERENCES TICKET_PASSENGER(passenger_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_cn_amt CHECK (refund_amount >= 0 AND cancellation_chg >= 0)
);

CREATE INDEX idx_route_station ON ROUTE (station_code, train_no);
CREATE INDEX idx_sched_date    ON SCHEDULE (journey_date, train_no);
CREATE INDEX idx_booking_user  ON BOOKING (user_id, booking_ts);
CREATE INDEX idx_booking_sched ON BOOKING (schedule_id, class_code, booking_status);
CREATE INDEX idx_tp_status     ON TICKET_PASSENGER (pnr, current_status);
CREATE INDEX idx_wl_queue      ON WAITLIST (schedule_id, class_code, quota_code, queue_type, is_active, position);
CREATE INDEX idx_pay_status    ON PAYMENT (pay_status, paid_at);
CREATE INDEX idx_coach_train   ON COACH (train_no, class_code);
