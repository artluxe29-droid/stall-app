import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CountdownBlocks } from '../../components/Countdown';
import { Button, C, Card, Dot, Empty, H1, H2, Muted, s } from '../../components/ui';
import { formatDay, formatExam } from '../../lib/dates';
import { sampleState } from '../../lib/sample';
import { useStore } from '../../lib/store';
import type { PlanTask } from '../../lib/types';
import { useNow } from '../../lib/useNow';
import { usePlan } from '../../lib/usePlan';

function greeting() {
  const h = new Date().getHours();
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
}

export default function Today() {
  const { ready, state, toggleSession, replaceAll } = useStore();
  const plan = usePlan();
  const now = useNow();
  const upcoming = state.courses.filter(c => new Date(c.examAt).getTime() > now).sort((a, b) => a.examAt.localeCompare(b.examAt));
  const next = upcoming[0];
  const course = (id: string) => state.courses.find(c => c.id === id);
  const todayPlan = plan.days.find(d => d.date === plan.today);
  const tasks = todayPlan?.tasks ?? [];

  const isDone = (t: PlanTask) =>
    t.kind === 'topic' ? state.sessions.some(x => x.topicId === t.topicId && x.date === plan.today)
      : t.kind === 'mock' ? state.mocksDone.some(m => m.courseId === t.courseId && m.date === plan.today)
        : false;
  const doneCount = tasks.filter(isDone).length;

  const onTask = (t: PlanTask) => {
    if (t.kind === 'topic') toggleSession(t.courseId, t.topicId);
    else if (t.kind === 'mock') router.push({ pathname: '/quiz', params: { courseId: t.courseId, mode: 'mock', count: '20' } });
    else router.push({ pathname: '/quiz', params: { courseId: 'all', mode: 'review', count: '50' } });
  };

  if (!ready) return <View style={s.screen} />;

  return (
    <SafeAreaView style={s.screen} edges={['top']}>
      <ScrollView contentContainerStyle={s.content}>
        <View style={[s.row, { justifyContent: 'space-between' }]}>
          <View>
            <Muted>{greeting()}{state.settings.name ? `, ${state.settings.name}` : ''}</Muted>
            <H1>Your exam prep</H1>
          </View>
          <Pressable onPress={() => router.push('/settings')} hitSlop={12} accessibilityLabel="Settings">
            <Ionicons name="settings-outline" size={24} color={C.ink2} />
          </Pressable>
        </View>

        {state.courses.length === 0 ? (
          <Empty icon="school-outline" title="Add your exams to get started" body="Enter each course, its exam date and its topics. PrepDeck builds a daily revision plan and counts down to every paper.">
            <View style={{ gap: 10, alignSelf: 'stretch' }}>
              <Button title="Add your first course" icon="add" onPress={() => router.push('/course/new')} />
              <Button title="Try with sample courses" kind="secondary" onPress={() => replaceAll(sampleState(state.settings.name))} />
            </View>
          </Empty>
        ) : next ? (
          <Pressable onPress={() => router.push(`/course/${next.id}`)}>
            <View style={st.hero}>
              <Text style={st.heroLabel}>NEXT EXAM</Text>
              <Text style={st.heroCode}>{next.code}</Text>
              <Text style={st.heroTitle}>{next.title}</Text>
              <View style={{ height: 14 }} />
              <CountdownBlocks target={next.examAt} />
              <View style={[s.row, { marginTop: 14 }]}>
                <Ionicons name="time-outline" size={15} color="#C7D2FE" />
                <Text style={st.heroMeta}>{formatExam(next.examAt)}{next.venue ? ` · ${next.venue}` : ''}</Text>
              </View>
            </View>
          </Pressable>
        ) : (
          <Card><H2>All exams done</H2><Muted>Add next semester’s courses when you have the timetable.</Muted></Card>
        )}

        {tasks.length > 0 && (
          <Card>
            <View style={[s.row, { justifyContent: 'space-between' }]}>
              <H2>Today’s plan</H2>
              <Text style={st.count}>{doneCount}/{tasks.length} done</Text>
            </View>
            <View style={st.track}><View style={[st.fill, { width: `${(doneCount / tasks.length) * 100}%` }]} /></View>
            {tasks.map(t => {
              const done = isDone(t);
              const c = t.kind !== 'review' ? course(t.courseId) : undefined;
              const action = t.kind !== 'topic';
              return (
                <Pressable key={t.key} onPress={() => onTask(t)} style={st.task} accessibilityRole={action ? 'button' : 'checkbox'} accessibilityState={{ checked: done }}>
                  {action ? (
                    <View style={[st.check, { borderColor: done ? C.green : C.amber, backgroundColor: done ? C.green : C.amberSoft }]}>
                      <Ionicons name={done ? 'checkmark' : t.kind === 'mock' ? 'timer-outline' : 'refresh'} size={15} color={done ? '#fff' : '#B45309'} />
                    </View>
                  ) : (
                    <View style={[st.check, done && { backgroundColor: C.green, borderColor: C.green }]}>
                      {done ? <Ionicons name="checkmark" size={16} color="#fff" /> : null}
                    </View>
                  )}
                  <View style={{ flex: 1 }}>
                    <Text style={[st.taskText, done && st.taskDone]}>{t.label}</Text>
                    {c ? (
                      <View style={[s.row, { gap: 6, marginTop: 2 }]}>
                        <Dot color={c.color} size={8} />
                        <Text style={st.taskSub}>{c.code}{t.kind === 'topic' ? ' · revise, then tick' : ''}</Text>
                      </View>
                    ) : <Text style={st.taskSub}>Spaced review of questions you missed</Text>}
                  </View>
                  {action && !done ? <Ionicons name="chevron-forward" size={18} color={C.ink3} /> : null}
                </Pressable>
              );
            })}
          </Card>
        )}

        {plan.unscheduled > 0 && (
          <Card style={{ backgroundColor: C.amberSoft, borderColor: '#FCD34D' }}>
            <View style={s.row}>
              <Ionicons name="warning-outline" size={20} color="#B45309" />
              <Text style={{ flex: 1, color: '#78350F', fontSize: 14 }}>
                {plan.unscheduled} revision session{plan.unscheduled === 1 ? '' : 's'} won’t fit before your exams. Add more sessions per day in Settings.
              </Text>
            </View>
          </Card>
        )}

        {plan.days.length > 1 && (
          <Card>
            <H2>Coming up</H2>
            {plan.days.slice(1, 4).map(d => (
              <View key={d.date} style={st.dayRow}>
                <Text style={st.dayName}>{formatDay(d.date)}</Text>
                <View style={{ flex: 1, gap: 4 }}>
                  {d.tasks.length === 0 ? <Muted>Rest day</Muted> : d.tasks.map(t => (
                    <View key={t.key} style={[s.row, { gap: 6 }]}>
                      <Dot color={t.kind === 'review' ? C.amber : course(t.courseId)?.color ?? C.ink3} size={7} />
                      <Text style={st.upcoming} numberOfLines={1}>{t.label}</Text>
                    </View>
                  ))}
                </View>
              </View>
            ))}
          </Card>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const st = StyleSheet.create({
  hero: { backgroundColor: C.hero, borderRadius: 22, padding: 18 },
  heroLabel: { color: '#A5B4FC', fontSize: 12, fontWeight: '700', letterSpacing: 1.2 },
  heroCode: { color: '#fff', fontSize: 30, fontWeight: '800', marginTop: 6, letterSpacing: -0.5 },
  heroTitle: { color: '#C7D2FE', fontSize: 15, marginTop: 2 },
  heroMeta: { color: '#C7D2FE', fontSize: 13 },
  count: { fontSize: 13, fontWeight: '700', color: C.primary },
  track: { height: 6, borderRadius: 3, backgroundColor: C.primarySoft, marginTop: 10, marginBottom: 6, overflow: 'hidden' },
  fill: { height: 6, borderRadius: 3, backgroundColor: C.primary },
  task: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 11, borderBottomWidth: 1, borderBottomColor: C.line },
  check: { width: 26, height: 26, borderRadius: 8, borderWidth: 2, borderColor: C.line, alignItems: 'center', justifyContent: 'center' },
  taskText: { fontSize: 15, fontWeight: '600', color: C.ink },
  taskDone: { color: C.ink3, textDecorationLine: 'line-through' },
  taskSub: { fontSize: 12, color: C.ink2 },
  dayRow: { flexDirection: 'row', gap: 12, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: C.line },
  dayName: { width: 86, fontSize: 13, fontWeight: '700', color: C.ink2 },
  upcoming: { fontSize: 13, color: C.ink, flex: 1 },
});
