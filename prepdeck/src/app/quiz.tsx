import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { router, Stack, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Button, C, Card, Empty, F, GRADIENT, Pill, Ring, s, shadow, Tap, Txt, type IconName } from '../components/ui';
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
        <Empty icon="checkmark-done" title="Nothing to practise" body={mode === 'review' ? 'No missed questions are due right now. Nice.' : 'Add past questions to this course first.'}>
          <Button title="Back" onPress={() => router.back()} style={{ alignSelf: 'stretch' }} />
        </Empty>
      </View>
    );
  }

  if (finished) return <Results mode={mode} results={results} seconds={elapsed} />;

  const q = questions[index];
  const last = index === questions.length - 1;
  const mm = String(Math.floor(secondsLeft / 60)).padStart(2, '0');
  const ss = String(secondsLeft % 60).padStart(2, '0');
  const lowTime = secondsLeft < 60;

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
          <View style={[st.timer, lowTime && { backgroundColor: C.redSoft }]}>
            <Ionicons name="timer" size={15} color={lowTime ? C.red : C.accent} />
            <Text style={[st.timerText, lowTime && { color: C.red }]}>{mm}:{ss}</Text>
          </View>
        ) : undefined,
      }} />

      <View style={st.steps}>
        {questions.map((x, i) => {
          const r = results[i];
          const color = mode === 'mock'
            ? (mockAnswers[x.id] !== undefined ? C.primary : i === index ? C.violet : C.line)
            : r ? (r.correct ? C.green : C.red) : i === index ? C.primary : C.line;
          return <View key={x.id} style={[st.step, { backgroundColor: color, opacity: i === index && !r ? 1 : r || mockAnswers[x.id] !== undefined ? 1 : 0.9 }]} />;
        })}
      </View>

      <ScrollView contentContainerStyle={[s.content, { paddingTop: 12 }]} showsVerticalScrollIndicator={false}>
        <View style={[s.row, { flexWrap: 'wrap', gap: 6 }]}>
          <Pill label={`Question ${index + 1} of ${questions.length}`} />
          {q.topic ? <Pill label={q.topic} color={C.ink2} bg={C.line} /> : null}
          {q.year ? <Pill label={q.year} color={C.accent} bg={C.accentSoft} /> : null}
        </View>
        <Card style={{ paddingVertical: 22 }}>
          <Text style={st.prompt}>{q.prompt}</Text>
        </Card>

        {q.kind === 'mcq' ? q.options.map((o, i) => {
          const letter = String.fromCharCode(65 + i);
          let border = 'transparent', bg = C.card, fg = C.ink, bubble = C.bg, bubbleFg = C.ink2, mark: IconName | null = null;
          if (mode === 'mock') {
            if (mockAnswers[q.id] === i) { border = C.primary; bg = C.primarySoft; bubble = C.primary; bubbleFg = '#fff'; }
          } else if (chosen !== null) {
            if (i === q.answer) { border = C.green; bg = C.greenSoft; bubble = C.green; bubbleFg = '#fff'; mark = 'checkmark-circle'; }
            else if (i === chosen) { border = C.red; bg = C.redSoft; bubble = C.red; bubbleFg = '#fff'; mark = 'close-circle'; }
            else fg = C.ink3;
          }
          return (
            <Tap key={i} scale={0.98} accessibilityRole="button" accessibilityLabel={`Option ${letter}: ${o}`}
              style={[st.option, shadow, { borderColor: border, backgroundColor: bg }]}
              onPress={() => (mode === 'mock' ? setMockAnswers(a => ({ ...a, [q.id]: i })) : answerPractice(i))}>
              <View style={[st.letter, { backgroundColor: bubble }]}><Text style={[st.letterText, { color: bubbleFg }]}>{letter}</Text></View>
              <Text style={[st.optionText, { color: fg }]}>{o}</Text>
              {mark ? <Ionicons name={mark} size={24} color={border} /> : null}
            </Tap>
          );
        }) : null}

        {mode !== 'mock' && q.kind === 'mcq' && chosen !== null && (
          <View style={[st.feedback, { backgroundColor: chosen === q.answer ? C.greenSoft : C.redSoft }]}>
            <View style={s.row}>
              <Ionicons name={chosen === q.answer ? 'sparkles' : 'bulb'} size={20} color={chosen === q.answer ? C.green : C.red} />
              <Text style={[st.verdict, { color: chosen === q.answer ? C.green : C.red }]}>
                {chosen === q.answer ? 'Correct! Nicely done.' : `Not quite. It’s ${String.fromCharCode(65 + q.answer)}.`}
              </Text>
            </View>
            {q.explanation ? <Text style={st.explain}>{q.explanation}</Text> : null}
          </View>
        )}

        {q.kind === 'theory' && (
          showAnswer ? (
            <Card>
              <Txt v="overline" style={{ color: C.primary }}>Model answer</Txt>
              <Text style={[st.explain, { marginTop: 8 }]}>{q.modelAnswer}</Text>
              <Txt v="bodyStrong" style={{ marginTop: 16 }}>Did your answer cover this?</Txt>
              <View style={[s.row, { marginTop: 12 }]}>
                <Button title="I missed it" kind="danger" icon="close" style={{ flex: 1 }} onPress={() => selfGrade(false)} />
                <Button title="I got it" icon="checkmark" style={{ flex: 1 }} onPress={() => selfGrade(true)} />
              </View>
            </Card>
          ) : (
            <Card flat style={{ backgroundColor: C.primarySoft, gap: 12 }}>
              <View style={s.row}>
                <Ionicons name="create" size={20} color={C.primary} />
                <Txt v="small" style={{ flex: 1, color: C.ink }}>Answer it in your head or on paper first, then check against the model answer.</Txt>
              </View>
              <Button title="Show model answer" icon="eye" onPress={() => setShowAnswer(true)} />
            </Card>
          )
        )}
      </ScrollView>

      <View style={st.footer}>
        {mode === 'mock' ? (
          <>
            <Button title="Back" kind="secondary" icon="chevron-back" disabled={index === 0} onPress={() => setIndex(index - 1)} style={{ flex: 1 }} />
            {last ? (
              <Button title="Submit" icon="checkmark-done" style={{ flex: 1.4 }} onPress={() => {
                const blank = questions.length - Object.keys(mockAnswers).length;
                if (blank > 0) confirm('Submit the exam?', `${blank} question${blank === 1 ? ' is' : 's are'} unanswered.`, 'Submit', submitMock);
                else submitMock();
              }} />
            ) : (
              <Button title="Next" icon="chevron-forward" style={{ flex: 1.4 }} onPress={() => setIndex(index + 1)} />
            )}
          </>
        ) : q.kind === 'mcq' ? (
          <Button title={last ? 'See results' : 'Next question'} icon={last ? 'trophy' : 'arrow-forward'} disabled={chosen === null} style={{ flex: 1 }}
            onPress={() => next({ q, correct: chosen === q.answer, chosen: chosen ?? undefined })} />
        ) : null}
      </View>
    </View>
  );
}

