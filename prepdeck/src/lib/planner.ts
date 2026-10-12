import { addDays, dayKey, daysBetween } from './dates';
import type { Course, PlanDay, PlanTask, StudySession, Topic } from './types';

export interface PlanInput {
  courses: Course[];
  sessions: StudySession[];
  mocksDone: { courseId: string; date: string }[];
  today: string; // YYYY-MM-DD
  sessionsPerDay: number;
  reviewDue: number; // questions due for spaced review today
}

export interface Plan {
  days: PlanDay[];
  /** Revision sessions that could not fit before their exam. */
  unscheduled: number;
}

/** How many study sessions a topic needs in total, from confidence and course difficulty. */
export function sessionsNeeded(topic: Topic, course: Course): number {
  const base = 4 - topic.confidence; // shaky 3, okay 2, solid 1
  return Math.min(4, base + (course.difficulty === 3 ? 1 : 0));
}

const examDay = (c: Course) => dayKey(new Date(c.examAt));

/**
 * Builds a day-by-day revision plan from today until the last exam.
 * Topics closer to their exam, weaker, and in harder courses come first; the
 * same topic is not repeated on back-to-back days if anything else is
 * available, and each course gets a timed mock exam the day before its paper.
 * The plan is rebuilt from scratch whenever anything changes, so missed work
 * simply rolls forward.
 */
export function buildPlan(input: PlanInput): Plan {
  const { courses, sessions, mocksDone, today } = input;
  const slots = Math.max(1, Math.round(input.sessionsPerDay));
  const upcoming = courses.filter(c => daysBetween(today, examDay(c)) >= 1);

  // Sessions already done before today count against what is still needed.
  // Today's ticks are left out so today's list stays stable as items are ticked.
  const remaining = new Map<string, number>();
  for (const c of upcoming) {
    for (const t of c.topics) {
      const done = sessions.filter(s => s.topicId === t.id && s.date < today).length;
      remaining.set(t.id, Math.max(0, sessionsNeeded(t, c) - done));
    }
  }

  const lastExam = upcoming.reduce((m, c) => (examDay(c) > m ? examDay(c) : m), today);
  const days: PlanDay[] = [];
  let yesterday = new Set<string>();

  for (let d = today; d < lastExam; d = addDays(d, 1)) {
    const tasks: PlanTask[] = [];

    if (d === today && input.reviewDue > 0) {
      tasks.push({ kind: 'review', key: `${d}:review`, count: input.reviewDue, label: `Review ${input.reviewDue} missed question${input.reviewDue === 1 ? '' : 's'}` });
    }

    for (const c of upcoming) {
      const eve = addDays(examDay(c), -1);
      const mockedRecently = mocksDone.some(m => m.courseId === c.id && m.date < today && daysBetween(m.date, examDay(c)) <= 3);
      if (d === eve && !mockedRecently) {
        tasks.push({ kind: 'mock', key: `${d}:mock:${c.id}`, courseId: c.id, label: `Timed mock exam: ${c.code}` });
      }
    }

    const open = Math.max(1, slots - tasks.length);
    const candidates: { course: Course; topic: Topic; score: number }[] = [];
    for (const c of upcoming) {
      const left = daysBetween(d, examDay(c));
      if (left < 1) continue;
      for (const t of c.topics) {
        const r = remaining.get(t.id) ?? 0;
        if (r <= 0) continue;
        const weight = (4 - t.confidence) * (1 + 0.25 * (c.difficulty - 1));
        // Urgency: how many sessions per remaining day this topic still needs.
        let score = weight * (r / left) + weight / (left + 1);
        if (yesterday.has(t.id)) score *= 0.3;
        candidates.push({ course: c, topic: t, score });
      }
    }
    candidates.sort((a, b) => b.score - a.score || a.topic.name.localeCompare(b.topic.name));

    const picked = new Set<string>();
    for (const cand of candidates.slice(0, open)) {
      picked.add(cand.topic.id);
      remaining.set(cand.topic.id, (remaining.get(cand.topic.id) ?? 0) - 1);
      tasks.push({
        kind: 'topic',
        key: `${d}:topic:${cand.topic.id}`,
        courseId: cand.course.id,
        topicId: cand.topic.id,
        label: cand.topic.name,
      });
    }
    yesterday = picked;
    days.push({ date: d, tasks });
  }

  let unscheduled = 0;
  for (const r of remaining.values()) unscheduled += Math.max(0, r);
  return { days, unscheduled };
}
