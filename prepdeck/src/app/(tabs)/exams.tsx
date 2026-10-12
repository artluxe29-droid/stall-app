import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { router } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Bar, C, Empty, F, GRADIENT, Pill, s, shadow, Tap, Txt, Button } from '../../components/ui';
import { formatExam, relativeDays } from '../../lib/dates';
import { sessionsNeeded } from '../../lib/planner';
import { useStore } from '../../lib/store';
import type { Course } from '../../lib/types';
import { useNow } from '../../lib/useNow';

const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

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

  const card = (c: Course, dim = false) => {
    const qs = state.questions.filter(q => q.courseId === c.id).length;
    const pct = coverage(c);
    const rel = relativeDays(c.examAt);
    const urgent = rel === 'today' || rel === 'tomorrow';
    const d = new Date(c.examAt);
    return (
      <Tap key={c.id} onPress={() => router.push(`/course/${c.id}`)} scale={0.98} style={[st.card, shadow, dim && { opacity: 0.55 }]}>
        <View style={[st.date, { backgroundColor: `${c.color}18` }]}>
          <Text style={[st.dateMonth, { color: c.color }]}>{MONTHS[d.getMonth()]}</Text>
          <Text style={[st.dateDay, { color: c.color }]}>{d.getDate()}</Text>
        </View>
        <View style={{ flex: 1, gap: 3 }}>
          <View style={s.between}>
            <Txt v="h2">{c.code}</Txt>
            <Pill label={rel} color={urgent ? C.red : C.primary} bg={urgent ? C.redSoft : C.primarySoft} />
          </View>
          <Txt v="bodyStrong" numberOfLines={1} style={{ color: C.ink2, fontFamily: F.semibold }}>{c.title}</Txt>
          <Txt v="caption" style={{ fontFamily: F.medium }}>{formatExam(c.examAt).split(', ')[1]}{c.venue ? `  ·  ${c.venue}` : ''}</Txt>
          <View style={[s.row, { marginTop: 8 }]}>
            <Bar value={pct} color={c.color} height={7} />
            <Text style={st.pct}>{Math.round(pct * 100)}%</Text>
          </View>
          <View style={[s.row, { gap: 14, marginTop: 4 }]}>
            <Meta icon="list" text={`${c.topics.length} topics`} />
            <Meta icon="help-circle" text={`${qs} questions`} />
          </View>
        </View>
      </Tap>
    );
  };

  return (
    <SafeAreaView style={s.screen} edges={['top']}>
      <ScrollView contentContainerStyle={s.content} showsVerticalScrollIndicator={false}>
        <View style={s.between}>
          <View>
            <Txt v="title">Exams</Txt>
            <Txt v="small">{upcoming.length ? `${upcoming.length} coming up` : 'Your timetable'}</Txt>
          </View>
          <Tap onPress={() => router.push('/course/new')} accessibilityRole="button" accessibilityLabel="Add exam">
            <LinearGradient colors={GRADIENT.primary} style={st.add}><Ionicons name="add" size={26} color="#fff" /></LinearGradient>
          </Tap>
        </View>
        {state.courses.length === 0 ? (
          <Empty icon="calendar" title="No exams yet" body="Add each course with its exam date and topics, and your plan builds itself.">
            <Button title="Add an exam" icon="add" onPress={() => router.push('/course/new')} style={{ alignSelf: 'stretch' }} />
          </Empty>
        ) : (
          <>
            {upcoming.map(c => card(c))}
            {past.length > 0 && <Txt v="overline" style={{ marginTop: 8 }}>Finished</Txt>}
            {past.map(c => card(c, true))}
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function Meta({ icon, text }: { icon: 'list' | 'help-circle'; text: string }) {
  return (
    <View style={[s.row, { gap: 4 }]}>
      <Ionicons name={icon} size={13} color={C.ink3} />
      <Txt v="caption" style={{ color: C.ink2 }}>{text}</Txt>
    </View>
  );
}

const st = StyleSheet.create({
  card: { flexDirection: 'row', gap: 14, backgroundColor: C.card, borderRadius: 24, padding: 16 },
  date: { width: 58, borderRadius: 18, alignItems: 'center', justifyContent: 'center', paddingVertical: 10, alignSelf: 'flex-start' },
  dateMonth: { fontFamily: F.bold, fontSize: 11, letterSpacing: 1 },
  dateDay: { fontFamily: F.extrabold, fontSize: 24, lineHeight: 28 },
  pct: { fontFamily: F.bold, fontSize: 12, color: C.ink2, minWidth: 34, textAlign: 'right' },
  add: { width: 48, height: 48, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
});