function Results({ mode, results, seconds }: { mode: QuizMode; results: Result[]; seconds: number }) {
  const correct = results.filter(r => r.correct).length;
  const pct = correct / results.length;
  const missed = results.filter(r => !r.correct);
  const [title, message, icon]: [string, string, IconName] = pct >= 0.7
    ? ['Excellent!', 'You really know this. Keep the streak going.', 'trophy']
    : pct >= 0.5
      ? ['Good work', 'Solid effort. Review the ones you missed below.', 'thumbs-up']
      : ['Keep going', 'Every miss is now in your review deck and will come back.', 'rocket'];
  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content} showsVerticalScrollIndicator={false}>
      <Stack.Screen options={{ title: '', headerRight: undefined }} />
      <LinearGradient colors={GRADIENT.hero} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={st.scoreCard}>
        <View style={[st.orb, { top: -60, left: -40 }]} />
        <View style={[st.orb, { bottom: -70, right: -50, width: 180, height: 180 }]} />
        <View style={st.badge}><Ionicons name={icon} size={26} color={C.amber} /></View>
        <Text style={st.resultTitle}>{title}</Text>
        <Text style={st.resultMode}>{TITLES[mode]}</Text>
        <View style={{ marginVertical: 18 }}>
          <Ring value={pct} size={150} stroke={14} colors={['#FFD166', '#FF8A4C']} track="rgba(255,255,255,0.15)">
            <Text style={st.scoreBig}>{Math.round(pct * 100)}%</Text>
          </Ring>
        </View>
        <Text style={st.scoreMsg}>{message}</Text>
      </LinearGradient>

      <View style={s.row}>
        <Stat value={correct} label="correct" color={C.green} bg={C.greenSoft} icon="checkmark-circle" />
        <Stat value={results.length - correct} label="missed" color={C.red} bg={C.redSoft} icon="close-circle" />
        <Stat value={Math.max(1, Math.round(seconds / 60))} label="minutes" color={C.primary} bg={C.primarySoft} icon="time" />
      </View>

      {missed.length > 0 && <Txt v="h2">Review these</Txt>}
      {missed.map(({ q, chosen }) => (
        <Card key={q.id}>
          <Txt v="h3" style={{ marginBottom: 10 }}>{q.prompt}</Txt>
          {q.kind === 'mcq' ? (
            <View style={{ gap: 8 }}>
              {chosen !== undefined && (
                <View style={[st.ans, { backgroundColor: C.redSoft }]}>
                  <Ionicons name="close-circle" size={18} color={C.red} />
                  <Text style={[st.ansText, { color: C.red }]}>{String.fromCharCode(65 + chosen)}. {q.options[chosen]}</Text>
                </View>
              )}
              <View style={[st.ans, { backgroundColor: C.greenSoft }]}>
                <Ionicons name="checkmark-circle" size={18} color={C.green} />
                <Text style={[st.ansText, { color: C.green }]}>{String.fromCharCode(65 + q.answer)}. {q.options[q.answer]}</Text>
              </View>
              {q.explanation ? <Txt v="small" style={{ marginTop: 2 }}>{q.explanation}</Txt> : null}
            </View>
          ) : <Txt v="small">{q.modelAnswer}</Txt>}
        </Card>
      ))}
      <Button title="Done" icon="checkmark" onPress={() => router.back()} />
    </ScrollView>
  );
}

