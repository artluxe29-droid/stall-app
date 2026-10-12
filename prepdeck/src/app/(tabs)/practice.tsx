import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { router } from 'expo-router';
import { useState, type ReactNode } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Button, C, Chip, Empty, F, GRADIENT, s, shadow, Tap, Txt, type IconName } from '../../components/ui';
import { dayKey } from '../../lib/dates';
import { dueForReview } from '../../lib/srs';
import { useStore } from '../../lib/store';

export default function Practice() {
  const { state } = useStore();
  const [courseId, setCourseId] = useState<string>('all');
  const [mockCount, setMockCount] = useState(20);
  const pool = state.questions.filter(q => courseId === 'all' || q.courseId === courseId);
  const mcqs = pool.filter(q => q.kind === 'mcq').length;
  const due = dueForReview(state.questions, state.cards, dayKey(), courseId === 'all' ? undefined : courseId).length;
  const firstCourse = state.courses[0];

  const go = (mode: string, count: number) => router.push({ pathname: '/quiz', params: { courseId, mode, count: String(count) } });

  return (
    <SafeAreaView style={s.screen} edges={['top']}>
      <ScrollView contentContainerStyle={s.content} showsVerticalScrollIndicator={false}>
        <View>
          <Txt v="title">Practice</Txt>
          <Txt v="small">{state.questions.length} past questions in your deck</Txt>
        </View>
        {state.questions.length === 0 ? (
          <Empty icon="document-text" title="No past questions yet" body="Paste past questions into a course and they become quizzes and timed mock exams.">
            {firstCourse ? (
              <Button title={`Add questions to ${firstCourse.code}`} icon="add" style={{ alignSelf: 'stretch' }} onPress={() => router.push(`/course/${firstCourse.id}/import`)} />
            ) : (
              <Button title="Add a course first" icon="add" style={{ alignSelf: 'stretch' }} onPress={() => router.push('/course/new')} />
            )}
          </Empty>
        ) : (
          <>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8, paddingRight: 20 }} style={{ marginHorizontal: -20, paddingLeft: 20 }}>
              <Chip label={`All · ${state.questions.length}`} active={courseId === 'all'} onPress={() => setCourseId('all')} />
              {state.courses.map(c => (
                <Chip key={c.id} label={`${c.code} · ${state.questions.filter(q => q.courseId === c.id).length}`} active={courseId === c.id} color={c.color} onPress={() => setCourseId(c.id)} />
              ))}
            </ScrollView>

            <ModeCard icon="flash" grad={GRADIENT.primary} title="Quick practice" tag="10 questions"
              body="Weakest questions first, with the answer straight after each one." disabled={pool.length === 0} onPress={() => go('practice', 10)} />

            <ModeCard icon="timer" grad={GRADIENT.warm} title="Timed mock exam" tag={`${Math.min(mockCount, mcqs)} min`}
              body="Exam conditions: 1 minute per question, marked at the end." disabled={mcqs === 0} onPress={() => go('mock', Math.min(mockCount, mcqs))}>
              <View style={[s.row, { gap: 8, marginTop: 14, flexWrap: 'wrap' }]}>
                {[...[10, 20, 40].filter(n => n < mcqs), mcqs].map(n => (
                  <Chip key={n} label={n === mcqs ? `All ${n}` : `${n} Qs`} active={Math.min(mockCount, mcqs) === n} color={C.accent} onPress={() => setMockCount(n)} />
                ))}
              </View>
            </ModeCard>

            <ModeCard icon="refresh" grad={GRADIENT.green} title="Review mistakes" tag={due ? `${due} due` : 'All clear'}
              body={due ? 'Questions you missed come back on a schedule until you master them.' : 'Nothing due right now. Missed questions return here 1, 2, 4, 7 and 14 days later.'}
              disabled={due === 0} onPress={() => go('review', due)} />
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function ModeCard({ icon, grad, title, tag, body, onPress, disabled, children }: {
  icon: IconName; grad: readonly [string, string, ...string[]]; title: string; tag: string; body: string; onPress: () => void; disabled?: boolean; children?: ReactNode;
}) {
  return (
    <Tap onPress={onPress} disabled={disabled} scale={0.98} accessibilityRole="button" accessibilityLabel={title} style={[st.mode, shadow]}>
      <View style={s.row}>
        <LinearGradient colors={grad} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={st.icon}>
          <Ionicons name={icon} size={26} color="#fff" />
        </LinearGradient>
        <View style={{ flex: 1 }}>
          <Txt v="h2">{title}</Txt>
          <Text style={[st.tag, { color: grad[grad.length - 1] }]}>{tag}</Text>
        </View>
        <View style={st.go}><Ionicons name="arrow-forward" size={18} color={C.ink} /></View>
      </View>
      <Txt v="small" style={{ marginTop: 12 }}>{body}</Txt>
      {children}
    </Tap>
  );
}

const st = StyleSheet.create({
  mode: { backgroundColor: C.card, borderRadius: 26, padding: 18 },
  icon: { width: 54, height: 54, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  tag: { fontFamily: F.bold, fontSize: 13, marginTop: 2 },
  go: { width: 38, height: 38, borderRadius: 13, backgroundColor: C.bg, alignItems: 'center', justifyContent: 'center' },
});
