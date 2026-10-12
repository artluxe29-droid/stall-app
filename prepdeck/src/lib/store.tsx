import AsyncStorage from '@react-native-async-storage/async-storage';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { dayKey } from './dates';
import type { DraftQuestion } from './importer';
import { review } from './srs';
import type { AppState, Confidence, Course, QuizAttempt, Settings } from './types';

const KEY = 'prepdeck:v1';

export const COURSE_COLORS = ['#4F46E5', '#0EA5E9', '#16A34A', '#F59E0B', '#E11D48', '#9333EA', '#0D9488', '#EA580C'];

export const DEFAULT_SETTINGS: Settings = {
  name: '',
  sessionsPerDay: 4,
  reminderHour: 19,
  reminderMinute: 0,
  remindersOn: true,
};

const EMPTY: AppState = { courses: [], questions: [], cards: {}, sessions: [], mocksDone: [], attempts: [], settings: DEFAULT_SETTINGS };

export const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);

interface Store {
  ready: boolean;
  state: AppState;
  addCourse(c: Omit<Course, 'id' | 'color'>): string;
  updateCourse(id: string, patch: Partial<Omit<Course, 'id'>>): void;
  deleteCourse(id: string): void;
  setConfidence(courseId: string, topicId: string, confidence: Confidence): void;
  toggleSession(courseId: string, topicId: string): void;
  addQuestions(courseId: string, drafts: DraftQuestion[]): number;
  deleteQuestion(id: string): void;
  recordAnswer(questionId: string, correct: boolean): void;
  finishQuiz(attempt: Omit<QuizAttempt, 'id' | 'date'>): void;
  updateSettings(patch: Partial<Settings>): void;
  replaceAll(next: AppState): void;
}

const Ctx = createContext<Store | null>(null);

export function StoreProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AppState>(EMPTY);
  const [ready, setReady] = useState(false);
  const loaded = useRef(false);

  useEffect(() => {
    AsyncStorage.getItem(KEY)
      .then(raw => {
        if (raw) {
          const saved = JSON.parse(raw) as Partial<AppState>;
          setState({ ...EMPTY, ...saved, settings: { ...DEFAULT_SETTINGS, ...saved.settings } });
        }
      })
      .catch(() => {})
      .finally(() => {
        loaded.current = true;
        setReady(true);
      });
  }, []);

  useEffect(() => {
    if (loaded.current) AsyncStorage.setItem(KEY, JSON.stringify(state)).catch(() => {});
  }, [state]);

  const update = useCallback((fn: (s: AppState) => AppState) => setState(fn), []);

  const store = useMemo<Store>(() => ({
    ready,
    state,
    addCourse(c) {
      const id = uid();
      update(s => ({ ...s, courses: [...s.courses, { ...c, id, color: COURSE_COLORS[s.courses.length % COURSE_COLORS.length] }] }));
      return id;
    },
    updateCourse(id, patch) {
      update(s => ({ ...s, courses: s.courses.map(c => (c.id === id ? { ...c, ...patch } : c)) }));
    },
    deleteCourse(id) {
      update(s => {
        const gone = new Set(s.questions.filter(q => q.courseId === id).map(q => q.id));
        const cards = Object.fromEntries(Object.entries(s.cards).filter(([k]) => !gone.has(k)));
        return {
          ...s,
          courses: s.courses.filter(c => c.id !== id),
          questions: s.questions.filter(q => q.courseId !== id),
          cards,
          sessions: s.sessions.filter(x => x.courseId !== id),
          mocksDone: s.mocksDone.filter(x => x.courseId !== id),
          attempts: s.attempts.filter(x => x.courseId !== id),
        };
      });
    },
    setConfidence(courseId, topicId, confidence) {
      update(s => ({
        ...s,
        courses: s.courses.map(c => (c.id !== courseId ? c : { ...c, topics: c.topics.map(t => (t.id === topicId ? { ...t, confidence } : t)) })),
      }));
    },
    toggleSession(courseId, topicId) {
      const today = dayKey();
      update(s => {
        const has = s.sessions.some(x => x.topicId === topicId && x.date === today);
        return {
          ...s,
          sessions: has ? s.sessions.filter(x => !(x.topicId === topicId && x.date === today)) : [...s.sessions, { courseId, topicId, date: today }],
        };
      });
    },
    addQuestions(courseId, drafts) {
      const fresh = drafts.map(d => ({ ...d, id: uid(), courseId }));
      update(s => ({ ...s, questions: [...s.questions, ...fresh] }));
      return fresh.length;
    },
    deleteQuestion(id) {
      update(s => {
        const { [id]: _, ...cards } = s.cards;
        return { ...s, questions: s.questions.filter(q => q.id !== id), cards };
      });
    },
    recordAnswer(questionId, correct) {
      const today = dayKey();
      update(s => ({ ...s, cards: { ...s.cards, [questionId]: review(s.cards[questionId], correct, today) } }));
    },
    finishQuiz(a) {
      const today = dayKey();
      update(s => ({
        ...s,
        attempts: [...s.attempts, { ...a, id: uid(), date: new Date().toISOString() }],
        mocksDone: a.mode === 'mock' && !s.mocksDone.some(m => m.courseId === a.courseId && m.date === today)
          ? [...s.mocksDone, { courseId: a.courseId, date: today }]
          : s.mocksDone,
      }));
    },
    updateSettings(patch) {
      update(s => ({ ...s, settings: { ...s.settings, ...patch } }));
    },
    replaceAll(next) {
      update(() => next);
    },
  }), [ready, state, update]);

  return <Ctx.Provider value={store}>{children}</Ctx.Provider>;
}

export function useStore(): Store {
  const s = useContext(Ctx);
  if (!s) throw new Error('useStore must be used inside StoreProvider');
  return s;
}
