import { useState } from 'react';
import { Platform, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { Button, C, Card, Chip, F, Field, IconBubble, s, Tap, Txt } from '../components/ui';
import { confirm } from '../lib/confirm';
import { sampleState } from '../lib/sample';
import { DEFAULT_SETTINGS, useStore } from '../lib/store';

const TIMES: [number, number, string][] = [[7, 0, '7am'], [12, 0, '12pm'], [16, 0, '4pm'], [19, 0, '7pm'], [21, 0, '9pm']];

export default function Settings() {
  const { state, updateSettings, replaceAll } = useStore();
  const { settings } = state;
  const [name, setName] = useState(settings.name);

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
      <Card>
        <Field label="Your first name" value={name} onChangeText={setName} onEndEditing={() => updateSettings({ name: name.trim() })} onBlur={() => updateSettings({ name: name.trim() })} placeholder="For your greeting" />
        <Text style={s.label}>Study sessions per day</Text>
        <View style={[s.row, { gap: 14 }]}>
          <Tap style={st.stepper} accessibilityLabel="Fewer sessions" onPress={() => updateSettings({ sessionsPerDay: Math.max(1, settings.sessionsPerDay - 1) })}><Text style={st.stepText}>−</Text></Tap>
          <Text style={st.count}>{settings.sessionsPerDay}</Text>
          <Tap style={st.stepper} accessibilityLabel="More sessions" onPress={() => updateSettings({ sessionsPerDay: Math.min(10, settings.sessionsPerDay + 1) })}><Text style={st.stepText}>+</Text></Tap>
          <Txt v="small" style={{ flex: 1 }}>About 45 minutes each. Your plan reshuffles straight away.</Txt>
        </View>
      </Card>

      <Card>
        <View style={s.between}>
          <View style={[s.row, { flex: 1 }]}>
            <IconBubble icon="notifications" color={C.primary} bg={C.primarySoft} size={40} />
            <Txt v="h2">Daily reminder</Txt>
          </View>
          <Switch value={settings.remindersOn} onValueChange={v => updateSettings({ remindersOn: v })} trackColor={{ true: C.primary, false: C.line }} thumbColor="#fff" />
        </View>
        <Txt v="small" style={{ marginTop: 10, marginBottom: 14 }}>
          That day’s revision tasks, plus a nudge the evening before each exam.{Platform.OS === 'web' ? ' (Notifications work in the phone app, not this web preview.)' : ''}
        </Txt>
        <View style={[s.row, { gap: 8, flexWrap: 'wrap' }]}>
          {TIMES.map(([h, m, l]) => (
            <Chip key={l} label={l} active={settings.reminderHour === h && settings.reminderMinute === m} onPress={() => updateSettings({ reminderHour: h, reminderMinute: m })} />
          ))}
        </View>
      </Card>

      <Card style={{ gap: 12 }}>
        <View style={s.row}>
          <IconBubble icon="phone-portrait" color={C.green} bg={C.greenSoft} size={40} />
          <View style={{ flex: 1 }}>
            <Txt v="h2">Your data</Txt>
            <Txt v="small">Stored on this phone only. No account needed.</Txt>
          </View>
        </View>
        <Button title="Load sample courses" kind="secondary" onPress={() => confirm('Load sample courses?', 'This replaces your current courses and questions with two demo courses.', 'Load', () => replaceAll(sampleState(settings.name)))} />
        <Button title="Erase everything" kind="danger" onPress={() => confirm('Erase everything?', 'All courses, questions and progress will be deleted.', 'Erase', () => replaceAll({ courses: [], questions: [], cards: {}, sessions: [], mocksDone: [], attempts: [], settings: { ...DEFAULT_SETTINGS, name: settings.name } }))} />
      </Card>
    </ScrollView>
  );
}

const st = StyleSheet.create({
  stepper: { width: 44, height: 44, borderRadius: 15, backgroundColor: C.primarySoft, alignItems: 'center', justifyContent: 'center' },
  stepText: { fontFamily: F.extrabold, fontSize: 22, color: C.primary },
  count: { fontFamily: F.extrabold, fontSize: 26, color: C.ink, minWidth: 30, textAlign: 'center' },
});
