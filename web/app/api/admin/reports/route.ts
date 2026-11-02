import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { query } from "@/lib/db";
import { route } from "@/lib/errors";
import { redisStats, redisUp, trendingRoutes } from "@/lib/redis";

export const GET = route(async () => {
  await requireRole("ADMIN");

  const [totals] = await query(
    `SELECT (SELECT COUNT(*) FROM BOOKING) AS bookings,
            (SELECT COUNT(*) FROM CANCELLATION) AS cancellations,
            (SELECT COUNT(*) FROM WAITLIST WHERE is_active) AS queued,
            (SELECT COALESCE(SUM(net_revenue), 0) FROM v_revenue) AS net_revenue`,
  );
  const occupancy = await query(
    `SELECT class_code, SUM(total_seats) AS seats, SUM(seats_booked) AS booked,
            ROUND(100 * SUM(seats_booked) / SUM(total_seats), 1) AS pct
       FROM v_occupancy
      WHERE seats_booked > 0
      GROUP BY class_code
      ORDER BY pct DESC`,
  );
  const revenue = await query(
    `SELECT month, SUM(collected) AS collected, SUM(refunded) AS refunded, SUM(net_revenue) AS net
       FROM v_revenue GROUP BY month ORDER BY month DESC LIMIT 12`,
  );
  // CTE plus a window function: the best routes across all months.
  const topRoutes = await query(
    `WITH route_total AS (
        SELECT b.from_station, b.to_station, SUM(p.amount) AS revenue, COUNT(DISTINCT b.pnr) AS bookings
          FROM PAYMENT p JOIN BOOKING b ON b.pnr = p.pnr
         WHERE p.pay_status = 'SUCCESS'
         GROUP BY b.from_station, b.to_station
     )
     SELECT *, RANK() OVER (ORDER BY revenue DESC) AS route_rank
       FROM route_total ORDER BY route_rank LIMIT 5`,
  );
  const fullest = await query(
    `SELECT schedule_id, train_no, train_name, journey_date, class_code, total_seats, seats_booked, waitlisted
       FROM v_occupancy
      WHERE journey_date >= CURDATE() AND (seats_booked > 0 OR waitlisted > 0)
      ORDER BY waitlisted DESC, seats_booked DESC LIMIT 8`,
  );

  return NextResponse.json({
    totals, occupancy, revenue, topRoutes, fullest,
    redis: { up: await redisUp(), stats: await redisStats(), trending: await trendingRoutes() },
  });
});
