import { useMemo } from 'react';
import { dayKey } from './dates';
import { buildPlan, type Plan } from './planner';
import { dueForReview } from './srs';
import { useStore } from './store';

/** Today's revision plan, rebuilt whenever courses, ticks or settings change. */
export function usePlan(): Plan & { today: string; reviewDue: number } {
  const { state } = useStore();
  const today = dayKey();
  return useMemo(() => {
    const reviewDue = dueForReview(state.questions, state.cards, today).length;
    const plan = buildPlan({
      courses: state.courses,
      sessions: state.sessions,
      mocksDone: state.mocksDone,
      today,
      sessionsPerDay: state.settings.sessionsPerDay,
      reviewDue,
    });
    return { ...plan, today, reviewDue };
  }, [state.courses, state.sessions, state.mocksDone, state.questions, state.cards, state.settings.sessionsPerDay, today]);
}
