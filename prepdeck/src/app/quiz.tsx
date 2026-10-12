import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { router, Stack, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Button, C, Card, Empty, H2, Muted, s } from '../components/ui';
import { confirm } from '../lib/confirm';
import { dayKey } from '../lib/dates';
import { dueForReview, pickPractice, shuffle } from '../lib/srs';
import { useStore } from '../lib/store';
import type { Question, QuizMode } from '../lib/types';

interface Result {
  q: Question;
  correct: boolean;
  chosen?: number;
}

const TITLES: Record<QuizMode, string> = { practice: 'Practice', mock: 'Mock exam', review: 'Review mistakes' };

function buzz(ok: boolean) {
  if (Platform.OS === 'web') return;
  Haptics.notificationAsync(ok ? Haptics.NotificationFeedbackType.Success : Haptics.NotificationFeedbackType.Error).catch(() => {});
}

export default function Quiz() {
  const params = useLocalSearchParams<{ courseId: string; mode: QuizMode; count: string }>();
  const mode: QuizMode = params.mode ?? 'practice';
  const courseId = params.courseId ?? 'all';
  const { state, recordAnswer, finishQuiz } = useStore();

  // Questions are picked once when the quiz opens, so answering doesn't reshuffle them.
  const [questions] = useState<Question[]>(() => {
    const count = Math.max(1, Number(params.count) || 10);
    const pool = state.questions.filter(q => courseId === 'all' || q.courseId === courseId);
    if (mode === 'review') return shuffle(dueForReview(pool, state.cards, dayKey())).slice(0, count);
    if (mode === 'mock') return shuffle(pool.filter(q => q.kind === 'mcq')).slice(0, count);
    return pickPractice(pool, state.cards, count);
  });

  const [started] = useState(() => Date.now());
  const [elapsed, setElapsed] = useState(0);
  const saved = useRef(false);
  const [index, setIndex] = useState(0);
  const [results, setResults] = useState<Result[]>([]);
  const [chosen, setChosen] = useState<number | null>(null); // practice: the option tapped on this question
  const [showAnswer, setShowAnswer] = useState(false); // practice theory: model answer visible
  const [mockAnswers, setMockAnswers] = useState<Record<string, number>>({});
  const [finished, setFinished] = useState(false);
  const [secondsLeft, setSecondsLeft] = useState(questions.length * 60);

  const finish = (all: Result[]) => {
    const seconds = Math.round((Date.now() - started) / 1000);
    setResults(all);
    setElapsed(seconds);
    setFinished(true);
    if (!saved.current && all.length) {
      saved.current = true;
      finishQuiz({ courseId, mode, total: all.length, correct: all.filter(r => r.correct).length, seconds });
    }
  };

  const submitMock = () => {
    const all = questions.map(q => {
      const pick = mockAnswers[q.id];
      const correct = q.kind === 'mcq' && pick === q.answer;
      recordAnswer(q.id, correct);
      return { q, correct, chosen: pick };
    });
    finish(all);
  };

  // Mock exam timer: submits automatically when time runs out.
  useEffect(() => {
    if (mode !== 'mock' || finished) return;
    const t = setTimeout(() => {
      if (secondsLeft <= 1) submitMock();
      else setSecondsLeft(n => n - 1);
    }, 1000);
    return () => clearTimeout(t);
  }, [mode, finished, secondsLeft]); // eslint-disable-line react-hooks/exhaustive-deps

  if (questions.length === 0) {
    return (
      <View style={[s.screen, s.content]}>
        <Stack.Screen options={{ title: TITLES[mode] }} />
        <Empty icon="checkmark-done-outline" title="Nothing to practise" body={mode === 'review' ? 'No missed questions are due right now.' : 'Add past questions to this course first.'}>
          <Button title="Back" onPress={() => router.back()} />
        </Empty>
      </View>
    );
  }

  if (finished) return <Results mode={mode} results={results} seconds={elapsed} />;

  const q = questions[index];
  const last = index === questions.length - 1;
  const mm = String(Math.floor(secondsLeft / 60)).padStart(2, '0');
  const ss = String(secondsLeft % 60).padStart(2, '0');

  const next = (r?: Result) => {
    const all = r ? [...results, r] : results;
    setResults(all);
    setChosen(null);
    setShowAnswer(false);
    if (last) finish(all);
    else setIndex(index + 1);
  };

  const answerPractice = (i: number) => {
    if (chosen !== null || q.kind !== 'mcq') return;
    setChosen(i);
    const ok = i === q.answer;
    buzz(ok);
    recordAnswer(q.id, ok);
  };

  const selfGrade = (ok: boolean) => {
    buzz(ok);
    recordAnswer(q.id, ok);
    next({ q, correct: ok });
  };

  return (
    <View style={s.screen}>
      <Stack.Screen options={{
        title: TITLES[mode],
        headerRight: mode === 'mock' ? () => (
          <View style={[st.timer, secondsLeft < 60 && { backgroundColor: C.redSoft }]}>
            <Ionicons name="timer-outline" size={15} color={secondsLeft < 60 ? C.red : '#B45309'} />
            <Text style={[st.timerText, secondsLeft < 60 && { color: C.red }]}>{mm}:{ss}</Text>
          </View>
        ) : undefined,
      }} />
      <View style={st.progressTrack}><View style={[st.progressFill, { width: `${((index + 1) / questions.length) * 100}%` }]} /></View>

      <ScrollView contentContainerStyle={s.content}>
        <Muted style={{ fontWeight: '700' }}>
          Question {index + 1} of {questions.length}{q.topic ? ` · ${q.topic}` : ''}{q.year ? ` · ${q.year}` : ''}
        </Muted>
        <Text style={st.prompt}>{q.prompt}</Text>

        {q.kind === 'mcq' ? q.options.map((o, i) => {
          const letter = String.fromCharCode(65 + i);
          let border = C.line, bg = C.card, fg = C.ink;
          if (mode === 'mock') {
            if (mockAnswers[q.id] === i) { border = C.primary; bg = C.primarySoft; }
          } else if (chosen !== null) {
            if (i === q.answer) { border = C.green; bg = C.greenSoft; }
            else if (i === chosen) { border = C.red; bg = C.redSoft; }
            else fg = C.ink3;
          }
          return (
            <Pressable key={i} style={[st.option, { borderColor: border, backgroundColor: bg }]}
              onPress={() => (mode === 'mock' ? setMockAnswers(a => ({ ...a, [q.id]: i })) : answerPractice(i))}>
              <View style={[st.letter, { borderColor: border }]}><Text style={[st.letterText, { color: fg }]}>{letter}</Text></View>
              <Text style={[st.optionText, { color: fg }]}>{o}</Text>
            </Pressable>
          );
        }) : null}

        {mode !== 'mock' && q.kind === 'mcq' && chosen !== null && (
          <Card style={{ backgroundColor: chosen === q.answer ? C.greenSoft : C.redSoft, borderColor: 'transparent' }}>
            <Text style={[st.verdict, { color: chosen === q.answer ? C.green : C.red }]}>
              {chosen === q.answer ? 'Correct' : `Not quite. The answer is ${String.fromCharCode(65 + q.answer)}.`}
            </Text>
            {q.explanation ? <Text style={st.explain}>{q.explanation}</Text> : null}
          </Card>
        )}

        {q.kind === 'theory' && (
          showAnswer ? (
            <Card style={{ backgroundColor: C.primarySoft, borderColor: 'transparent' }}>
              <H2>Model answer</H2>
              <Text style={[st.explain, { marginTop: 6 }]}>{q.modelAnswer}</Text>
              <Muted style={{ marginTop: 12 }}>Did your answer cover this?</Muted>
              <View style={[s.row, { marginTop: 10 }]}>
                <Button title="I missed it" kind="danger" style={{ flex: 1 }} onPress={() => selfGrade(false)} />
                <Button title="I got it" style={{ flex: 1, backgroundColor: C.green }} onPress={() => selfGrade(true)} />
              </View>
            </Card>
          ) : (
            <>
              <Muted>Answer it in your head or on paper first, then check.</Muted>
              <Button title="Show model answer" kind="secondary" icon="eye-outline" onPress={() => setShowAnswer(true)} />
            </>
          )
        )}
      </ScrollView>

      <View style={st.footer}>
        {mode === 'mock' ? (
          <>
            <Button title="Back" kind="secondary" icon="chevron-back" disabled={index === 0} onPress={() => setIndex(index - 1)} style={{ flex: 1 }} />
            {last ? (
              <Button title="Submit" icon="checkmark" style={{ flex: 1 }} onPress={() => {
                const blank = questions.length - Object.keys(mockAnswers).length;
                if (blank > 0) confirm('Submit the exam?', `${blank} question${blank === 1 ? ' is' : 's are'} unanswered.`, 'Submit', submitMock);
                else submitMock();
              }} />
            ) : (
              <Button title="Next" style={{ flex: 1 }} onPress={() => setIndex(index + 1)} />
            )}
          </>
        ) : q.kind === 'mcq' ? (
          <Button title={last ? 'See results' : 'Next question'} disabled={chosen === null} style={{ flex: 1 }}
            onPress={() => next({ q, correct: chosen === q.answer, chosen: chosen ?? undefined })} />
        ) : null}
      </View>
    </View>
  );
}

