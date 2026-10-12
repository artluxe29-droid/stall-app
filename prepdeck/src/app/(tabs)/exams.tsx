import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Button, C, Empty, H1, Muted, s } from '../../components/ui';
import { formatExam, relativeDays } from '../../lib/dates';
import { sessionsNeeded } from '../../lib/planner';
import { useStore } from '../../lib/store';
import { useNow } from '../../lib/useNow';
import type { Course } from '../../lib/types';

export default function Exams() {
  const { state } = useStore();
  const now = useNow();
  const sorted = [...state.courses].sort((a, b) => a.examAt.localeCompare(b.examAt));
  const upcoming = sorted.filter(c => new Date(c.examAt).getTime() > now);
  const past = sorted.filter(c => new Date(c.examAt).getTime() <= now).reverse();

  const coverage = (c: Course) => {
    const need = c.topics.reduce((n, t) => n + sessionsNeeded(t, c), 0);
    const done = c.topics.reduce((n, t) => n + Math.min(sessionsNeeded(t, c), state.sessions.filter(x => x.topicId === t.id).length), 0);
    return need ? done / need : 0;
  };

  const row = (c: Course, dim = false) => {
    const qs = state.questions.filter(q => q.courseId === c.id).length;
    const pct = Math.round(coverage(c) * 100);
    const rel = relativeDays(c.examAt);
    return (
      <Pressable key={c.id} onPress={() => router.push(`/course/${c.id}`)} style={[st.card, dim && { opacity: 0.55 }]}>
        <View style={[st.stripe, { backgroundColor: c.color }]} />
        <View style={{ flex: 1, padding: 14, gap: 4 }}>
          <View style={[s.row, { justifyContent: 'space-between' }]}>
            <Text style={st.code}>{c.code}</Text>
            <View style={[st.badge, rel === 'today' || rel === 'tomorrow' ? { backgroundColor: C.redSoft } : null]}>
              <Text style={[st.badgeText, rel === 'today' || rel === 'tomorrow' ? { color: C.red } : null]}>{rel}</Text>
            </View>
          </View>
          <Text style={st.title} numberOfLines={1}>{c.title}</Text>
          <Muted style={{ fontSize: 13 }}>{formatExam(c.examAt)}{c.venue ? ` · ${c.venue}` : ''}</Muted>
          <View style={[s.row, { marginTop: 8 }]}>
            <View style={st.track}><View style={[st.fill, { width: `${pct}%`, backgroundColor: c.color }]} /></View>
            <Text style={st.meta}>{pct}% revised</Text>
          </View>
          <View style={[s.row, { gap: 14, marginTop: 2 }]}>
            <Text style={st.meta}><Ionicons name="list-outline" size={12} /> {c.topics.length} topics</Text>
            <Text style={st.meta}><Ionicons name="help-circle-outline" size={12} /> {qs} questions</Text>
          </View>
        </View>
      </Pressable>
    );
  };

  return (
    <SafeAreaView style={s.screen} edges={['top']}>
      <ScrollView contentContainerStyle={s.content}>
        <View style={[s.row, { justifyContent: 'space-between' }]}>
          <H1>Exams</H1>
          <Button title="Add" icon="add" onPress={() => router.push('/course/new')} style={{ paddingVertical: 9 }} />
        </View>
        {state.courses.length === 0 ? (
          <Empty icon="calendar-outline" title="No exams yet" body="Add each course with its exam date and topics." />
        ) : (
          <>
            {upcoming.map(c => row(c))}
            {past.length > 0 && <Muted style={{ marginTop: 8, fontWeight: '700' }}>Finished</Muted>}
            {past.map(c => row(c, true))}
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const st = StyleSheet.create({
  card: { flexDirection: 'row', backgroundColor: C.card, borderRadius: 18, borderWidth: 1, borderColor: C.line, overflow: 'hidden' },
  stripe: { width: 6 },
  code: { fontSize: 18, fontWeight: '800', color: C.ink },
  title: { fontSize: 15, color: C.ink, fontWeight: '500' },
  badge: { backgroundColor: C.primarySoft, paddingHorizontal: 10, paddingVertical: 4, borderRadius: 20 },
  badgeText: { fontSize: 12, fontWeight: '700', color: C.primary },
  track: { flex: 1, height: 6, borderRadius: 3, backgroundColor: C.line, overflow: 'hidden' },
  fill: { height: 6, borderRadius: 3 },
  meta: { fontSize: 12, color: C.ink2, fontWeight: '600' },
});
