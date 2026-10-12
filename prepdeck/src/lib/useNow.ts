import { useEffect, useState } from 'react';

/** Current time in ms, refreshed every `everyMs` so "upcoming vs done" stays correct while the app is open. */
export function useNow(everyMs = 60_000): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), everyMs);
    return () => clearInterval(t);
  }, [everyMs]);
  return now;
}
