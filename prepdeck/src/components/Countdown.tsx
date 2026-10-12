import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { countdown } from '../lib/dates';
import { C, F } from './ui';

/** Live days/hours/minutes/seconds counter for an exam. `light` is for gradient backgrounds. */
export function CountdownBlocks({ target, light = true }: { target: string; light?: boolean }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(t);
  }, []);
  const c = countdown(new Date(target), now);
  const parts: [number, string][] = [[c.days, 'Days'], [c.hours, 'Hours'], [c.minutes, 'Mins'], [c.seconds, 'Secs']];
  return (
    <View style={st.row}>
      {parts.map(([v, l]) => (
        <View key={l} style={[st.block, light ? st.glass : st.soft]}>
          <Text style={[st.num, { color: light ? '#fff' : C.primary }]}>{String(v).padStart(2, '0')}</Text>
          <Text style={[st.unit, { color: light ? 'rgba(255,255,255,0.75)' : C.ink2 }]}>{l}</Text>
        </View>
      ))}
    </View>
  );
}

const st = StyleSheet.create({
  row: { flexDirection: 'row', gap: 8 },
  block: { flex: 1, alignItems: 'center', paddingVertical: 12, borderRadius: 18 },
  glass: { backgroundColor: 'rgba(255,255,255,0.14)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.18)' },
  soft: { backgroundColor: C.primarySoft },
  num: { fontFamily: F.extrabold, fontSize: 28, lineHeight: 34, fontVariant: ['tabular-nums'], letterSpacing: -0.5 },
  unit: { fontFamily: F.semibold, fontSize: 11, marginTop: 1 },
});
