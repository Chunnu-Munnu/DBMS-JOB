import { query } from "./db";

export type ClassOption = {
  class_code: string; class_name: string; quota_code: string; seats_available: number;
  rac_available: number; waitlist_count: number; fare: number;
};
export type TrainResult = {
  train_no: string; train_name: string; train_type: string; schedule_id: number;
  departure_time: string; arrival_time: string; day_diff: number; km: number;
  classes: ClassOption[];
};

// ROUTE joined to itself: r1 is where you board, r2 where you get off.
// r1.seq_no < r2.seq_no is what rejects a train running the opposite way.
// The date typed is the boarding date, while SCHEDULE stores the date at origin.
const SEARCH_SQL = `
  SELECT t.train_no, t.train_name, t.train_type, s.schedule_id,
         r1.departure_time, r2.arrival_time,
         r2.day_offset - r1.day_offset AS day_diff,
         r2.dist_from_src - r1.dist_from_src AS km,
         a.class_code, tc.class_name, a.quota_code,
         a.seats_available, a.rac_available, a.waitlist_count,
         fn_compute_fare(a.class_code, a.quota_code, t.train_type,
                         r2.dist_from_src - r1.dist_from_src, s.journey_date) AS fare
    FROM ROUTE r1
    JOIN ROUTE r2         ON r2.train_no = r1.train_no AND r1.seq_no < r2.seq_no
    JOIN TRAIN t          ON t.train_no = r1.train_no
    JOIN SCHEDULE s       ON s.train_no = t.train_no
                         AND s.journey_date = DATE_SUB(?, INTERVAL r1.day_offset DAY)
                         AND s.run_status = 'SCHEDULED'
    JOIN AVAILABILITY a   ON a.schedule_id = s.schedule_id
    JOIN TRAVEL_CLASS tc  ON tc.class_code = a.class_code
   WHERE r1.station_code = ? AND r2.station_code = ?
   ORDER BY r1.departure_time, t.train_no, a.class_code, a.quota_code`;

export async function searchTrains(from: string, to: string, date: string): Promise<TrainResult[]> {
  const rows = await query<TrainResult & ClassOption>(SEARCH_SQL, [date, from, to]);
  const trains = new Map<number, TrainResult>();
  for (const row of rows) {
    if (!trains.has(row.schedule_id)) {
      const { train_no, train_name, train_type, schedule_id, departure_time, arrival_time, day_diff, km } = row;
      trains.set(schedule_id, {
        train_no, train_name, train_type, schedule_id, departure_time, arrival_time, day_diff, km, classes: [],
      });
    }
    const { class_code, class_name, quota_code, seats_available, rac_available, waitlist_count, fare } = row;
    trains.get(row.schedule_id)!.classes.push({
      class_code, class_name, quota_code, seats_available, rac_available, waitlist_count, fare,
    });
  }
  return [...trains.values()];
}