function Results({ mode, results, seconds }: { mode: QuizMode; results: Result[]; seconds: number }) {
  const correct = results.filter(r => r.correct).length;
  const pct = Math.round((correct / results.length) * 100);
  const missed = results.filter(r => !r.correct);
  const message = pct >= 70 ? 'Excellent work.' : pct >= 50 ? 'Good. Review the ones you missed.' : 'Keep going. Missed questions will come back for review.';
  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <Stack.Screen options={{ title: `${TITLES[mode]} results`, headerRight: undefined }} />
      <View style={st.scoreCard}>
        <Text style={st.scoreBig}>{pct}%</Text>
        <Text style={st.scoreSub}>{correct} of {results.length} correct · {Math.max(1, Math.round(seconds / 60))} min</Text>
        <Text style={st.scoreMsg}>{message}</Text>
      </View>
      {missed.length > 0 && <H2>To review</H2>}
      {missed.map(({ q, chosen }) => (
        <Card key={q.id}>
          <Text style={st.reviewQ}>{q.prompt}</Text>
          {q.kind === 'mcq' ? (
            <>
              {chosen !== undefined && <Text style={[st.explain, { color: C.red }]}>Your answer: {String.fromCharCode(65 + chosen)}) {q.options[chosen]}</Text>}
              <Text style={[st.explain, { color: C.green, fontWeight: '700' }]}>Correct: {String.fromCharCode(65 + q.answer)}) {q.options[q.answer]}</Text>
              {q.explanation ? <Muted style={{ marginTop: 4 }}>{q.explanation}</Muted> : null}
            </>
          ) : <Muted>{q.modelAnswer}</Muted>}
        </Card>
      ))}
      <Button title="Done" onPress={() => router.back()} />
    </ScrollView>
  );
}

