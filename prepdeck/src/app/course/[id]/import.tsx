import { Ionicons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, Text, TextInput, View } from 'react-native';
import { Button, C, Card, F, IconBubble, s, Txt } from '../../../components/ui';
import { IMPORT_EXAMPLE, parseQuestions } from '../../../lib/importer';
import { useStore } from '../../../lib/store';

export default function Import() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { state, addQuestions } = useStore();
  const course = state.courses.find(c => c.id === id);
  const [text, setText] = useState('');
  const result = useMemo(() => parseQuestions(text), [text]);
  const mcq = result.questions.filter(q => q.kind === 'mcq').length;
  const theory = result.questions.length - mcq;

  if (!course) return null;

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
        <Card flat style={{ backgroundColor: C.primarySoft }}>
          <Txt v="h2">Paste past questions for {course.code}</Txt>
          <Txt v="small" style={{ marginTop: 6 }}>
            Start each question with “Q:”. Add options as A) B) C) D) and the correct one as “Answer: B”. A question with no options is a theory question; put the model answer after “Answer:”. Topic: and Year: lines are optional.
          </Txt>
          <View style={[s.row, { marginTop: 14, alignItems: 'flex-start', backgroundColor: '#fff', borderRadius: 16, padding: 12 }]}>
            <IconBubble icon="camera" color={C.primary} bg={C.primarySoft} size={34} />
            <Txt v="small" style={{ flex: 1 }}>Have a photo of a past paper? Send it to Claude and ask for the questions in this format with answers, then paste the result here.</Txt>
          </View>
          <Button title="Insert an example" kind="ghost" icon="document-text-outline" onPress={() => setText(IMPORT_EXAMPLE)} style={{ alignSelf: 'flex-start', paddingHorizontal: 0 }} />
        </Card>

        <TextInput
          value={text}
          onChangeText={setText}
          multiline
          placeholder={'Q: ...\nA) ...\nB) ...\nAnswer: A'}
          placeholderTextColor={C.ink3}
          style={[s.input, { minHeight: 260, textAlignVertical: 'top', backgroundColor: '#fff', borderColor: C.line, fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' }), fontSize: 13 }]}
        />

        {text.trim() !== '' && (
          <Card>
            <Text style={{ fontSize: 15, fontFamily: F.bold, color: result.questions.length ? C.green : C.ink2 }}>
              Found {result.questions.length} question{result.questions.length === 1 ? '' : 's'}
              {result.questions.length ? ` (${mcq} multiple choice, ${theory} theory)` : ''}
            </Text>
            {result.errors.map(e => (
              <View key={e} style={[s.row, { marginTop: 6, alignItems: 'flex-start' }]}>
                <Ionicons name="alert-circle-outline" size={16} color={C.red} style={{ marginTop: 2 }} />
                <Text style={{ flex: 1, fontSize: 13, color: C.red, fontFamily: F.medium }}>{e}</Text>
              </View>
            ))}
          </Card>
        )}

        <Button
          title={result.questions.length ? `Add ${result.questions.length} question${result.questions.length === 1 ? '' : 's'}` : 'Add questions'}
          icon="checkmark"
          disabled={result.questions.length === 0}
          onPress={() => {
            addQuestions(course.id, result.questions);
            router.back();
          }}
        />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
