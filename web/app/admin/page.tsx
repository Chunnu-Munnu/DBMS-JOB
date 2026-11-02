"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import { api } from "@/lib/api";

type Reports = {
  totals: { bookings: number; cancellations: number; queued: number; net_revenue: number };
  occupancy: { class_code: string; seats: number; booked: number; pct: number }[];
  revenue: { month: string; collected: number; refunded: number; net: number }[];
  topRoutes: { from_station: string; to_station: string; revenue: number; bookings: number; route_rank: number }[];
  fullest: { schedule_id: number; train_no: string; train_name: string; journey_date: string; class_code: string; total_seats: number; seats_booked: number; waitlisted: number }[];
  redis: { up: boolean; stats: { keys: number; memory: string } | null; trending: { route: string; searches: number }[] };
};
type Schedules = {
  trains: { train_no: string; train_name: string; runs_on: string }[];
  empty: { schedule_id: number; train_no: string; journey_date: string }[];
};
type Fare = {
  rule_id: number; class_code: string; quota_code: string; train_type: string; base_fare: number;
  rate_per_km: number; reservation_chg: number; effective_from: string; effective_to: string | null;
};

const rupees = (n: number) => `₹${Number(n).toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;

export default function AdminPage() {
  const [data, setData] = useState<Reports | null>(null);
  const [sched, setSched] = useState<Schedules | null>(null);
  const [fares, setFares] = useState<Fare[]>([]);
  const [error, setError] = useState("");
  const [note, setNote] = useState("");
  const [trainNo, setTrainNo] = useState("12627");
  const [date, setDate] = useState("");
  const [fare, setFare] = useState({
    classCode: "SL", quotaCode: "GN", trainType: "EXPRESS", baseFare: "70", ratePerKm: "0.5", reservationChg: "20", from: "",
  });

  const load = useCallback(() => {
    api<Reports>("/api/admin/reports").then(setData).catch((e) => setError(e.message));
    api<Schedules>("/api/admin/schedules").then(setSched).catch(() => {});
    api<Fare[]>("/api/admin/fares").then(setFares).catch(() => {});
  }, []);
  useEffect(load, [load]);

  async function run(work: () => Promise<unknown>, done: string) {
    setError("");
    setNote("");
    try {
      await work();
      setNote(done);
      load();
    } catch (err) {
      setError((err as Error).message);
    }
  }

  const addSchedule = (e: FormEvent) => {
    e.preventDefault();
    run(() => api("/api/admin/schedules", { trainNo, date }), `Train ${trainNo} opened for ${date}`);
  };
  const addFare = (e: FormEvent) => {
    e.preventDefault();
    run(() => api("/api/admin/fares", fare), "New fare rule saved; the previous rule was closed, not edited");
  };
  const removeSchedule = (id: number) =>
    run(async () => {
      const res = await fetch(`/api/admin/schedules?id=${id}`, { method: "DELETE" });
      if (!res.ok) throw new Error((await res.json()).error);
    }, `Schedule ${id} deleted`);

  if (error && !data) return <p className="error">{error}</p>;
  if (!data) return <p className="muted">Loading...</p>;

  return (
    <>
      <h1>Admin dashboard</h1>
      <div className="stats">
        <div className="card stat"><strong>{data.totals.bookings}</strong>Bookings</div>
        <div className="card stat"><strong>{data.totals.cancellations}</strong>Cancellations</div>
        <div className="card stat"><strong>{data.totals.queued}</strong>In RAC or waitlist</div>
        <div className="card stat"><strong>{rupees(data.totals.net_revenue)}</strong>Net revenue</div>
      </div>

      {error && <p className="error">{error}</p>}
      {note && <p className="ok">{note}</p>}

      <h2>Occupancy by class</h2>
      <div className="card scroll">
        <table>
          <thead><tr><th>Class</th><th>Seats</th><th>Booked</th><th>Occupancy</th></tr></thead>
          <tbody>
            {data.occupancy.map((o) => (
              <tr key={o.class_code}>
                <td>{o.class_code}</td><td>{o.seats}</td><td>{o.booked}</td>
                <td><div className="bar"><i style={{ width: `${Math.min(o.pct, 100)}%` }} /></div>{o.pct}%</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>Monthly revenue</h2>
      <div className="card scroll">
        <table>
          <thead><tr><th>Month</th><th>Collected</th><th>Refunded</th><th>Net</th></tr></thead>
          <tbody>
            {data.revenue.map((r) => (
              <tr key={r.month}><td>{r.month}</td><td>{rupees(r.collected)}</td><td>{rupees(r.refunded)}</td><td>{rupees(r.net)}</td></tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>Top-earning routes</h2>
      <div className="card scroll">
        <table>
          <thead><tr><th>Rank</th><th>Route</th><th>Bookings</th><th>Revenue</th></tr></thead>
          <tbody>
            {data.topRoutes.map((r) => (
              <tr key={r.from_station + r.to_station}>
                <td>{r.route_rank}</td><td>{r.from_station} to {r.to_station}</td><td>{r.bookings}</td><td>{rupees(r.revenue)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>Busiest upcoming runs</h2>
      <div className="card scroll">
        <table>
          <thead><tr><th>Train</th><th>Date</th><th>Class</th><th>Booked</th><th>Waitlisted</th></tr></thead>
          <tbody>
            {data.fullest.map((f) => (
              <tr key={`${f.schedule_id}${f.class_code}`}>
                <td>{f.train_no} {f.train_name}</td><td>{f.journey_date}</td><td>{f.class_code}</td>
                <td>{f.seats_booked} of {f.total_seats}</td><td>{f.waitlisted}</td>
              </tr>
            ))}
            {data.fullest.length === 0 && <tr><td colSpan={5} className="muted">No upcoming bookings yet.</td></tr>}
          </tbody>
        </table>
      </div>

      <h2>Redis</h2>
      <div className="card">
        <p>
          <span className={`badge ${data.redis.up ? "CNF" : "CAN"}`}>{data.redis.up ? "Connected" : "Down: running on MySQL only"}</span>
          {data.redis.stats && <span className="muted"> {data.redis.stats.keys} keys, {data.redis.stats.memory} memory</span>}
        </p>
        <p className="muted">
          Most searched routes:{" "}
          {data.redis.trending.map((t) => `${t.route} (${t.searches})`).join(", ") || "none yet"}
        </p>
        <button className="secondary" onClick={() => run(() => api("/api/admin/redis", {}), "Live queues rebuilt from MySQL")}>
          Rebuild live queues from MySQL
        </button>
      </div>

      <h2>Open a train for a date</h2>
      <form className="card row" onSubmit={addSchedule}>
        <label>Train
          <select value={trainNo} onChange={(e) => setTrainNo(e.target.value)}>
            {sched?.trains.map((t) => <option key={t.train_no} value={t.train_no}>{t.train_no} {t.train_name} ({t.runs_on})</option>)}
          </select>
        </label>
        <label>Date<input type="date" value={date} onChange={(e) => setDate(e.target.value)} required /></label>
        <button>Open</button>
      </form>
      <div className="card scroll">
        <p className="muted">Runs with no bookings can be withdrawn. Runs with bookings are protected by a foreign key.</p>
        <table>
          <tbody>
            {sched?.empty.map((s) => (
              <tr key={s.schedule_id}>
                <td>{s.train_no}</td><td>{s.journey_date}</td>
                <td><button className="secondary" onClick={() => removeSchedule(s.schedule_id)}>Delete</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>Change a fare</h2>
      <form className="card" onSubmit={addFare}>
        <div className="row">
          {(["classCode", "quotaCode", "trainType", "baseFare", "ratePerKm", "reservationChg"] as const).map((key) => (
            <label key={key}>{key}
              <input value={fare[key]} onChange={(e) => setFare({ ...fare, [key]: e.target.value })} required />
            </label>
          ))}
          <label>Effective from
            <input type="date" value={fare.from} onChange={(e) => setFare({ ...fare, from: e.target.value })} required />
          </label>
          <button>Save</button>
        </div>
      </form>
      <div className="card scroll">
        <table>
          <thead><tr><th>Class</th><th>Quota</th><th>Type</th><th>Base</th><th>Per km</th><th>From</th><th>To</th></tr></thead>
          <tbody>
            {fares.map((f) => (
              <tr key={f.rule_id}>
                <td>{f.class_code}</td><td>{f.quota_code}</td><td>{f.train_type}</td><td>{f.base_fare}</td>
                <td>{f.rate_per_km}</td><td>{f.effective_from}</td><td>{f.effective_to ?? "current"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
