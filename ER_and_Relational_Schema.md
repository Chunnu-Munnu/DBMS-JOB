# Railway Reservation & PNR Management System
### Week 4 — ER Diagram, Relational Schema and DDL

---

## 1. ER Diagram

```mermaid
erDiagram
    STATION ||--o{ ROUTE : "is a stop on"
    STATION ||--o{ TRAIN : "originates/terminates"
    STATION ||--o{ STAFF : "posted at"
    TRAIN   ||--|{ ROUTE : "has ordered stops"
    TRAIN   ||--|{ COACH : "is composed of"
    TRAIN   ||--o{ SCHEDULE : "runs on date"
    TRAVEL_CLASS ||--o{ COACH : "classifies"
    COACH   ||--|{ SEAT : "contains"
    SCHEDULE ||--|{ AVAILABILITY : "tracks"
    TRAVEL_CLASS ||--o{ AVAILABILITY : "per class"
    QUOTA   ||--o{ AVAILABILITY : "per quota"
    USER_ACCOUNT ||--o{ BOOKING : "makes"
    STAFF   ||--o{ BOOKING : "books at counter"
    SCHEDULE ||--o{ BOOKING : "is booked on"
    TRAVEL_CLASS ||--o{ BOOKING : "in class"
    QUOTA   ||--o{ BOOKING : "under quota"
    BOOKING ||--|{ TICKET_PASSENGER : "covers"
    SEAT    ||--o| TICKET_PASSENGER : "allotted to"
    BOOKING ||--o{ WAITLIST : "queued as"
    TICKET_PASSENGER ||--o| WAITLIST : "holds position"
    SCHEDULE ||--o{ WAITLIST : "queue for"
    TRAVEL_CLASS ||--o{ FARE_RULE : "priced by"
    QUOTA   ||--o{ FARE_RULE : "priced by"
    BOOKING ||--|{ PAYMENT : "paid via"
    BOOKING ||--o{ CANCELLATION : "cancelled by"
    TICKET_PASSENGER ||--o| CANCELLATION : "partial cancel"

    STATION { CHAR station_code PK
              VARCHAR station_name
              VARCHAR city
              VARCHAR state
              VARCHAR zone }
    TRAIN   { CHAR train_no PK
              VARCHAR train_name
              ENUM train_type
              CHAR source_code FK
              CHAR dest_code FK
              CHAR runs_on
              INT total_distance }
    ROUTE   { CHAR train_no PK_FK
              SMALLINT seq_no PK
              CHAR station_code FK
              TIME arrival_time
              TIME departure_time
              INT dist_from_src
              SMALLINT halt_minutes }
    TRAVEL_CLASS { VARCHAR class_code PK
              VARCHAR class_name
              BOOL is_ac
              BOOL has_berth }
    QUOTA   { VARCHAR quota_code PK
              VARCHAR quota_name
              DECIMAL surcharge_pct }
    COACH   { INT coach_id PK
              CHAR train_no FK
              VARCHAR coach_code
              VARCHAR class_code FK
              SMALLINT total_seats }
    SEAT    { INT seat_id PK
              INT coach_id FK
              SMALLINT seat_no
              ENUM berth_type }
    SCHEDULE { INT schedule_id PK
              CHAR train_no FK
              DATE journey_date
              ENUM run_status
              BOOL chart_prepared }
    AVAILABILITY { INT schedule_id PK_FK
              VARCHAR class_code PK_FK
              VARCHAR quota_code PK_FK
              SMALLINT total_seats
              SMALLINT seats_available
              SMALLINT rac_available
              SMALLINT waitlist_count }
    USER_ACCOUNT { INT user_id PK
              VARCHAR full_name
              VARCHAR email
              CHAR phone
              CHAR password_hash }
    STAFF   { INT staff_id PK
              VARCHAR staff_name
              ENUM role
              CHAR station_code FK
              CHAR phone }
    BOOKING { CHAR pnr PK
              INT user_id FK
              INT schedule_id FK
              CHAR from_station FK
              CHAR to_station FK
              VARCHAR class_code FK
              VARCHAR quota_code FK
              INT booked_by_staff FK
              TIMESTAMP booking_ts
              INT distance_km
              DECIMAL total_fare
              ENUM booking_status }
    TICKET_PASSENGER { INT passenger_id PK
              CHAR pnr FK
              VARCHAR passenger_name
              TINYINT age
              ENUM gender
              ENUM berth_pref
              INT seat_id FK
              ENUM current_status
              SMALLINT status_number }
    WAITLIST { INT waitlist_id PK
              INT schedule_id FK
              VARCHAR class_code FK
              VARCHAR quota_code FK
              CHAR pnr FK
              INT passenger_id FK
              ENUM queue_type
              SMALLINT position
              BOOL is_active }
    FARE_RULE { INT rule_id PK
              VARCHAR class_code FK
              VARCHAR quota_code FK
              ENUM train_type
              DECIMAL base_fare
              DECIMAL rate_per_km
              DECIMAL reservation_chg
              DATE effective_from }
    PAYMENT { INT payment_id PK
              CHAR pnr FK
              DECIMAL amount
              ENUM mode
              VARCHAR txn_ref
              ENUM pay_status }
    CANCELLATION { INT cancel_id PK
              CHAR pnr FK
              INT passenger_id FK
              TIMESTAMP cancelled_at
              DECIMAL cancellation_chg
              DECIMAL refund_amount }
```

