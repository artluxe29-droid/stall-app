export type Confidence = 1 | 2 | 3; // 1 = shaky, 2 = okay, 3 = solid

export interface Topic {
  id: string;
  name: string;
  confidence: Confidence;
}

export interface Course {
  id: string;
  code: string; // e.g. "CPE 501"
  title: string;
  examAt: string; // ISO date-time of the exam
  venue?: string;
  difficulty: 1 | 2 | 3; // how hard the student finds the course
  color: string;
  topics: Topic[];
}

export type Question =
  | {
      id: string;
      courseId: string;
      kind: 'mcq';
      prompt: string;
      options: string[];
      answer: number; // index into options
      explanation?: string;
      topic?: string;
      year?: string;
    }
  | {
      id: string;
      courseId: string;
      kind: 'theory';
      prompt: string;
      modelAnswer: string;
      topic?: string;
      year?: string;
    };

/** Spaced-repetition state for one question (Leitner boxes). */
export interface CardState {
  box: number; // 0..5; 5 = mastered
  due: string; // YYYY-MM-DD
  seen: number;
  correct: number;
  lastWrong?: string; // YYYY-MM-DD
}

export interface StudySession {
  topicId: string;
  courseId: string;
  date: string; // YYYY-MM-DD it was ticked off
}

export interface QuizAttempt {
  id: string;
  courseId: string;
  mode: QuizMode;
  date: string; // ISO
  total: number;
  correct: number;
  seconds: number;
}

export type QuizMode = 'practice' | 'mock' | 'review';

export interface Settings {
  name: string;
  sessionsPerDay: number;
  reminderHour: number;
  reminderMinute: number;
  remindersOn: boolean;
}

export interface AppState {
  courses: Course[];
  questions: Question[];
  cards: Record<string, CardState>;
  sessions: StudySession[];
  mocksDone: { courseId: string; date: string }[];
  attempts: QuizAttempt[];
  settings: Settings;
}

export type PlanTask =
  | { kind: 'topic'; key: string; courseId: string; topicId: string; label: string }
  | { kind: 'mock'; key: string; courseId: string; label: string }
  | { kind: 'review'; key: string; count: number; label: string };

export interface PlanDay {
  date: string; // YYYY-MM-DD
  tasks: PlanTask[];
}
