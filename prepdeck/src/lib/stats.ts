import { addDays, dayKey } from './dates';
import type { AppState } from './types';

/** Days on which the student ticked a session or finished a quiz. */
export function activeDays(state: Pick<AppState, 'sessions' | 'attempts'>): Set<string> {
  return new Set([...state.sessions.map(x => x.date), ...state.attempts.map(a => dayKey(new Date(a.date)))]);
}

/** Consecutive active days ending today (or yesterday, so the streak survives until tonight). */
export function streak(state: Pick<AppState, 'sessions' | 'attempts'>, today = dayKey()): number {
  const active = activeDays(state);
  let n = 0;
  let d = active.has(today) ? today : addDays(today, -1);
  while (active.has(d)) {
    n++;
    d = addDays(d, -1);
  }
  return n;
}