const st = StyleSheet.create({
  progressTrack: { height: 4, backgroundColor: C.primarySoft },
  progressFill: { height: 4, backgroundColor: C.primary },
  prompt: { fontSize: 19, fontWeight: '700', color: C.ink, lineHeight: 27, marginBottom: 4 },
  option: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 14, borderRadius: 16, borderWidth: 2 },
  letter: { width: 30, height: 30, borderRadius: 15, borderWidth: 2, alignItems: 'center', justifyContent: 'center' },
  letterText: { fontWeight: '800', fontSize: 14 },
  optionText: { flex: 1, fontSize: 16, fontWeight: '500' },
  verdict: { fontSize: 16, fontWeight: '800' },
  explain: { fontSize: 14, color: C.ink, lineHeight: 21, marginTop: 4 },
  footer: { flexDirection: 'row', gap: 10, padding: 16, paddingBottom: 24, borderTopWidth: 1, borderTopColor: C.line, backgroundColor: C.card },
  timer: { flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: C.amberSoft, paddingHorizontal: 10, paddingVertical: 5, borderRadius: 20 },
  timerText: { fontWeight: '800', color: '#B45309', fontVariant: ['tabular-nums'] },
  scoreCard: { backgroundColor: C.hero, borderRadius: 22, padding: 24, alignItems: 'center' },
  scoreBig: { fontSize: 56, fontWeight: '800', color: '#fff' },
  scoreSub: { fontSize: 15, color: '#C7D2FE', marginTop: 4 },
  scoreMsg: { fontSize: 15, color: '#fff', marginTop: 12, fontWeight: '600', textAlign: 'center' },
  reviewQ: { fontSize: 15, fontWeight: '700', color: C.ink, marginBottom: 6 },
});
