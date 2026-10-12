import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { countdown } from '../lib/dates';

/** Live days/hours/minutes/seconds counter for an exam. */
export function CountdownBlocks({ target, color = '#fff', small }: { target: string; color?: string; small?: boolean }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(t);
  }, []);
  const c = countdown(new Date(target), now);
  const parts: [number, string][] = [[c.days, 'days'], [c.hours, 'hrs'], [c.minutes, 'min'], [c.seconds, 'sec']];
  return (
    <View style={st.row}>
      {parts.map(([v, l]) => (
        <View key={l} style={[st.block, small && st.blockSmall]}>
          <Text style={[st.num, small && st.numSmall, { color }]}>{String(v).padStart(2, '0')}</Text>
          <Text style={[st.unit, { color }]}>{l}</Text>
        </View>
      ))}
    </View>
  );
}

const st = StyleSheet.create({
  row: { flexDirection: 'row', gap: 8 },
  block: { flex: 1, alignItems: 'center', paddingVertical: 10, borderRadius: 14, backgroundColor: 'rgba(255,255,255,0.1)' },
  blockSmall: { paddingVertical: 6, borderRadius: 10, backgroundColor: 'rgba(79,70,229,0.08)' },
  num: { fontSize: 30, fontWeight: '800', fontVariant: ['tabular-nums'] },
  numSmall: { fontSize: 20 },
  unit: { fontSize: 11, fontWeight: '600', opacity: 0.75, marginTop: 2, textTransform: 'uppercase', letterSpacing: 0.5 },
});
