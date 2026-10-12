import { useState } from 'react';
import { Platform, Pressable, ScrollView, Switch, Text, View } from 'react-native';
import { Button, C, Card, Chip, Field, H2, Muted, s } from '../components/ui';
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
        <Field label="Your first name" value={name} onChangeText={setName} onEndEditing={() => updateSettings({ name: name.trim() })} onBlur={() => updateSettings({ name: name.trim() })} placeholder="For the greeting" />
        <Text style={s.label}>Revision sessions per day</Text>
        <View style={[s.row, { gap: 12 }]}>
          <Pressable style={stepper} onPress={() => updateSettings({ sessionsPerDay: Math.max(1, settings.sessionsPerDay - 1) })}><Text style={stepText}>−</Text></Pressable>
          <Text style={{ fontSize: 22, fontWeight: '800', color: C.ink, minWidth: 30, textAlign: 'center' }}>{settings.sessionsPerDay}</Text>
          <Pressable style={stepper} onPress={() => updateSettings({ sessionsPerDay: Math.min(10, settings.sessionsPerDay + 1) })}><Text style={stepText}>+</Text></Pressable>
          <Muted style={{ flex: 1, fontSize: 13 }}>About 45 minutes each. Your plan reshuffles straight away.</Muted>
        </View>
      </Card>

      <Card>
        <View style={[s.row, { justifyContent: 'space-between' }]}>
          <H2>Daily reminder</H2>
          <Switch value={settings.remindersOn} onValueChange={v => updateSettings({ remindersOn: v })} trackColor={{ true: C.primary, false: C.line }} />
        </View>
        <Muted style={{ fontSize: 13, marginTop: 4, marginBottom: 10 }}>
          A notification with that day’s revision tasks, plus a nudge the evening before each exam.{Platform.OS === 'web' ? ' (Notifications work in the phone app, not this web preview.)' : ''}
        </Muted>
        <View style={[s.row, { gap: 8, flexWrap: 'wrap' }]}>
          {TIMES.map(([h, m, l]) => (
            <Chip key={l} label={l} active={settings.reminderHour === h && settings.reminderMinute === m} onPress={() => updateSettings({ reminderHour: h, reminderMinute: m })} />
          ))}
        </View>
      </Card>

      <Card style={{ gap: 10 }}>
        <H2>Data</H2>
        <Muted style={{ fontSize: 13 }}>Everything is stored on this phone only.</Muted>
        <Button title="Load sample courses" kind="secondary" onPress={() => confirm('Load sample courses?', 'This replaces your current courses and questions with two demo courses.', 'Load', () => replaceAll(sampleState(settings.name)))} />
        <Button title="Erase everything" kind="danger" onPress={() => confirm('Erase everything?', 'All courses, questions and progress will be deleted.', 'Erase', () => replaceAll({ courses: [], questions: [], cards: {}, sessions: [], mocksDone: [], attempts: [], settings: { ...DEFAULT_SETTINGS, name: settings.name } }))} />
      </Card>
    </ScrollView>
  );
}

const stepper = { width: 40, height: 40, borderRadius: 12, backgroundColor: C.primarySoft, alignItems: 'center' as const, justifyContent: 'center' as const };
const stepText = { fontSize: 22, fontWeight: '800' as const, color: C.primary };
