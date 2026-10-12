import { Ionicons } from '@expo/vector-icons';
import RNDateTimePicker, { DateTimePickerAndroid } from '@react-native-community/datetimepicker';
import { useState } from 'react';
import { Platform, Pressable, Text, TextInput, View } from 'react-native';
import { formatExam } from '../lib/dates';
import { C, F, s } from './ui';

const pad = (n: number) => String(n).padStart(2, '0');

/** Picks a date and time: native pickers on phones, typed fields on the web preview. */
export function DateTimeField({ label, value, onChange }: { label: string; value: Date; onChange: (d: Date) => void }) {
  const [webDate, setWebDate] = useState(`${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}`);
  const [webTime, setWebTime] = useState(`${pad(value.getHours())}:${pad(value.getMinutes())}`);

  if (Platform.OS === 'web') {
    const apply = (dateStr: string, timeStr: string) => {
      const [y, m, d] = dateStr.split('-').map(Number);
      const [h, min] = timeStr.split(':').map(Number);
      const next = new Date(y, (m || 1) - 1, d || 1, h || 0, min || 0);
      if (!Number.isNaN(next.getTime())) onChange(next);
    };
    return (
      <View style={{ marginBottom: 16 }}>
        <Text style={s.label}>{label}</Text>
        <View style={s.row}>
          <TextInput style={[s.input, { flex: 2 }]} value={webDate} placeholder="YYYY-MM-DD" onChangeText={t => { setWebDate(t); apply(t, webTime); }} />
          <TextInput style={[s.input, { flex: 1 }]} value={webTime} placeholder="HH:MM" onChangeText={t => { setWebTime(t); apply(webDate, t); }} />
        </View>
      </View>
    );
  }

  if (Platform.OS === 'ios') {
    return (
      <View style={{ marginBottom: 14 }}>
        <Text style={s.label}>{label}</Text>
        <RNDateTimePicker mode="datetime" value={value} display="compact" minuteInterval={5} onChange={(_, d) => d && onChange(d)} style={{ alignSelf: 'flex-start' }} />
      </View>
    );
  }

  // Android: open the date dialog, then the time dialog.
  const open = () => {
    DateTimePickerAndroid.open({
      value, mode: 'date',
      onChange: (e, d) => {
        if (e.type !== 'set' || !d) return;
        DateTimePickerAndroid.open({
          value: d, mode: 'time', is24Hour: false,
          onChange: (e2, t) => {
            if (e2.type === 'set' && t) onChange(t);
          },
        });
      },
    });
  };
  return (
    <View style={{ marginBottom: 14 }}>
      <Text style={s.label}>{label}</Text>
      <Pressable onPress={open} style={[s.input, s.row, { justifyContent: 'space-between' }]}>
        <Text style={{ fontSize: 15.5, color: C.ink, fontFamily: F.medium }}>{formatExam(value.toISOString())}</Text>
        <Ionicons name="calendar-outline" size={18} color={C.ink2} />
      </Pressable>
    </View>
  );
}
