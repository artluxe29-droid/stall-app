import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useState, type ReactNode } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { C, Chip, Empty, H1, H2, Muted, s, type IconName, Button } from '../../components/ui';
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
      <ScrollView contentContainerStyle={s.content}>
        <H1>Practice</H1>
        {state.questions.length === 0 ? (
          <Empty icon="document-text-outline" title="No past questions yet" body="Paste past questions into a course and they become quizzes and timed mock exams.">
            {firstCourse ? (
              <Button title={`Add questions to ${firstCourse.code}`} icon="add" onPress={() => router.push(`/course/${firstCourse.id}/import`)} />
            ) : (
              <Button title="Add a course first" icon="add" onPress={() => router.push('/course/new')} />
            )}
          </Empty>
        ) : (
          <>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
              <Chip label={`All (${state.questions.length})`} active={courseId === 'all'} onPress={() => setCourseId('all')} />
              {state.courses.map(c => (
                <Chip key={c.id} label={`${c.code} (${state.questions.filter(q => q.courseId === c.id).length})`} active={courseId === c.id} color={c.color} onPress={() => setCourseId(c.id)} />
              ))}
            </ScrollView>

            <ModeCard icon="flash-outline" color={C.primary} bg={C.primarySoft} title="Quick practice"
              body={`10 questions, weakest first. See the answer straight away. ${pool.length} available.`}
              disabled={pool.length === 0} onPress={() => go('practice', 10)} />

            <ModeCard icon="timer-outline" color="#B45309" bg={C.amberSoft} title="Timed mock exam"
              body={`Multiple choice under exam conditions: 1 minute per question, marked at the end. ${mcqs} available.`}
              disabled={mcqs === 0} onPress={() => go('mock', Math.min(mockCount, mcqs))}>
              <View style={[s.row, { gap: 6, marginTop: 10 }]}>
                {[...[10, 20, 40].filter(n => n < mcqs), mcqs].map(n => (
                  <Chip key={n} label={n === mcqs ? `All ${n}` : `${n} Qs`} active={Math.min(mockCount, mcqs) === n} color={C.amber} onPress={() => setMockCount(n)} />
                ))}
              </View>
            </ModeCard>

            <ModeCard icon="refresh-outline" color={C.green} bg={C.greenSoft} title="Review mistakes"
              body={due ? `${due} question${due === 1 ? '' : 's'} you missed ${due === 1 ? 'is' : 'are'} due again today.` : 'Nothing due. Questions you miss come back here on a schedule until you master them.'}
              disabled={due === 0} onPress={() => go('review', due)} />
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function ModeCard({ icon, color, bg, title, body, onPress, disabled, children }: {
  icon: IconName; color: string; bg: string; title: string; body: string; onPress: () => void; disabled?: boolean; children?: ReactNode;
}) {
  return (
    <Pressable onPress={onPress} disabled={disabled} style={[st.mode, disabled && { opacity: 0.5 }]}>
      <View style={[st.modeIcon, { backgroundColor: bg }]}><Ionicons name={icon} size={24} color={color} /></View>
      <View style={{ flex: 1 }}>
        <H2>{title}</H2>
        <Muted style={{ fontSize: 13 }}>{body}</Muted>
        {children}
      </View>
      <Ionicons name="chevron-forward" size={20} color={C.ink3} />
    </Pressable>
  );
}

const st = StyleSheet.create({
  mode: { flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: C.card, borderRadius: 18, padding: 16, borderWidth: 1, borderColor: C.line },
  modeIcon: { width: 48, height: 48, borderRadius: 14, alignItems: 'center', justifyContent: 'center' },
});
