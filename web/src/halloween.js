// One-off Halloween weekend, with explicit Perth offsets (independent of device timezone).
export const HALLOWEEN_START = Date.parse("2026-10-29T18:53:12+08:00");
export const HALLOWEEN_END = Date.parse("2026-11-02T00:00:00+08:00");

export function isHalloweenActive(now = Date.now()) {
  return now >= HALLOWEEN_START && now < HALLOWEEN_END;
}
