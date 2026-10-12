import { addDays } from './dates';
import type { CardState, Question } from './types';

/** Days until the next review for each Leitner box. Box 5 counts as mastered. */
export const INTERVALS = [1, 2, 4, 7, 14];
export const MASTERED = 5;

export function newCard(today: string): CardState {
  return { box: 0, due: today, seen: 0, correct: 0 };
}

/** Moves a card up a box when answered correctly, or back to the start when missed. */
export function review(card: CardState | undefined, correct: boolean, today: string): CardState {
  const c = card ?? newCard(today);
  if (correct) {
    const box = Math.min(MASTERED, c.box + 1);
    return { ...c, box, seen: c.seen + 1, correct: c.correct + 1, due: addDays(today, INTERVALS[Math.min(box, INTERVALS.length) - 1]) };
  }
  return { ...c, box: 0, seen: c.seen + 1, due: addDays(today, 1), lastWrong: today };
}

/** Questions the student has missed before and that are due again. */
export function dueForReview(questions: Question[], cards: Record<string, CardState>, today: string, courseId?: string): Question[] {
  return questions.filter(q => {
    if (courseId && q.courseId !== courseId) return false;
    const c = cards[q.id];
    return !!c && !!c.lastWrong && c.box < MASTERED && c.due <= today;
  });
}

/** Fisher–Yates shuffle with an injectable random source (for tests). */
export function shuffle<T>(items: T[], rand: () => number = Math.random): T[] {
  const a = items.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/** Picks practice questions, weakest first: unseen and low-box questions before mastered ones. */
export function pickPractice(questions: Question[], cards: Record<string, CardState>, count: number, rand: () => number = Math.random): Question[] {
  const weight = (q: Question) => {
    const c = cards[q.id];
    return c ? c.box : -1;
  };
  return shuffle(questions, rand)
    .sort((a, b) => weight(a) - weight(b))
    .slice(0, count);
}
