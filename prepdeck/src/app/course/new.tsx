import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, Text, View } from 'react-native';
import { DateTimeField } from '../../components/DateTimeField';
import { Button, Chip, Field, s, Txt } from '../../components/ui';
import { uid, useStore } from '../../lib/store';
import type { Topic } from '../../lib/types';

function defaultExam() {
  const d = new Date();
  d.setDate(d.getDate() + 14);
  d.setHours(9, 0, 0, 0);
  return d;
}

/** Add a course, or edit one when opened with ?id=. */
export default function CourseForm() {
  const { id } = useLocalSearchParams<{ id?: string }>();
  const { state, addCourse, updateCourse } = useStore();
  const existing = state.courses.find(c => c.id === id);

  const [code, setCode] = useState(existing?.code ?? '');
  const [title, setTitle] = useState(existing?.title ?? '');
  const [venue, setVenue] = useState(existing?.venue ?? '');
  const [examAt, setExamAt] = useState(existing ? new Date(existing.examAt) : defaultExam());
  const [difficulty, setDifficulty] = useState<1 | 2 | 3>(existing?.difficulty ?? 2);
  const [topicsText, setTopicsText] = useState(existing?.topics.map(t => t.name).join('\n') ?? '');

  const save = () => {
    const names = topicsText.split('\n').map(t => t.trim()).filter(Boolean);
    // Keep ids (and confidence) of topics that were already there, so ticks and history survive edits.
    const topics: Topic[] = names.map(name => existing?.topics.find(t => t.name === name) ?? { id: uid(), name, confidence: 1 });
    const data = { code: code.trim().toUpperCase(), title: title.trim(), venue: venue.trim() || undefined, examAt: examAt.toISOString(), difficulty, topics };
    if (existing) updateCourse(existing.id, data);
    else addCourse(data);
    router.back();
  };

  const valid = code.trim() && title.trim();

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={[s.content, { gap: 0 }]} keyboardShouldPersistTaps="handled">
        <Txt v="title" style={{ marginBottom: 4 }}>{existing ? 'Edit exam' : 'New exam'}</Txt>
        <Txt v="small" style={{ marginBottom: 22 }}>Your plan updates as soon as you save.</Txt>
        <Field label="Course code" value={code} onChangeText={setCode} placeholder="e.g. CPE 501" autoCapitalize="characters" />
        <Field label="Course title" value={title} onChangeText={setTitle} placeholder="e.g. Digital Systems Design" />
        <DateTimeField label="Exam date and time" value={examAt} onChange={setExamAt} />
        <Field label="Venue (optional)" value={venue} onChangeText={setVenue} placeholder="e.g. Main hall" />
        <View style={{ marginBottom: 16 }}>
          <Text style={s.label}>How hard is this course for you?</Text>
          <View style={[s.row, { gap: 8 }]}>
            {(['Easy', 'Medium', 'Hard'] as const).map((l, i) => (
              <Chip key={l} label={l} active={difficulty === i + 1} onPress={() => setDifficulty((i + 1) as 1 | 2 | 3)} />
            ))}
          </View>
        </View>
        <Field label="Topics to revise (one per line)" value={topicsText} onChangeText={setTopicsText} multiline placeholder={'Number systems\nBoolean algebra\nLogic gates'}
          hint="Copy them from the course outline. New topics start as “shaky”; rate each one on the course page." />
        <Button title={existing ? 'Save changes' : 'Add course'} onPress={save} disabled={!valid} style={{ marginTop: 8 }} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
