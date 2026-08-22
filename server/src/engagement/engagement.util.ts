// Small date-key helpers for dedupe keys. UTC-based — good enough for
// "once per day"/"once per week" gating at scale (the send-window already
// localizes when a push goes out).

/** "YYYY-MM-DD" in UTC. */
export function ymdKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** "YYYY-Www" ISO week key in UTC, e.g. "2026-W25". */
export function isoWeekKey(date: Date): string {
  const d = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
  // ISO: Thursday determines the week-year.
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(
    ((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7,
  );
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}
