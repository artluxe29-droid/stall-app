import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { router, Stack, useLocalSearchParams } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { CountdownBlocks } from '../../../components/Countdown';
import { Button, C, Card, Empty, F, Pill, s, Tap, Txt } from '../../../components/ui';
import { confirm } from '../../../lib/confirm';
import { formatExam, relativeDays } from '../../../lib/dates';
import { sessionsNeeded } from '../../../lib/planner';
import { useStore } from '../../../lib/store';
import type { Confidence } from '../../../lib/types';
import { useNow } from '../../../lib/useNow';

const LEVELS: { v: Confidence; label: string; color: string; bg: string }[] = [
  { v: 1, label: 'Shaky', color: C.red, bg: C.redSoft },
  { v: 2, label: 'Okay', color: '#B45309', bg: C.amberSoft },
  { v: 3, label: 'Solid', color: C.green, bg: C.greenSoft },
];

/** Darkens a #RRGGBB colour, for the second stop of a course's gradient. */
function shade(hex: string, f = 0.55) {
  const n = parseInt(hex.slice(1), 16);
  const ch = (x: number) => Math.round(x * f).toString(16).padStart(2, '0');
  return `#${ch((n >> 16) & 255)}${ch((n >> 8) & 255)}${ch(n & 255)}`;
}

export default function CourseDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { state, setConfidence, deleteCourse, deleteQuestion } = useStore();
  const now = useNow();
  const course = state.courses.find(c => c.id === id);
  if (!course) return <View style={s.screen}><Txt style={{ padding: 20 }}>This course was deleted.</Txt></View>;

  const questions = state.questions.filter(q => q.courseId === course.id);
  const upcoming = new Date(course.examAt).getTime() > now;

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content} showsVerticalScrollIndicator={false}>
      <Stack.Screen options={{
        title: '',
        headerRight: () => (
          <Tap onPress={() => router.push({ pathname: '/course/new', params: { id: course.id } })} hitSlop={10} accessibilityRole="button">
            <Text style={{ color: C.primary, fontFamily: F.bold, fontSize: 16 }}>Edit</Text>
          </Tap>
        ),
      }} />

      <LinearGradient colors={[course.color, shade(course.color)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={st.hero}>
        <View style={st.orb} />
        <Pill label={upcoming ? relativeDays(course.examAt) : 'Done'} color="#fff" bg="rgba(255,255,255,0.2)" icon="time" />
        <Text style={st.code}>{course.code}</Text>
        <Text style={st.title}>{course.title}</Text>
        <Text style={st.meta}>{formatExam(course.examAt)}{course.venue ? `  ·  ${course.venue}` : ''}</Text>
        {upcoming ? <View style={{ marginTop: 16 }}><CountdownBlocks target={course.examAt} /></View> : null}
      </LinearGradient>

      <Card>
        <Txt v="h2">Topics</Txt>
        <Txt v="small" style={{ marginTop: 4, marginBottom: 6 }}>How well do you know each one? Shaky topics get more sessions.</Txt>
        {course.topics.length === 0 && <Txt>No topics yet. Tap Edit to add them.</Txt>}
        {course.topics.map(t => {
          const done = Math.min(state.sessions.filter(x => x.topicId === t.id).length, sessionsNeeded(t, course));
          const need = sessionsNeeded(t, course);
          return (
            <View key={t.id} style={st.topic}>
              <View style={s.between}>
                <Txt v="h3" style={{ flex: 1 }}>{t.name}</Txt>
                <View style={s.row}>
                  {Array.from({ length: need }, (_, i) => (
                    <View key={i} style={[st.pip, i < done && { backgroundColor: course.color }]} />
                  ))}
                </View>
              </View>
              <View style={st.seg}>
                {LEVELS.map(l => {
                  const on = t.confidence === l.v;
                  return (
                    <Tap key={l.v} onPress={() => setConfidence(course.id, t.id, l.v)} style={[st.segBtn, on && { backgroundColor: l.bg }]} accessibilityRole="button" accessibilityState={{ selected: on }}>
                      <Text style={[st.segText, on && { color: l.color }]}>{l.label}</Text>
                    </Tap>
                  );
                })}
              </View>
            </View>
          );
        })}
      </Card>

      <Card>
        <View style={s.between}>
          <Txt v="h2">Past questions</Txt>
          <Pill label={`${questions.length}`} />
        </View>
        <View style={[s.row, { marginTop: 14 }]}>
          <Button title="Paste" icon="clipboard" small style={{ flex: 1 }} onPress={() => router.push(`/course/${course.id}/import`)} />
          <Button title="Add one" icon="add" kind="secondary" small style={{ flex: 1 }} onPress={() => router.push(`/course/${course.id}/question`)} />
        </View>
        {questions.length > 0 && (
          <Tap style={st.practise} onPress={() => router.push({ pathname: '/quiz', params: { courseId: course.id, mode: 'practice', count: '10' } })} accessibilityRole="button">
            <Ionicons name="play-circle" size={22} color={C.primary} />
            <Text style={{ fontFamily: F.bold, color: C.primary, fontSize: 15 }}>Practise {course.code} now</Text>
          </Tap>
        )}
        {questions.length === 0 ? (
          <View style={{ marginTop: 14 }}>
            <Empty icon="document-text" title="No questions yet" body="Paste a past paper in the Q: / A) / Answer: format, or add questions one by one." />
          </View>
        ) : questions.slice(0, 60).map((q, i) => (
          <View key={q.id} style={st.q}>
            <View style={st.qNum}><Text style={st.qNumText}>{i + 1}</Text></View>
            <View style={{ flex: 1 }}>
              <Txt v="bodyStrong" numberOfLines={2} style={{ fontSize: 14 }}>{q.prompt}</Txt>
              <Txt v="caption" style={{ fontFamily: F.medium }}>{q.kind === 'mcq' ? 'Multiple choice' : 'Theory'}{q.topic ? `  ·  ${q.topic}` : ''}{q.year ? `  ·  ${q.year}` : ''}</Txt>
            </View>
            <Tap hitSlop={12} accessibilityLabel="Delete question" onPress={() => confirm('Delete question?', q.prompt.slice(0, 80), 'Delete', () => deleteQuestion(q.id))}>
              <Ionicons name="trash-outline" size={18} color={C.ink3} />
            </Tap>
          </View>
        ))}
        {questions.length > 60 && <Txt v="small" style={{ marginTop: 8 }}>+ {questions.length - 60} more</Txt>}
      </Card>

      <Button title="Delete course" kind="danger" icon="trash-outline"
        onPress={() => confirm(`Delete ${course.code}?`, 'Its topics, questions and history will be removed.', 'Delete', () => { deleteCourse(course.id); router.back(); })} />
    </ScrollView>
  );
}

