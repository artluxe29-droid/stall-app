import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, Text, View } from 'react-native';
import { Button, Chip, Field, s, Txt } from '../../../components/ui';
import { useStore } from '../../../lib/store';

const LETTERS = ['A', 'B', 'C', 'D'];

export default function NewQuestion() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { addQuestions } = useStore();
  const [kind, setKind] = useState<'mcq' | 'theory'>('mcq');
  const [prompt, setPrompt] = useState('');
  const [options, setOptions] = useState(['', '', '', '']);
  const [answer, setAnswer] = useState(0);
  const [explanation, setExplanation] = useState('');
  const [modelAnswer, setModelAnswer] = useState('');
  const [topic, setTopic] = useState('');

  const filled = options.map(o => o.trim()).filter(Boolean);
  const valid = prompt.trim() && (kind === 'theory' ? modelAnswer.trim() : filled.length >= 2 && options[answer]?.trim());

  const save = () => {
    const extra = topic.trim() ? { topic: topic.trim() } : {};
    if (kind === 'mcq') {
      // Drop empty options while keeping the chosen answer pointing at the right one.
      const kept = options.map((o, i) => ({ o: o.trim(), i })).filter(x => x.o);
      addQuestions(id, [{
        kind: 'mcq', prompt: prompt.trim(), options: kept.map(x => x.o), answer: kept.findIndex(x => x.i === answer),
        ...(explanation.trim() ? { explanation: explanation.trim() } : {}), ...extra,
      }]);
    } else {
      addQuestions(id, [{ kind: 'theory', prompt: prompt.trim(), modelAnswer: modelAnswer.trim(), ...extra }]);
    }
    router.back();
  };

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={[s.content, { gap: 0 }]} keyboardShouldPersistTaps="handled">
        <Txt v="title" style={{ marginBottom: 16 }}>New question</Txt>
        <View style={[s.row, { gap: 8, marginBottom: 18 }]}>
          <Chip label="Multiple choice" active={kind === 'mcq'} onPress={() => setKind('mcq')} />
          <Chip label="Theory" active={kind === 'theory'} onPress={() => setKind('theory')} />
        </View>
        <Field label="Question" value={prompt} onChangeText={setPrompt} multiline placeholder="Type the question" />
        {kind === 'mcq' ? (
          <>
            {options.map((o, i) => (
              <Field key={i} label={`Option ${LETTERS[i]}`} value={o} onChangeText={t => setOptions(prev => prev.map((p, j) => (j === i ? t : p)))} />
            ))}
            <Text style={s.label}>Correct answer</Text>
            <View style={[s.row, { gap: 8, marginBottom: 16 }]}>
              {LETTERS.map((l, i) => <Chip key={l} label={l} active={answer === i} onPress={() => setAnswer(i)} />)}
            </View>
            <Field label="Explanation (optional)" value={explanation} onChangeText={setExplanation} multiline />
          </>
        ) : (
          <Field label="Model answer" value={modelAnswer} onChangeText={setModelAnswer} multiline placeholder="What a full-marks answer contains" />
        )}
        <Field label="Topic (optional)" value={topic} onChangeText={setTopic} />
        <Button title="Save question" onPress={save} disabled={!valid} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
