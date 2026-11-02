-- ============================================================
-- The six key queries, plus examples of each SQL feature the project uses.
-- Read-only: safe to run on the seeded database.
-- ============================================================
USE railway_db;
SET @journey = CURDATE() + INTERVAL 20 DAY;

-- Q1. Availability by route and date. Self-join on ROUTE; seq_no enforces direction.
SELECT t.train_no, t.train_name, a.class_code, a.quota_code, a.seats_available, a.rac_available,
       a.waitlist_count, r2.dist_from_src - r1.dist_from_src AS km,
       fn_compute_fare(a.class_code, a.quota_code, t.train_type, r2.dist_from_src - r1.dist_from_src, s.journey_date) AS fare
  FROM ROUTE r1
  JOIN ROUTE r2       ON r2.train_no = r1.train_no AND r1.seq_no < r2.seq_no
  JOIN TRAIN t        ON t.train_no = r1.train_no
  JOIN SCHEDULE s     ON s.train_no = t.train_no AND s.journey_date = @journey - INTERVAL r1.day_offset DAY
  JOIN AVAILABILITY a ON a.schedule_id = s.schedule_id
 WHERE r1.station_code = 'SBC' AND r2.station_code = 'NDLS'
 ORDER BY t.train_no, a.class_code, a.quota_code;

-- Q2. Complete PNR status, through the view.
SELECT pnr, train_name, journey_date, passenger_name, current_status, coach_code, seat_no, current_position
  FROM v_pnr_status
 WHERE pnr = (SELECT pnr FROM BOOKING ORDER BY booking_ts DESC LIMIT 1);

-- Q3. Who gets the next freed seat: earliest RAC, then earliest WL.
SELECT w.queue_type, w.position, tp.passenger_name, w.pnr, w.enqueued_at
  FROM WAITLIST w
  JOIN TICKET_PASSENGER tp ON tp.passenger_id = w.passenger_id
 WHERE w.is_active
 ORDER BY w.schedule_id, w.class_code, w.quota_code, w.queue_type, w.position
 LIMIT 5;

-- Q4. Class-wise occupancy, with a HAVING filter on the aggregate.
SELECT class_code, SUM(total_seats) AS seats, SUM(seats_booked) AS booked,
       ROUND(100 * SUM(seats_booked) / SUM(total_seats), 1) AS occupancy_pct
  FROM v_occupancy
 WHERE journey_date < CURDATE()
 GROUP BY class_code
HAVING SUM(seats_booked) > 0
 ORDER BY occupancy_pct DESC;

-- Q5a. Monthly revenue.
SELECT month, SUM(collected) AS collected, SUM(refunded) AS refunded, SUM(net_revenue) AS net
  FROM v_revenue GROUP BY month ORDER BY month;

-- Q5b. Top-earning routes. CTE plus a window function: rank inside each month.
WITH route_month AS (
    SELECT DATE_FORMAT(p.paid_at, '%Y-%m') AS month, b.from_station, b.to_station, SUM(p.amount) AS revenue
      FROM PAYMENT p JOIN BOOKING b ON b.pnr = p.pnr
     WHERE p.pay_status = 'SUCCESS'
     GROUP BY month, b.from_station, b.to_station
)
SELECT * FROM (
    SELECT rm.*, RANK() OVER (PARTITION BY month ORDER BY revenue DESC) AS route_rank
      FROM route_month rm
) ranked
 WHERE route_rank <= 3
 ORDER BY month, route_rank;

-- Q6. A passenger's bookings and cancellations in the last year.
SELECT pnr, train_name, journey_date, booking_status, total_fare, refunded
  FROM v_passenger_history
 WHERE user_id = 1 AND booking_ts >= NOW() - INTERVAL 1 YEAR
 ORDER BY booking_ts DESC
 LIMIT 10;

-- Correlated subquery: the inner SELECT refers to t.train_no, so it runs once per train.
SELECT t.train_no, t.train_name,
       (SELECT SUM(b.total_fare) FROM BOOKING b JOIN SCHEDULE s ON s.schedule_id = b.schedule_id
         WHERE s.train_no = t.train_no) AS earned
  FROM TRAIN t
 WHERE (SELECT SUM(b.total_fare) FROM BOOKING b JOIN SCHEDULE s ON s.schedule_id = b.schedule_id
         WHERE s.train_no = t.train_no)
       > (SELECT AVG(train_total) FROM (
              SELECT SUM(b.total_fare) AS train_total
                FROM BOOKING b JOIN SCHEDULE s ON s.schedule_id = b.schedule_id
               GROUP BY s.train_no) totals);

-- NOT EXISTS (correlated): passengers who have never cancelled anything.
SELECT u.full_name FROM USER_ACCOUNT u
 WHERE NOT EXISTS (SELECT 1 FROM BOOKING b JOIN CANCELLATION c ON c.pnr = b.pnr WHERE b.user_id = u.user_id);

-- IN with an uncorrelated subquery: stations served by a Superfast train.
SELECT station_name FROM STATION
 WHERE station_code IN (SELECT r.station_code FROM ROUTE r JOIN TRAIN t ON t.train_no = r.train_no
                         WHERE t.train_type = 'SUPERFAST');

-- Subquery in FROM: busiest class by average passengers per booking.
SELECT class_code, AVG(pax) AS avg_passengers
  FROM (SELECT b.class_code, b.pnr, COUNT(*) AS pax
          FROM BOOKING b JOIN TICKET_PASSENGER tp ON tp.pnr = b.pnr
         GROUP BY b.class_code, b.pnr) per_booking
 GROUP BY class_code;

-- LEFT OUTER JOIN: every train, including any with no schedule.
SELECT t.train_no, COUNT(s.schedule_id) AS runs
  FROM TRAIN t LEFT JOIN SCHEDULE s ON s.train_no = t.train_no
 GROUP BY t.train_no;

-- Set operation: everyone who can log in.
SELECT email, 'PASSENGER' AS role FROM USER_ACCOUNT
 UNION ALL
SELECT email, role FROM STAFF;

-- Window function with LAG: month-on-month revenue change.
SELECT month, net, net - LAG(net) OVER (ORDER BY month) AS change_from_last_month
  FROM (SELECT month, SUM(net_revenue) AS net FROM v_revenue GROUP BY month) m;

-- Full-text search in boolean mode.
SELECT station_code, station_name, MATCH(station_name, city) AGAINST ('beng*' IN BOOLEAN MODE) AS relevance
  FROM STATION
 WHERE MATCH(station_name, city) AGAINST ('beng*' IN BOOLEAN MODE);

-- Index use: type is ref on a composite index that starts with these columns, not a full scan.
EXPLAIN SELECT waitlist_id FROM WAITLIST
 WHERE schedule_id = 1 AND class_code = '3A' AND quota_code = 'GN' AND queue_type = 'WL' AND is_active
 ORDER BY position LIMIT 1;