### ER design notes

| Construct | Where it appears | Justification |
|---|---|---|
| **Weak entity** | `ROUTE` (identified by `TRAIN` + `seq_no`), `SEAT` (dependent on `COACH`) | A stop has no meaning without its train; a seat has none without its coach. |
| **Recursive / dual role** | `STATION` plays both *source* and *destination* for `TRAIN`, and both *from* and *to* for `BOOKING` | Same entity set, two distinct relationship roles. |
| **Ternary → relationship entity** | `AVAILABILITY` (SCHEDULE × TRAVEL_CLASS × QUOTA) | Seat counts are meaningful only for the combination of all three. |
| **Multivalued attribute → table** | `TICKET_PASSENGER` | One PNR carries up to six passengers. |
| **Aggregation** | `WAITLIST` references the *booking-on-a-schedule* relationship | The queue position is a property of a passenger already related to a schedule. |
| **Total participation** | `COACH`–`SEAT`, `BOOKING`–`TICKET_PASSENGER` | Every coach has seats; every PNR has ≥ 1 passenger. |

---

## 2. Relational Schema

Primary keys are **underlined** (shown here in **bold**); foreign keys are marked *(FK → Table)*.

1. **STATION**(**station_code**, station_name, city, state, zone)

2. **TRAIN**(**train_no**, train_name, train_type, source_code *(FK → STATION)*, dest_code *(FK → STATION)*, runs_on, total_distance)

3. **ROUTE**(**train_no** *(FK → TRAIN)*, **seq_no**, station_code *(FK → STATION)*, arrival_time, departure_time, day_offset, dist_from_src, halt_minutes)

4. **TRAVEL_CLASS**(**class_code**, class_name, is_ac, has_berth)

5. **QUOTA**(**quota_code**, quota_name, surcharge_pct)

6. **COACH**(**coach_id**, train_no *(FK → TRAIN)*, coach_code, class_code *(FK → TRAVEL_CLASS)*, total_seats)

7. **SEAT**(**seat_id**, coach_id *(FK → COACH)*, seat_no, berth_type)

8. **SCHEDULE**(**schedule_id**, train_no *(FK → TRAIN)*, journey_date, run_status, chart_prepared)

9. **AVAILABILITY**(**schedule_id** *(FK → SCHEDULE)*, **class_code** *(FK → TRAVEL_CLASS)*, **quota_code** *(FK → QUOTA)*, total_seats, seats_available, rac_available, waitlist_count)

10. **USER_ACCOUNT**(**user_id**, full_name, email, phone, password_hash, created_at)

11. **STAFF**(**staff_id**, staff_name, role, station_code *(FK → STATION)*, phone)

12. **BOOKING**(**pnr**, user_id *(FK → USER_ACCOUNT)*, schedule_id *(FK → SCHEDULE)*, from_station *(FK → STATION)*, to_station *(FK → STATION)*, class_code *(FK → TRAVEL_CLASS)*, quota_code *(FK → QUOTA)*, booked_by_staff *(FK → STAFF)*, booking_ts, distance_km, total_fare, booking_status)

13. **TICKET_PASSENGER**(**passenger_id**, pnr *(FK → BOOKING)*, passenger_name, age, gender, berth_pref, seat_id *(FK → SEAT)*, current_status, status_number)

14. **WAITLIST**(**waitlist_id**, schedule_id *(FK → SCHEDULE)*, class_code *(FK → TRAVEL_CLASS)*, quota_code *(FK → QUOTA)*, pnr *(FK → BOOKING)*, passenger_id *(FK → TICKET_PASSENGER)*, queue_type, position, enqueued_at, is_active)

15. **FARE_RULE**(**rule_id**, class_code *(FK → TRAVEL_CLASS)*, quota_code *(FK → QUOTA)*, train_type, base_fare, rate_per_km, reservation_chg, effective_from, effective_to)

