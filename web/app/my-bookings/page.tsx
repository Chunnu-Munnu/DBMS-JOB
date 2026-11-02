"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

type Row = {
  pnr: string; booking_status: string; total_fare: number; class_code: string; journey_date: string;
  train_no: string; train_name: string; from_station: string; to_station: string; passengers: number; refunded: number;
};

export default function MyBookings() {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    api<Row[]>("/api/bookings").then(setRows).catch((e) => setError(e.message));
  }, []);

  return (
    <>
      <h1>My bookings</h1>
      {error && <p className="error">{error}</p>}
      {rows?.length === 0 && <p className="card">No bookings yet.</p>}
      {rows && rows.length > 0 && (
        <div className="card scroll">
          <table>
            <thead><tr><th>PNR</th><th>Train</th><th>Journey</th><th>Date</th><th>Pax</th><th>Fare</th><th>Refunded</th><th>Status</th></tr></thead>
            <tbody>
              {rows.map((b) => (
                <tr key={b.pnr}>
                  <td><Link href={`/pnr/${b.pnr}`}>{b.pnr}</Link></td>
                  <td>{b.train_no} {b.train_name}</td>
                  <td>{b.from_station} to {b.to_station} ({b.class_code})</td>
                  <td>{b.journey_date}</td>
                  <td>{b.passengers}</td>
                  <td>₹{b.total_fare}</td>
                  <td>{b.refunded > 0 ? `₹${b.refunded}` : "-"}</td>
                  <td><span className={`badge ${b.booking_status}`}>{b.booking_status}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