const st = StyleSheet.create({
  hero: { borderRadius: 28, padding: 20, overflow: 'hidden' },
  orb: { position: 'absolute', width: 200, height: 200, borderRadius: 100, backgroundColor: '#fff', opacity: 0.1, top: -70, right: -60 },
  code: { fontFamily: F.extrabold, fontSize: 34, color: '#fff', marginTop: 14, letterSpacing: -1 },
  title: { fontFamily: F.semibold, fontSize: 16, color: 'rgba(255,255,255,0.92)' },
  meta: { fontFamily: F.medium, fontSize: 13, color: 'rgba(255,255,255,0.8)', marginTop: 6 },
  topic: { paddingVertical: 14, gap: 10, borderBottomWidth: 1, borderBottomColor: C.line },
  pip: { width: 10, height: 10, borderRadius: 4, backgroundColor: C.line },
  seg: { flexDirection: 'row', backgroundColor: C.bg, borderRadius: 14, padding: 4 },
  segBtn: { flex: 1, alignItems: 'center', paddingVertical: 9, borderRadius: 11 },
  segText: { fontFamily: F.bold, fontSize: 13, color: C.ink3 },
  practise: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, marginTop: 12, paddingVertical: 12, borderRadius: 16, backgroundColor: C.primarySoft },
  q: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: C.line },
  qNum: { width: 30, height: 30, borderRadius: 10, backgroundColor: C.bg, alignItems: 'center', justifyContent: 'center' },
  qNumText: { fontFamily: F.bold, fontSize: 12, color: C.ink2 },
});