16. **PAYMENT**(**payment_id**, pnr *(FK → BOOKING)*, amount, mode, txn_ref, pay_status, paid_at)

17. **CANCELLATION**(**cancel_id**, pnr *(FK → BOOKING)*, passenger_id *(FK → TICKET_PASSENGER)*, cancelled_at, cancellation_chg, refund_amount, reason)

### ER → Relational mapping rules applied

- **Strong entities** → one relation each, with the entity key as PK (STATION, TRAIN, TRAVEL_CLASS, QUOTA, USER_ACCOUNT, STAFF).
- **Weak entities** → PK = owner's PK + partial key (`ROUTE(train_no, seq_no)`); `SEAT` uses a surrogate PK with `UNIQUE(coach_id, seat_no)` as its natural key.
- **1:N relationships** → FK placed on the N-side (`COACH.train_no`, `SEAT.coach_id`, `SCHEDULE.train_no`, `BOOKING.user_id`).
- **M:N relationship** → separate relation with the composite PK (`AVAILABILITY` for the SCHEDULE × CLASS × QUOTA ternary; `FARE_RULE` for CLASS × QUOTA × train_type).
- **Multivalued attribute** (passengers on a ticket) → separate relation `TICKET_PASSENGER`.
- **Optional participation** → nullable FKs (`TICKET_PASSENGER.seat_id` is NULL until allotment; `BOOKING.booked_by_staff` is NULL for online bookings; `CANCELLATION.passenger_id` is NULL for a full-PNR cancellation).
- **Normalization**: all relations are in **3NF/BCNF** — every non-key attribute depends on the whole key and nothing but the key. `distance_km` and `total_fare` on BOOKING are deliberate *point-in-time snapshots*, not transitive dependencies, since fare rules change over time.

---

## 3. DDL

- `ddl_mysql.sql` — the submission DDL, MySQL 8.0 / InnoDB.
- `ddl_sqlite.sql` — an equivalent port used to execute and verify the schema locally.

Includes 17 tables, 33 foreign keys, 8 secondary indexes, and CHECK constraints covering
station-pair validity, distance/fare positivity, seat and waitlist bounds, PNR/phone/email formats,
and enumerated status domains.

---

## 4. Execution Result

`python run_ddl.py` builds `railway.db` from the DDL and verifies it.

```
TABLES CREATED: 17          EXPLICIT INDEXES: 8
fk_check  : PASS (no violations)
integrity : ok

CONSTRAINT SMOKE TEST
  duplicate station PK                   rejected: UNIQUE constraint failed: STATION.station_code
  train with source = destination        rejected: CHECK constraint failed: chk_train_ends
  train referencing unknown station      rejected: FOREIGN KEY constraint failed
  invalid train_type value               rejected: CHECK constraint failed: chk_train_type
  negative total_distance                rejected: CHECK constraint failed: chk_train_dist
  malformed runs_on flags                rejected: CHECK constraint failed: chk_runs_on
  bad phone format on USER_ACCOUNT       rejected: CHECK constraint failed: chk_user_phone
  email without @                        rejected: CHECK constraint failed: chk_user_email
  two stops at same seq_no               rejected: UNIQUE constraint failed: ROUTE.train_no, seq_no
```

Per-table column and FK counts:

| Table | Cols | FKs | | Table | Cols | FKs |
|---|---|---|---|---|---|---|
| STATION | 5 | 0 | | BOOKING | 12 | 7 |
| TRAIN | 7 | 2 | | TICKET_PASSENGER | 9 | 2 |
| ROUTE | 8 | 2 | | WAITLIST | 10 | 5 |
| TRAVEL_CLASS | 4 | 0 | | FARE_RULE | 9 | 2 |
| QUOTA | 3 | 0 | | PAYMENT | 7 | 1 |
| COACH | 5 | 2 | | CANCELLATION | 7 | 2 |
| SEAT | 4 | 1 | | STAFF | 5 | 1 |
| SCHEDULE | 5 | 1 | | USER_ACCOUNT | 6 | 0 |
| AVAILABILITY | 7 | 3 | | | | |

---

## 5. Known limitation

One integrity rule is **not** expressible as a table constraint: *the same physical seat must not be
allotted twice on the same schedule*. `TICKET_PASSENGER` holds `seat_id` but not `schedule_id`
(it reaches the schedule through `BOOKING`), so a simple `UNIQUE` cannot express it. This will be
enforced in the DML phase by a `BEFORE INSERT` trigger on `TICKET_PASSENGER`, together with the
Redis seat-lock during the booking window.
