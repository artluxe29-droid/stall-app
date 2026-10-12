import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { C, Card, Dot, Empty, H1, H2, Muted, s } from '../../components/ui';
import { addDays, dayKey } from '../../lib/dates';
import { MASTERED } from '../../lib/srs';
import { useStore } from '../../lib/store';

export default function Progress() {
  const { state } = useStore();
  const cards = Object.entries(state.cards);
  const seen = cards.reduce((n, [, c]) => n + c.seen, 0);
  const correct = cards.reduce((n, [, c]) => n + c.correct, 0);
  const mastered = cards.filter(([, c]) => c.box >= MASTERED).length;

  // Streak: consecutive days (ending today or yesterday) with a ticked session or a finished quiz.
  const active = new Set([...state.sessions.map(x => x.date), ...state.attempts.map(a => dayKey(new Date(a.date)))]);
  let streak = 0;
  let d = active.has(dayKey()) ? dayKey() : addDays(dayKey(), -1);
  while (active.has(d)) {
    streak++;
    d = addDays(d, -1);
  }

  const stats: [string, string, string][] = [
    [`${streak}`, streak === 1 ? 'day streak' : 'day streak', C.amber],
    [`${seen}`, 'answers', C.primary],
    [seen ? `${Math.round((correct / seen) * 100)}%` : '–', 'accuracy', C.green],
    [`${mastered}`, 'mastered', '#9333EA'],
  ];

  const recent = [...state.attempts].reverse().slice(0, 8);
  const code = (id: string) => state.courses.find(c => c.id === id)?.code ?? 'All courses';

  if (state.courses.length === 0) {
    return (
      <SafeAreaView style={s.screen} edges={['top']}>
        <ScrollView contentContainerStyle={s.content}>
          <H1>Progress</H1>
          <Empty icon="stats-chart-outline" title="Nothing to show yet" body="Your streak, accuracy and mock scores appear here once you start revising." />
        </ScrollView>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={s.screen} edges={['top']}>
      <ScrollView contentContainerStyle={s.content}>
        <H1>Progress</H1>
        <View style={st.grid}>
          {stats.map(([v, l, color]) => (
            <View key={l} style={st.stat}>
              <Text style={[st.statNum, { color }]}>{v}</Text>
              <Text style={st.statLabel}>{l}</Text>
            </View>
          ))}
        </View>

        <Card>
          <H2>By course</H2>
          {state.courses.map(c => {
            const ids = new Set(state.questions.filter(q => q.courseId === c.id).map(q => q.id));
            const cs = cards.filter(([id]) => ids.has(id)).map(([, x]) => x);
            const sn = cs.reduce((n, x) => n + x.seen, 0);
            const acc = sn ? Math.round((cs.reduce((n, x) => n + x.correct, 0) / sn) * 100) : null;
            const shaky = c.topics.filter(t => t.confidence === 1).length;
            const lastMock = [...state.attempts].reverse().find(a => a.courseId === c.id && a.mode === 'mock');
            return (
              <View key={c.id} style={st.courseRow}>
                <View style={[s.row, { justifyContent: 'space-between' }]}>
                  <View style={[s.row, { gap: 8 }]}><Dot color={c.color} /><Text style={st.code}>{c.code}</Text></View>
                  <Text style={st.acc}>{acc === null ? 'no answers yet' : `${acc}% correct`}</Text>
                </View>
                <View style={st.track}><View style={[st.fill, { width: `${acc ?? 0}%`, backgroundColor: c.color }]} /></View>
                <Muted style={{ fontSize: 12 }}>
                  {shaky ? `${shaky} shaky topic${shaky === 1 ? '' : 's'}` : 'No shaky topics'}
                  {lastMock ? ` · last mock ${Math.round((lastMock.correct / lastMock.total) * 100)}%` : ''}
                </Muted>
              </View>
            );
          })}
        </Card>

        {recent.length > 0 && (
          <Card>
            <H2>Recent quizzes</H2>
            {recent.map(a => (
              <View key={a.id} style={st.attempt}>
                <View style={{ flex: 1 }}>
                  <Text style={st.code}>{code(a.courseId)}</Text>
                  <Muted style={{ fontSize: 12 }}>
                    {{ practice: 'Practice', mock: 'Mock exam', review: 'Review' }[a.mode]} · {new Date(a.date).toLocaleDateString()} · {Math.max(1, Math.round(a.seconds / 60))} min
                  </Muted>
                </View>
                <Text style={[st.score, { color: a.correct / a.total >= 0.5 ? C.green : C.red }]}>{a.correct}/{a.total}</Text>
              </View>
            ))}
          </Card>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const st = StyleSheet.create({
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  stat: { flexGrow: 1, flexBasis: '45%', backgroundColor: C.card, borderRadius: 18, padding: 16, borderWidth: 1, borderColor: C.line },
  statNum: { fontSize: 28, fontWeight: '800' },
  statLabel: { fontSize: 13, color: C.ink2, fontWeight: '600', marginTop: 2 },
  courseRow: { paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: C.line, gap: 6 },
  code: { fontSize: 15, fontWeight: '700', color: C.ink },
  acc: { fontSize: 13, fontWeight: '600', color: C.ink2 },
  track: { height: 6, borderRadius: 3, backgroundColor: C.line, overflow: 'hidden' },
  fill: { height: 6, borderRadius: 3 },
  attempt: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: C.line },
  score: { fontSize: 17, fontWeight: '800' },
});
