import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Bar, C, Card, Dot, Empty, F, GRADIENT, IconBubble, Ring, s, shadow, Txt, type IconName } from '../../components/ui';
import { addDays, dayKey, fromKey } from '../../lib/dates';
import { MASTERED } from '../../lib/srs';
import { activeDays, streak } from '../../lib/stats';
import { useStore } from '../../lib/store';

const WEEKDAY = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

export default function Progress() {
  const { state } = useStore();
  const cards = Object.entries(state.cards);
  const seen = cards.reduce((n, [, c]) => n + c.seen, 0);
  const correct = cards.reduce((n, [, c]) => n + c.correct, 0);
  const mastered = cards.filter(([, c]) => c.box >= MASTERED).length;
  const days = streak(state);
  const active = activeDays(state);
  const today = dayKey();
  const week = Array.from({ length: 7 }, (_, i) => addDays(today, i - 6));
  const accuracy = seen ? correct / seen : 0;

  if (state.courses.length === 0) {
    return (
      <SafeAreaView style={s.screen} edges={['top']}>
        <ScrollView contentContainerStyle={s.content}>
          <Txt v="title">Progress</Txt>
          <Empty icon="trophy" title="Nothing to show yet" body="Your streak, accuracy and mock scores appear here once you start revising." />
        </ScrollView>
      </SafeAreaView>
    );
  }

  const recent = [...state.attempts].reverse().slice(0, 8);
  const code = (id: string) => state.courses.find(c => c.id === id)?.code ?? 'All courses';

  return (
    <SafeAreaView style={s.screen} edges={['top']}>
      <ScrollView contentContainerStyle={s.content} showsVerticalScrollIndicator={false}>
        <Txt v="title">Progress</Txt>

        <LinearGradient colors={GRADIENT.warm} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={st.streakCard}>
          <View style={s.between}>
            <View>
              <Text style={st.streakNum}>{days} day{days === 1 ? '' : 's'}</Text>
              <Text style={st.streakSub}>{days ? 'study streak. Don’t break the chain!' : 'Tick a task today to start a streak.'}</Text>
            </View>
            <View style={st.flame}><Ionicons name="flame" size={30} color="#fff" /></View>
          </View>
          <View style={[s.between, { marginTop: 18 }]}>
            {week.map(d => {
              const on = active.has(d);
              return (
                <View key={d} style={{ alignItems: 'center', gap: 6 }}>
                  <View style={[st.dayDot, on && st.dayOn, d === today && !on && st.dayToday]}>
                    {on ? <Ionicons name="checkmark" size={16} color={C.accent} /> : null}
                  </View>
                  <Text style={st.dayLabel}>{WEEKDAY[fromKey(d).getDay()]}</Text>
                </View>
              );
            })}
          </View>
        </LinearGradient>

        <View style={[s.row, { alignItems: 'stretch' }]}>
          <Card style={[{ flex: 1, alignItems: 'center', gap: 8 }]}>
            <Ring value={accuracy} size={92} stroke={10} colors={GRADIENT.green} track={C.greenSoft}>
              <Text style={st.ringNum}>{seen ? `${Math.round(accuracy * 100)}%` : '–'}</Text>
            </Ring>
            <Txt v="caption" style={{ color: C.ink2 }}>Accuracy</Txt>
          </Card>
          <View style={{ flex: 1, gap: 12 }}>
            <Stat icon="create" color={C.primary} bg={C.primarySoft} value={seen} label="answers" />
            <Stat icon="ribbon" color={C.violet} bg="#F3EBFF" value={mastered} label="mastered" />
          </View>
        </View>

        <Card>
          <Txt v="h2" style={{ marginBottom: 6 }}>By course</Txt>
          {state.courses.map(c => {
            const ids = new Set(state.questions.filter(q => q.courseId === c.id).map(q => q.id));
            const cs = cards.filter(([id]) => ids.has(id)).map(([, x]) => x);
            const sn = cs.reduce((n, x) => n + x.seen, 0);
            const acc = sn ? cs.reduce((n, x) => n + x.correct, 0) / sn : null;
            const shaky = c.topics.filter(t => t.confidence === 1).length;
            const lastMock = [...state.attempts].reverse().find(a => a.courseId === c.id && a.mode === 'mock');
            return (
              <View key={c.id} style={st.courseRow}>
                <View style={s.between}>
                  <View style={[s.row, { gap: 8 }]}><Dot color={c.color} /><Txt v="h3">{c.code}</Txt></View>
                  <Txt v="caption" style={{ color: C.ink2 }}>{acc === null ? 'No answers yet' : `${Math.round(acc * 100)}% correct`}</Txt>
                </View>
                <Bar value={acc ?? 0} color={c.color} />
                <Txt v="caption" style={{ fontFamily: F.medium }}>
                  {shaky ? `${shaky} shaky topic${shaky === 1 ? '' : 's'}` : 'No shaky topics'}
                  {lastMock ? `  ·  last mock ${Math.round((lastMock.correct / lastMock.total) * 100)}%` : ''}
                </Txt>
              </View>
            );
          })}
        </Card>

        {recent.length > 0 && (
          <Card>
            <Txt v="h2" style={{ marginBottom: 6 }}>Recent quizzes</Txt>
            {recent.map(a => {
              const pct = a.correct / a.total;
              return (
                <View key={a.id} style={st.attempt}>
                  <IconBubble icon={a.mode === 'mock' ? 'timer' : a.mode === 'review' ? 'refresh' : 'flash'} color={C.primary} bg={C.primarySoft} size={40} />
                  <View style={{ flex: 1 }}>
                    <Txt v="h3">{code(a.courseId)}</Txt>
                    <Txt v="caption" style={{ fontFamily: F.medium }}>
                      {{ practice: 'Practice', mock: 'Mock exam', review: 'Review' }[a.mode]}  ·  {new Date(a.date).toLocaleDateString()}  ·  {Math.max(1, Math.round(a.seconds / 60))} min
                    </Txt>
                  </View>
                  <View style={[st.score, { backgroundColor: pct >= 0.5 ? C.greenSoft : C.redSoft }]}>
                    <Text style={[st.scoreText, { color: pct >= 0.5 ? C.green : C.red }]}>{a.correct}/{a.total}</Text>
                  </View>
                </View>
              );
            })}
          </Card>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function Stat({ icon, color, bg, value, label }: { icon: IconName; color: string; bg: string; value: number; label: string }) {
  return (
    <View style={[st.stat, shadow]}>
      <IconBubble icon={icon} color={color} bg={bg} size={38} />
      <View>
        <Text style={st.statNum}>{value}</Text>
        <Txt v="caption" style={{ color: C.ink2 }}>{label}</Txt>
      </View>
    </View>
  );
}

const st = StyleSheet.create({
  streakCard: { borderRadius: 28, padding: 20 },
  streakNum: { fontFamily: F.extrabold, fontSize: 30, color: '#fff', letterSpacing: -0.6 },
  streakSub: { fontFamily: F.semibold, fontSize: 13.5, color: 'rgba(255,255,255,0.9)', marginTop: 2 },
  flame: { width: 56, height: 56, borderRadius: 20, backgroundColor: 'rgba(255,255,255,0.2)', alignItems: 'center', justifyContent: 'center' },
  dayDot: { width: 34, height: 34, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.2)', alignItems: 'center', justifyContent: 'center' },
  dayOn: { backgroundColor: '#fff' },
  dayToday: { borderWidth: 2, borderColor: '#fff' },
  dayLabel: { fontFamily: F.bold, fontSize: 11, color: 'rgba(255,255,255,0.9)' },
  ringNum: { fontFamily: F.extrabold, fontSize: 20, color: C.ink },
  stat: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: C.card, borderRadius: 22, paddingHorizontal: 14, paddingVertical: 12 },
  statNum: { fontFamily: F.extrabold, fontSize: 22, color: C.ink, lineHeight: 26 },
  courseRow: { paddingVertical: 12, gap: 8, borderBottomWidth: 1, borderBottomColor: C.line },
  attempt: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: C.line },
  score: { paddingHorizontal: 12, paddingVertical: 6, borderRadius: 12 },
  scoreText: { fontFamily: F.extrabold, fontSize: 15 },
});
