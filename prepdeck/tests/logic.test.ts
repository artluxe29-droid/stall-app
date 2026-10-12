/// <reference types="node" />
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addDays, countdown, daysBetween } from '../src/lib/dates';
import { IMPORT_EXAMPLE, parseQuestions } from '../src/lib/importer';
import { buildPlan, sessionsNeeded } from '../src/lib/planner';
import { dueForReview, MASTERED, pickPractice, review } from '../src/lib/srs';
import type { Course, Question } from '../src/lib/types';

const exam = (key: string) => new Date(`${key}T09:00:00`).toISOString();
const course = (id: string, examKey: string, topics: [string, 1 | 2 | 3][], difficulty: 1 | 2 | 3 = 2): Course => ({
  id, code: id.toUpperCase(), title: id, examAt: exam(examKey), difficulty, color: '#000',
  topics: topics.map(([name, confidence]) => ({ id: `${id}-${name}`, name, confidence })),
});

test('date helpers', () => {
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
  assert.equal(daysBetween('2026-11-01', '2026-11-15'), 14);
  const c = countdown(new Date(2026, 0, 2, 3, 4, 5), new Date(2026, 0, 1, 0, 0, 0));
  assert.deepEqual([c.days, c.hours, c.minutes, c.seconds, c.past], [1, 3, 4, 5, false]);
  assert.equal(countdown(new Date(0), new Date(1000)).past, true);
});

test('importer parses the example: one MCQ and one theory question', () => {
  const { questions, errors } = parseQuestions(IMPORT_EXAMPLE);
  assert.deepEqual(errors, []);
  assert.equal(questions.length, 2);
  const [mcq, theory] = questions;
  assert.equal(mcq.kind, 'mcq');
  if (mcq.kind === 'mcq') {
    assert.equal(mcq.options.length, 4);
    assert.equal(mcq.answer, 1);
    assert.equal(mcq.topic, 'Logic gates');
    assert.equal(mcq.year, '2023');
  }
  assert.equal(theory.kind, 'theory');
});

test('importer handles numbered questions, answers by text, and reports problems', () => {
  const text = `1. What is 2 + 2?\na) 3\nb) 4\nAnswer: 4\n\n2) Missing answer here\nA. yes\nB. no\n\n3. Define voltage.\nAnswer: Potential difference\nper unit charge.`;
  const { questions, errors } = parseQuestions(text);
  assert.equal(questions.length, 2);
  assert.equal(questions[0].kind === 'mcq' && questions[0].answer, 1);
  assert.equal(questions[1].kind === 'theory' && questions[1].modelAnswer, 'Potential difference\nper unit charge.');
  assert.equal(errors.length, 1);
  assert.match(errors[0], /Question 2/);
});

test('importer keeps numbered points inside a model answer when Q: markers are used', () => {
  const { questions } = parseQuestions(`Q: List two logic families.\nAnswer:\n1. TTL\n2. CMOS`);
  assert.equal(questions.length, 1);
  assert.equal(questions[0].kind === 'theory' && questions[0].modelAnswer, '1. TTL\n2. CMOS');
});

test('planner schedules every needed session before each exam and adds a mock on the eve', () => {
  const a = course('a', '2026-11-10', [['t1', 1], ['t2', 3]]);
  const b = course('b', '2026-11-05', [['u1', 2]], 3);
  const plan = buildPlan({ courses: [a, b], sessions: [], mocksDone: [], today: '2026-11-01', sessionsPerDay: 3, reviewDue: 0 });
  assert.equal(plan.unscheduled, 0);
  const all = plan.days.flatMap(d => d.tasks.map(t => ({ ...t, date: d.date })));
  for (const c of [a, b]) {
    for (const t of c.topics) {
      const n = all.filter(x => x.kind === 'topic' && x.topicId === t.id);
      assert.equal(n.length, sessionsNeeded(t, c), t.name);
      assert.ok(n.every(x => x.date < c.examAt.slice(0, 10)), `${t.name} scheduled before exam`);
    }
  }
  assert.ok(all.some(x => x.kind === 'mock' && x.courseId === 'b' && x.date === '2026-11-04'));
  assert.ok(all.some(x => x.kind === 'mock' && x.courseId === 'a' && x.date === '2026-11-09'));
  assert.ok(plan.days.every(d => d.tasks.length <= 3));
});

test('planner prioritises the nearer exam and counts past sessions', () => {
  const near = course('near', '2026-11-03', [['n1', 1]]);
  const far = course('far', '2026-12-20', [['f1', 1]]);
  const plan = buildPlan({ courses: [far, near], sessions: [], mocksDone: [], today: '2026-11-01', sessionsPerDay: 1, reviewDue: 0 });
  assert.equal(plan.days[0].tasks[0].kind === 'topic' && plan.days[0].tasks[0].topicId, 'near-n1');

  const done = buildPlan({
    courses: [near], mocksDone: [], today: '2026-11-01', sessionsPerDay: 2, reviewDue: 0,
    sessions: [1, 2, 3].map(i => ({ topicId: 'near-n1', courseId: 'near', date: `2026-10-2${i}` })),
  });
  assert.equal(done.days.flatMap(d => d.tasks).filter(t => t.kind === 'topic').length, 0);
});

test('planner reports sessions that cannot fit and puts review first today', () => {
  const tight = course('t', '2026-11-02', [['x', 1], ['y', 1], ['z', 1]]);
  const plan = buildPlan({ courses: [tight], sessions: [], mocksDone: [], today: '2026-11-01', sessionsPerDay: 2, reviewDue: 4 });
  assert.equal(plan.days.length, 1);
  assert.equal(plan.days[0].tasks[0].kind, 'review');
  assert.ok(plan.unscheduled > 0);
});

test('spaced repetition moves cards between boxes', () => {
  let c = review(undefined, false, '2026-11-01');
  assert.deepEqual([c.box, c.due, c.lastWrong], [0, '2026-11-02', '2026-11-01']);
  c = review(c, true, '2026-11-02');
  assert.deepEqual([c.box, c.due], [1, '2026-11-03']);
  for (let i = 0; i < 10; i++) c = review(c, true, '2026-11-03');
  assert.equal(c.box, MASTERED);

  const qs: Question[] = [
    { id: 'q1', courseId: 'a', kind: 'theory', prompt: 'p', modelAnswer: 'm' },
    { id: 'q2', courseId: 'a', kind: 'theory', prompt: 'p', modelAnswer: 'm' },
  ];
  const cards = { q1: review(undefined, false, '2026-11-01'), q2: review(undefined, true, '2026-11-01') };
  assert.deepEqual(dueForReview(qs, cards, '2026-11-02').map(q => q.id), ['q1']);
  assert.deepEqual(dueForReview(qs, cards, '2026-11-01').map(q => q.id), []);
  assert.deepEqual(pickPractice(qs, cards, 1).map(q => q.id), ['q1']);
});
