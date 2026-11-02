-- ============================================================
-- v_pnr_status: what the PNR page shows. current_position is a correlated
-- subquery, so it is always the live rank among passengers still queued.
-- ============================================================
USE railway_db;

CREATE OR REPLACE VIEW v_pnr_status AS
SELECT b.pnr, b.booking_status, b.booking_ts, b.total_fare, b.distance_km, b.user_id,
       b.class_code, b.quota_code,
       t.train_no, t.train_name, sc.journey_date, sc.run_status, sc.schedule_id,
       b.from_station, sf.station_name AS from_name,
       b.to_station,   st.station_name AS to_name,
       tp.passenger_id, tp.passenger_name, tp.age, tp.gender, tp.current_status,
       tp.status_number AS booking_position,
       c.coach_code, s.seat_no, s.berth_type,
       (SELECT COUNT(*)
          FROM WAITLIST w2
         WHERE w2.schedule_id = w.schedule_id AND w2.class_code = w.class_code
           AND w2.quota_code = w.quota_code AND w2.queue_type = w.queue_type
           AND w2.is_active AND w2.position <= w.position) AS current_position
  FROM BOOKING b
  JOIN SCHEDULE sc         ON sc.schedule_id = b.schedule_id
  JOIN TRAIN t             ON t.train_no = sc.train_no
  JOIN STATION sf          ON sf.station_code = b.from_station
  JOIN STATION st          ON st.station_code = b.to_station
  JOIN TICKET_PASSENGER tp ON tp.pnr = b.pnr
  LEFT JOIN SEAT s         ON s.seat_id = tp.seat_id
  LEFT JOIN COACH c        ON c.coach_id = s.coach_id
  LEFT JOIN WAITLIST w     ON w.passenger_id = tp.passenger_id AND w.is_active;
