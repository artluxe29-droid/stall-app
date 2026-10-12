import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { router } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CountdownBlocks } from '../../components/Countdown';
import { Button, C, Card, Dot, F, GRADIENT, IconBubble, IconButton, Pill, Ring, s, shadow, Tap, Txt, type IconName } from '../../components/ui';
import { formatDay, formatExam, relativeDays } from '../../lib/dates';
import { sampleState } from '../../lib/sample';
import { streak } from '../../lib/stats';
import { useStore } from '../../lib/store';
import type { PlanTask } from '../../lib/types';
import { useNow } from '../../lib/useNow';
import { usePlan } from '../../lib/usePlan';

function greeting() {
  const h = new Date().getHours();
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
}

function cheer(done: number, total: number) {
  if (total === 0) return 'Nothing planned today.';
  if (done === total) return 'All done. Brilliant work today!';
  if (done === 0) return 'Start with the first one. Small wins add up.';
  return `${total - done} to go. Keep the momentum.`;
}

export default function Today() {
  const { ready, state, toggleSession, replaceAll } = useStore();
  const plan = usePlan();
  const now = useNow();
  if (!ready) return <View style={s.screen} />;
  if (state.courses.length === 0) return <Welcome onSample={() => replaceAll(sampleState(state.settings.name))} />;

  const upcoming = state.courses.filter(c => new Date(c.examAt).getTime() > now).sort((a, b) => a.examAt.localeCompare(b.examAt));
  const next = upcoming[0];
  const course = (id: string) => state.courses.find(c => c.id === id);
  const tasks = plan.days.find(d => d.date === plan.today)?.tasks ?? [];
  const isDone = (t: PlanTask) =>
    t.kind === 'topic' ? state.sessions.some(x => x.topicId === t.topicId && x.date === plan.today)
      : t.kind === 'mock' ? state.mocksDone.some(m => m.courseId === t.courseId && m.date === plan.today)
        : false;
  const done = tasks.filter(isDone).length;
  const days = streak(state);

  const onTask = (t: PlanTask) => {
    if (t.kind === 'topic') toggleSession(t.courseId, t.topicId);
    else if (t.kind === 'mock') router.push({ pathname: '/quiz', params: { courseId: t.courseId, mode: 'mock', count: '20' } });
    else router.push({ pathname: '/quiz', params: { courseId: 'all', mode: 'review', count: '50' } });
  };

  return (
    <SafeAreaView style={s.screen} edges={['top']}>
      <ScrollView contentContainerStyle={s.content} showsVerticalScrollIndicator={false}>
        <View style={s.between}>
          <View style={{ flex: 1 }}>
            <Txt v="small">{greeting()}{state.settings.name ? ',' : ''}</Txt>
            <Txt v="title" numberOfLines={1}>{state.settings.name || 'Ready to revise?'}</Txt>
          </View>
          <View style={[st.streak, shadow]}>
            <Ionicons name="flame" size={18} color={C.accent} />
            <Text style={st.streakNum}>{days}</Text>
          </View>
          <IconButton icon="settings-outline" label="Settings" onPress={() => router.push('/settings')} />
        </View>

        {next ? (
          <Tap onPress={() => router.push(`/course/${next.id}`)} scale={0.98}>
            <LinearGradient colors={GRADIENT.hero} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={st.hero}>
              <View style={[st.orb, { width: 180, height: 180, top: -60, right: -50 }]} />
              <View style={[st.orb, { width: 110, height: 110, bottom: -40, left: -30, opacity: 0.08 }]} />
              <View style={s.between}>
                <Pill label="Next exam" icon="school" color="#fff" bg="rgba(255,255,255,0.18)" />
                <Pill label={relativeDays(next.examAt)} color={C.hero} bg="#fff" />
              </View>
              <Text style={st.heroCode}>{next.code}</Text>
              <Text style={st.heroTitle} numberOfLines={1}>{next.title}</Text>
              <View style={{ height: 18 }} />
              <CountdownBlocks target={next.examAt} />
              <View style={[s.row, { marginTop: 16, gap: 6 }]}>
                <Ionicons name="time-outline" size={15} color="rgba(255,255,255,0.8)" />
                <Text style={st.heroMeta}>{formatExam(next.examAt)}{next.venue ? `  ·  ${next.venue}` : ''}</Text>
              </View>
            </LinearGradient>
          </Tap>
        ) : (
          <Card>
            <Txt v="h2">All exams done</Txt>
            <Txt>Add next semester’s courses when the timetable is out.</Txt>
          </Card>
        )}

        {tasks.length > 0 && (
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            <View style={[s.row, { padding: 18, gap: 16 }]}>
              <Ring value={done / tasks.length} size={76} stroke={9}>
                <Text style={st.ringNum}>{done}/{tasks.length}</Text>
              </Ring>
              <View style={{ flex: 1 }}>
                <Txt v="overline">Today’s plan</Txt>
                <Txt v="h2" style={{ marginTop: 2 }}>{done === tasks.length ? 'Plan complete' : `${tasks.length} things to do`}</Txt>
                <Txt v="small" style={{ marginTop: 2 }}>{cheer(done, tasks.length)}</Txt>
              </View>
            </View>
            {tasks.map(t => {
              const ok = isDone(t);
              const c = t.kind !== 'review' ? course(t.courseId) : undefined;
              const color = c?.color ?? C.amber;
              const action = t.kind !== 'topic';
              return (
                <Tap key={t.key} onPress={() => onTask(t)} scale={0.985} accessibilityRole={action ? 'button' : 'checkbox'} accessibilityState={{ checked: ok }} style={st.task}>
                  {action ? (
                    <IconBubble icon={ok ? 'checkmark' : t.kind === 'mock' ? 'timer' : 'refresh'} color={ok ? '#fff' : C.accent} bg={ok ? C.green : C.accentSoft} size={38} />
                  ) : (
                    <View style={[st.check, ok ? { backgroundColor: C.green, borderColor: C.green } : { borderColor: color }]}>
                      {ok ? <Ionicons name="checkmark" size={20} color="#fff" /> : null}
                    </View>
                  )}
                  <View style={{ flex: 1 }}>
                    <Text style={[st.taskText, ok && st.taskDone]} numberOfLines={2}>{t.label}</Text>
                    <View style={[s.row, { gap: 6, marginTop: 3 }]}>
                      <Dot color={color} size={7} />
                      <Txt v="caption" style={{ fontFamily: F.semibold, color: C.ink2 }}>
                        {c ? c.code : 'All courses'}{t.kind === 'topic' ? '  ·  tap when revised' : t.kind === 'mock' ? '  ·  20 min timed' : '  ·  spaced review'}
                      </Txt>
                    </View>
                  </View>
                  {action && !ok ? <Ionicons name="chevron-forward" size={18} color={C.ink3} /> : null}
                </Tap>
              );
            })}
          </Card>
        )}

        {plan.unscheduled > 0 && (
          <Tap onPress={() => router.push('/settings')}>
            <View style={st.warn}>
              <IconBubble icon="alert" color="#B45309" bg="#FFE7B3" size={36} />
              <Txt v="small" style={{ flex: 1, color: '#7A4A06' }}>
                {plan.unscheduled} session{plan.unscheduled === 1 ? '' : 's'} won’t fit before your exams. Tap to add more study sessions per day.
              </Txt>
            </View>
          </Tap>
        )}

        <View style={s.row}>
          <QuickAction icon="flash" label="Practice" grad={GRADIENT.primary} onPress={() => router.push('/practice')} />
          <QuickAction icon="add" label="Questions" grad={GRADIENT.warm} onPress={() => router.push(next ? `/course/${next.id}/import` : '/exams')} />
          <QuickAction icon="calendar" label="Exams" grad={GRADIENT.green} onPress={() => router.push('/exams')} />
        </View>

        {plan.days.length > 1 && (
          <View style={{ gap: 12 }}>
            <Txt v="h2">Coming up</Txt>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingRight: 20, paddingBottom: 8 }} style={{ marginHorizontal: -20, paddingLeft: 20 }}>
              {plan.days.slice(1, 8).map(d => (
                <Card key={d.date} style={st.dayCard}>
                  <Txt v="overline" style={{ color: C.primary }}>{formatDay(d.date).split(' ')[0]}</Txt>
                  <Txt v="h3" style={{ marginBottom: 10 }}>{formatDay(d.date).split(' ').slice(1).join(' ')}</Txt>
                  {d.tasks.length === 0 ? <Txt v="small">Rest day</Txt> : d.tasks.slice(0, 4).map(t => (
                    <View key={t.key} style={[s.row, { gap: 7, marginBottom: 6 }]}>
                      <Dot color={t.kind === 'review' ? C.amber : course(t.courseId)?.color ?? C.ink3} size={7} />
                      <Txt v="small" numberOfLines={1} style={{ flex: 1, color: C.ink }}>{t.label}</Txt>
                    </View>
                  ))}
                  {d.tasks.length > 4 ? <Txt v="caption">+{d.tasks.length - 4} more</Txt> : null}
                </Card>
              ))}
            </ScrollView>
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function QuickAction({ icon, label, grad, onPress }: { icon: IconName; label: string; grad: readonly [string, string, ...string[]]; onPress: () => void }) {
  return (
    <Tap onPress={onPress} accessibilityRole="button" accessibilityLabel={label} style={[st.quick, shadow]}>
      <LinearGradient colors={grad} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={st.quickIcon}>
        <Ionicons name={icon} size={22} color="#fff" />
      </LinearGradient>
      <Txt v="h3" style={{ fontSize: 14 }}>{label}</Txt>
    </Tap>
  );
}

function Welcome({ onSample }: { onSample: () => void }) {
  const points: [IconName, string, string][] = [
    ['hourglass', 'Live countdowns', 'See exactly how long you have for every paper.'],
    ['calendar', 'A plan that adapts', 'Daily revision tasks, weakest topics first. Miss a day and it reshuffles.'],
    ['flash', 'Past questions', 'Quick practice, timed mock exams, and smart review of what you got wrong.'],
  ];
  return (
    <LinearGradient colors={GRADIENT.hero} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={{ flex: 1 }}>
      <SafeAreaView style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={{ padding: 24, paddingBottom: 40, flexGrow: 1 }}>
          <View style={[st.orb, { width: 260, height: 260, top: -80, right: -90 }]} />
          <View style={st.logo}>
            <Ionicons name="layers" size={30} color={C.primary} />
          </View>
          <Text style={st.welcomeTitle}>Walk into every exam ready.</Text>
          <Text style={st.welcomeSub}>PrepDeck turns your timetable and past questions into a daily plan you can actually follow.</Text>
          <View style={{ gap: 14, marginTop: 28, marginBottom: 32 }}>
            {points.map(([icon, title, body]) => (
              <View key={title} style={st.point}>
                <View style={st.pointIcon}><Ionicons name={icon} size={20} color="#fff" /></View>
                <View style={{ flex: 1 }}>
                  <Text style={st.pointTitle}>{title}</Text>
                  <Text style={st.pointBody}>{body}</Text>
                </View>
              </View>
            ))}
          </View>
          <View style={{ flex: 1 }} />
          <Button title="Add my first exam" icon="add" kind="white" onPress={() => router.push('/course/new')} />
          <Tap onPress={onSample} style={{ marginTop: 14, alignItems: 'center', padding: 8 }} accessibilityRole="button">
            <Text style={st.sampleLink}>Explore with sample courses</Text>
          </Tap>
        </ScrollView>
      </SafeAreaView>
    </LinearGradient>
  );
}

const st = StyleSheet.create({
  streak: { flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: C.card, paddingHorizontal: 12, height: 44, borderRadius: 15 },
  streakNum: { fontFamily: F.extrabold, fontSize: 16, color: C.ink },
  hero: { borderRadius: 28, padding: 20, overflow: 'hidden' },
  orb: { position: 'absolute', borderRadius: 999, backgroundColor: '#fff', opacity: 0.1 },
  heroCode: { fontFamily: F.extrabold, color: '#fff', fontSize: 36, lineHeight: 42, marginTop: 16, letterSpacing: -1 },
  heroTitle: { fontFamily: F.medium, color: 'rgba(255,255,255,0.85)', fontSize: 15.5 },
  heroMeta: { fontFamily: F.medium, color: 'rgba(255,255,255,0.85)', fontSize: 13 },
  ringNum: { fontFamily: F.extrabold, fontSize: 17, color: C.ink },
  task: { flexDirection: 'row', alignItems: 'center', gap: 14, paddingVertical: 14, paddingHorizontal: 18, borderTopWidth: 1, borderTopColor: C.line },
  check: { width: 38, height: 38, borderRadius: 13, borderWidth: 2.5, alignItems: 'center', justifyContent: 'center' },
  taskText: { fontFamily: F.bold, fontSize: 15.5, color: C.ink },
  taskDone: { color: C.ink3, textDecorationLine: 'line-through' },
  warn: { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: C.amberSoft, borderRadius: 20, padding: 14 },
  quick: { flex: 1, backgroundColor: C.card, borderRadius: 22, paddingVertical: 16, alignItems: 'center', gap: 10 },
  quickIcon: { width: 46, height: 46, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  dayCard: { width: 168, padding: 16 },
  logo: { width: 60, height: 60, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', marginTop: 12 },
  welcomeTitle: { fontFamily: F.extrabold, color: '#fff', fontSize: 36, lineHeight: 42, letterSpacing: -1, marginTop: 28 },
  welcomeSub: { fontFamily: F.medium, color: 'rgba(255,255,255,0.85)', fontSize: 16, lineHeight: 24, marginTop: 12 },
  point: { flexDirection: 'row', gap: 14, backgroundColor: 'rgba(255,255,255,0.1)', borderRadius: 20, padding: 16, borderWidth: 1, borderColor: 'rgba(255,255,255,0.14)' },
  pointIcon: { width: 40, height: 40, borderRadius: 14, backgroundColor: 'rgba(255,255,255,0.18)', alignItems: 'center', justifyContent: 'center' },
  pointTitle: { fontFamily: F.bold, color: '#fff', fontSize: 15.5 },
  pointBody: { fontFamily: F.medium, color: 'rgba(255,255,255,0.78)', fontSize: 13.5, lineHeight: 19, marginTop: 2 },
  sampleLink: { fontFamily: F.bold, color: '#fff', fontSize: 15, textDecorationLine: 'underline' },
});
