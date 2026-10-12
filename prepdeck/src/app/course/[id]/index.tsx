import { Ionicons } from '@expo/vector-icons';
import { router, Stack, useLocalSearchParams } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { CountdownBlocks } from '../../../components/Countdown';
import { Button, C, Card, Empty, H2, Muted, s } from '../../../components/ui';
import { confirm } from '../../../lib/confirm';
import { formatExam } from '../../../lib/dates';
import { sessionsNeeded } from '../../../lib/planner';
import { useStore } from '../../../lib/store';
import type { Confidence } from '../../../lib/types';
import { useNow } from '../../../lib/useNow';

const LEVELS: { v: Confidence; label: string; color: string; bg: string }[] = [
  { v: 1, label: 'Shaky', color: C.red, bg: C.redSoft },
  { v: 2, label: 'Okay', color: '#B45309', bg: C.amberSoft },
  { v: 3, label: 'Solid', color: C.green, bg: C.greenSoft },
];

export default function CourseDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { state, setConfidence, deleteCourse, deleteQuestion } = useStore();
  const now = useNow();
  const course = state.courses.find(c => c.id === id);
  if (!course) return <View style={s.screen}><Muted style={{ padding: 16 }}>This course was deleted.</Muted></View>;

  const questions = state.questions.filter(q => q.courseId === course.id);
  const upcoming = new Date(course.examAt).getTime() > now;

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <Stack.Screen options={{
        title: course.code,
        headerRight: () => (
          <Pressable onPress={() => router.push({ pathname: '/course/new', params: { id: course.id } })} hitSlop={10}>
            <Text style={{ color: C.primary, fontWeight: '700', fontSize: 16 }}>Edit</Text>
          </Pressable>
        ),
      }} />

      <Card>
        <Text style={st.title}>{course.title}</Text>
        <Muted style={{ marginBottom: 12 }}>{formatExam(course.examAt)}{course.venue ? ` · ${course.venue}` : ''}</Muted>
        {upcoming ? <CountdownBlocks target={course.examAt} color={C.primary} small /> : <Muted>This exam is done.</Muted>}
      </Card>

      <Card>
        <H2>Topics</H2>
        <Muted style={{ fontSize: 13, marginBottom: 6 }}>Rate how well you know each topic. Shaky topics get more sessions in your plan.</Muted>
        {course.topics.length === 0 && <Muted>No topics yet. Tap Edit to add them.</Muted>}
        {course.topics.map(t => {
          const done = state.sessions.filter(x => x.topicId === t.id).length;
          const need = sessionsNeeded(t, course);
          return (
            <View key={t.id} style={st.topic}>
              <View style={{ flex: 1 }}>
                <Text style={st.topicName}>{t.name}</Text>
                <Muted style={{ fontSize: 12 }}>{Math.min(done, need)}/{need} sessions done</Muted>
              </View>
              <View style={st.seg}>
                {LEVELS.map(l => (
                  <Pressable key={l.v} onPress={() => setConfidence(course.id, t.id, l.v)}
                    style={[st.segBtn, t.confidence === l.v && { backgroundColor: l.bg }]}>
                    <Text style={[st.segText, t.confidence === l.v && { color: l.color }]}>{l.label}</Text>
                  </Pressable>
                ))}
              </View>
            </View>
          );
        })}
      </Card>

      <Card>
        <View style={[s.row, { justifyContent: 'space-between' }]}>
          <H2>Past questions</H2>
          <Text style={st.count}>{questions.length}</Text>
        </View>
        <View style={[s.row, { marginTop: 12 }]}>
          <Button title="Paste" icon="clipboard-outline" style={{ flex: 1 }} onPress={() => router.push(`/course/${course.id}/import`)} />
          <Button title="Add one" icon="add" kind="secondary" style={{ flex: 1 }} onPress={() => router.push(`/course/${course.id}/question`)} />
        </View>
        {questions.length > 0 && (
          <Button title="Practise this course" icon="play" kind="ghost" style={{ marginTop: 6 }}
            onPress={() => router.push({ pathname: '/quiz', params: { courseId: course.id, mode: 'practice', count: '10' } })} />
        )}
        {questions.length === 0 ? (
          <View style={{ marginTop: 12 }}><Empty icon="document-text-outline" title="No questions yet" body="Paste a past paper in the simple Q: / A) / Answer: format, or add questions one by one." /></View>
        ) : questions.slice(0, 60).map((q, i) => (
          <View key={q.id} style={st.q}>
            <Text style={st.qNum}>{i + 1}</Text>
            <View style={{ flex: 1 }}>
              <Text style={st.qText} numberOfLines={2}>{q.prompt}</Text>
              <Muted style={{ fontSize: 12 }}>{q.kind === 'mcq' ? 'Multiple choice' : 'Theory'}{q.topic ? ` · ${q.topic}` : ''}{q.year ? ` · ${q.year}` : ''}</Muted>
            </View>
            <Pressable hitSlop={10} accessibilityLabel="Delete question" onPress={() => confirm('Delete question?', q.prompt.slice(0, 80), 'Delete', () => deleteQuestion(q.id))}>
              <Ionicons name="trash-outline" size={18} color={C.ink3} />
            </Pressable>
          </View>
        ))}
        {questions.length > 60 && <Muted style={{ marginTop: 8 }}>+ {questions.length - 60} more</Muted>}
      </Card>

      <Button title="Delete course" kind="danger" icon="trash-outline"
        onPress={() => confirm(`Delete ${course.code}?`, 'Its topics, questions and history will be removed.', 'Delete', () => { deleteCourse(course.id); router.back(); })} />
    </ScrollView>
  );
}

const st = StyleSheet.create({
  title: { fontSize: 20, fontWeight: '800', color: C.ink, marginBottom: 4 },
  topic: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: C.line },
  topicName: { fontSize: 15, fontWeight: '600', color: C.ink },
  seg: { flexDirection: 'row', backgroundColor: C.bg, borderRadius: 10, padding: 3 },
  segBtn: { paddingHorizontal: 9, paddingVertical: 6, borderRadius: 8 },
  segText: { fontSize: 12, fontWeight: '700', color: C.ink3 },
  count: { fontSize: 15, fontWeight: '800', color: C.primary },
  q: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: C.line },
  qNum: { width: 22, fontSize: 13, fontWeight: '700', color: C.ink3 },
  qText: { fontSize: 14, color: C.ink },
});