function Stat({ value, label, color, bg, icon }: { value: number; label: string; color: string; bg: string; icon: IconName }) {
  return (
    <Card style={{ flex: 1, alignItems: 'center', paddingVertical: 14, gap: 4 }}>
      <View style={{ width: 34, height: 34, borderRadius: 12, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
        <Ionicons name={icon} size={18} color={color} />
      </View>
      <Text style={st.statNum}>{value}</Text>
      <Txt v="caption" style={{ color: C.ink2 }}>{label}</Txt>
    </Card>
  );
}

const st = StyleSheet.create({
  steps: { flexDirection: 'row', gap: 4, paddingHorizontal: 20, paddingTop: 4 },
  step: { flex: 1, height: 6, borderRadius: 3 },
  prompt: { fontFamily: F.bold, fontSize: 20, color: C.ink, lineHeight: 29, letterSpacing: -0.2 },
  option: { flexDirection: 'row', alignItems: 'center', gap: 14, padding: 14, borderRadius: 20, borderWidth: 2 },
  letter: { width: 38, height: 38, borderRadius: 13, alignItems: 'center', justifyContent: 'center' },
  letterText: { fontFamily: F.extrabold, fontSize: 15 },
  optionText: { flex: 1, fontFamily: F.semibold, fontSize: 16, lineHeight: 22 },
  feedback: { borderRadius: 20, padding: 16, gap: 6 },
  verdict: { fontFamily: F.extrabold, fontSize: 16, flex: 1 },
  explain: { fontFamily: F.medium, fontSize: 14.5, color: C.ink, lineHeight: 22 },
  footer: { flexDirection: 'row', gap: 10, paddingHorizontal: 20, paddingTop: 14, paddingBottom: 28, backgroundColor: C.card, borderTopLeftRadius: 28, borderTopRightRadius: 28, ...shadow },
  timer: { flexDirection: 'row', alignItems: 'center', gap: 5, backgroundColor: C.accentSoft, paddingHorizontal: 12, paddingVertical: 6, borderRadius: 999 },
  timerText: { fontFamily: F.extrabold, color: C.accent, fontVariant: ['tabular-nums'], fontSize: 14 },
  scoreCard: { borderRadius: 30, padding: 24, alignItems: 'center', overflow: 'hidden' },
  orb: { position: 'absolute', width: 140, height: 140, borderRadius: 999, backgroundColor: '#fff', opacity: 0.08 },
  badge: { width: 56, height: 56, borderRadius: 20, backgroundColor: 'rgba(255,255,255,0.16)', alignItems: 'center', justifyContent: 'center' },
  resultTitle: { fontFamily: F.extrabold, fontSize: 28, color: '#fff', marginTop: 12, letterSpacing: -0.6 },
  resultMode: { fontFamily: F.semibold, fontSize: 13.5, color: 'rgba(255,255,255,0.75)' },
  scoreBig: { fontFamily: F.extrabold, fontSize: 38, color: '#fff', letterSpacing: -1 },
  scoreMsg: { fontFamily: F.semibold, fontSize: 15, color: '#fff', textAlign: 'center', lineHeight: 22 },
  statNum: { fontFamily: F.extrabold, fontSize: 22, color: C.ink },
  ans: { flexDirection: 'row', alignItems: 'flex-start', gap: 8, borderRadius: 14, padding: 10 },
  ansText: { flex: 1, fontFamily: F.semibold, fontSize: 14, lineHeight: 20 },
});
