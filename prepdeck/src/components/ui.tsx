import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useState, type ComponentProps, type ReactNode } from 'react';
import {
  Animated, Platform, Pressable, StyleSheet, Text, TextInput, View,
  type PressableProps, type StyleProp, type TextInputProps, type TextProps, type TextStyle, type ViewStyle,
} from 'react-native';
import Svg, { Circle, Defs, Stop, LinearGradient as SvgGradient } from 'react-native-svg';

/* ---------- tokens ---------- */

export const C = {
  bg: '#F5F6FB',
  card: '#FFFFFF',
  ink: '#14123A',
  ink2: '#5B5F7A',
  ink3: '#9A9DB5',
  line: '#ECEDF5',
  field: '#F3F4FA',
  primary: '#5B4BF5',
  violet: '#8B5CF6',
  primarySoft: '#EFEDFF',
  accent: '#FF7A45',
  accentSoft: '#FFF0E8',
  amber: '#F5A524',
  amberSoft: '#FFF6E0',
  green: '#12B76A',
  greenSoft: '#E5F8EE',
  red: '#F04438',
  redSoft: '#FEECEB',
  hero: '#1B1650',
};

export const GRADIENT = {
  hero: ['#3A2BD8', '#6A43F0', '#A35BF7'] as const,
  primary: ['#5B4BF5', '#8B5CF6'] as const,
  warm: ['#FF8A4C', '#FF5E7E'] as const,
  green: ['#19C37D', '#0EA5A0'] as const,
};

export const F = {
  regular: 'PlusJakartaSans_400Regular',
  medium: 'PlusJakartaSans_500Medium',
  semibold: 'PlusJakartaSans_600SemiBold',
  bold: 'PlusJakartaSans_700Bold',
  extrabold: 'PlusJakartaSans_800ExtraBold',
};

export const shadow = Platform.select<ViewStyle>({
  ios: { shadowColor: '#2B2A6B', shadowOpacity: 0.08, shadowRadius: 18, shadowOffset: { width: 0, height: 8 } },
  android: { elevation: 3, shadowColor: '#2B2A6B' },
  default: { shadowColor: '#2B2A6B', shadowOpacity: 0.08, shadowRadius: 18, shadowOffset: { width: 0, height: 8 } },
});

export type IconName = ComponentProps<typeof Ionicons>['name'];

/* ---------- text ---------- */

type Variant = 'display' | 'title' | 'h2' | 'h3' | 'body' | 'bodyStrong' | 'small' | 'caption' | 'overline';

const variants: Record<Variant, TextStyle> = {
  display: { fontFamily: F.extrabold, fontSize: 34, lineHeight: 40, letterSpacing: -1, color: C.ink },
  title: { fontFamily: F.extrabold, fontSize: 26, lineHeight: 32, letterSpacing: -0.6, color: C.ink },
  h2: { fontFamily: F.bold, fontSize: 18, lineHeight: 24, letterSpacing: -0.2, color: C.ink },
  h3: { fontFamily: F.bold, fontSize: 15.5, lineHeight: 21, color: C.ink },
  body: { fontFamily: F.medium, fontSize: 15, lineHeight: 22, color: C.ink2 },
  bodyStrong: { fontFamily: F.semibold, fontSize: 15, lineHeight: 22, color: C.ink },
  small: { fontFamily: F.medium, fontSize: 13, lineHeight: 18, color: C.ink2 },
  caption: { fontFamily: F.semibold, fontSize: 12, lineHeight: 16, color: C.ink3 },
  overline: { fontFamily: F.bold, fontSize: 11, lineHeight: 14, letterSpacing: 1.2, textTransform: 'uppercase', color: C.ink3 },
};

export function Txt({ v = 'body', style, ...props }: TextProps & { v?: Variant }) {
  return <Text {...props} style={[variants[v], style]} />;
}

/* ---------- surfaces ---------- */

export function Card({ children, style, flat }: { children: ReactNode; style?: StyleProp<ViewStyle>; flat?: boolean }) {
  return <View style={[s.card, !flat && shadow, style]}>{children}</View>;
}

const AnimatedPressable = Animated.createAnimatedComponent(Pressable);

/** Pressable that gently shrinks while held, so every tap feels physical. */
export function Tap({ children, style, scale = 0.97, ...props }: PressableProps & { style?: StyleProp<ViewStyle>; scale?: number; children: ReactNode }) {
  const [v] = useState(() => new Animated.Value(1));
  const to = (n: number) => Animated.spring(v, { toValue: n, useNativeDriver: Platform.OS !== 'web', speed: 40, bounciness: 6 }).start();
  return (
    <AnimatedPressable
      {...props}
      onPressIn={e => { to(scale); props.onPressIn?.(e); }}
      onPressOut={e => { to(1); props.onPressOut?.(e); }}
      style={[style, { transform: [{ scale: v }] }, props.disabled ? { opacity: 0.45 } : null]}
    >
      {children}
    </AnimatedPressable>
  );
}

export function Button({
  title, onPress, kind = 'primary', icon, disabled, style, small,
}: {
  title: string;
  onPress: () => void;
  kind?: 'primary' | 'secondary' | 'danger' | 'ghost' | 'white';
  icon?: IconName;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
  small?: boolean;
}) {
  const fg = { primary: '#fff', secondary: C.primary, danger: C.red, ghost: C.primary, white: C.primary }[kind];
  const body = (
    <>
      {icon ? <Ionicons name={icon} size={small ? 16 : 19} color={fg} /> : null}
      <Text style={[s.btnText, small && { fontSize: 14 }, { color: fg }]}>{title}</Text>
    </>
  );
  const pad = small ? s.btnSmall : null;
  return (
    <Tap accessibilityRole="button" accessibilityLabel={title} onPress={onPress} disabled={disabled} style={style}>
      {kind === 'primary' ? (
        <LinearGradient colors={GRADIENT.primary} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={[s.btn, pad, s.btnGlow]}>{body}</LinearGradient>
      ) : (
        <View style={[s.btn, pad, { backgroundColor: { secondary: C.primarySoft, danger: C.redSoft, ghost: 'transparent', white: '#fff' }[kind] }]}>{body}</View>
      )}
    </Tap>
  );
}

export function IconButton({ icon, onPress, label, color = C.ink, bg = C.card }: { icon: IconName; onPress: () => void; label: string; color?: string; bg?: string }) {
  return (
    <Tap onPress={onPress} accessibilityLabel={label} accessibilityRole="button" hitSlop={8} style={[s.iconBtn, { backgroundColor: bg }, bg === C.card && shadow]}>
      <Ionicons name={icon} size={21} color={color} />
    </Tap>
  );
}

export function IconBubble({ icon, color, bg, size = 44 }: { icon: IconName; color: string; bg: string; size?: number }) {
  return (
    <View style={{ width: size, height: size, borderRadius: size * 0.34, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
      <Ionicons name={icon} size={size * 0.5} color={color} />
    </View>
  );
}

export function Pill({ label, color = C.primary, bg = C.primarySoft, icon }: { label: string; color?: string; bg?: string; icon?: IconName }) {
  return (
    <View style={[s.pill, { backgroundColor: bg }]}>
      {icon ? <Ionicons name={icon} size={13} color={color} /> : null}
      <Text style={[s.pillText, { color }]}>{label}</Text>
    </View>
  );
}

export function Chip({ label, active, onPress, color = C.primary }: { label: string; active: boolean; onPress: () => void; color?: string }) {
  return (
    <Tap onPress={onPress} accessibilityRole="button" accessibilityState={{ selected: active }} style={[s.chip, active ? { backgroundColor: color, borderColor: color } : null]}>
      <Text style={[s.chipText, active && { color: '#fff' }]}>{label}</Text>
    </Tap>
  );
}

export function Field({ label, hint, ...props }: TextInputProps & { label: string; hint?: string }) {
  const [focused, setFocused] = useState(false);
  return (
    <View style={{ marginBottom: 16 }}>
      <Text style={s.label}>{label}</Text>
      <TextInput
        placeholderTextColor={C.ink3}
        {...props}
        onFocus={e => { setFocused(true); props.onFocus?.(e); }}
        onBlur={e => { setFocused(false); props.onBlur?.(e); }}
        style={[s.input, focused && s.inputFocus, props.multiline && { minHeight: 110, textAlignVertical: 'top' }, props.style]}
      />
      {hint ? <Txt v="caption" style={{ marginTop: 6, fontFamily: F.medium }}>{hint}</Txt> : null}
    </View>
  );
}

export function Dot({ color, size = 10 }: { color: string; size?: number }) {
  return <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: color }} />;
}

export function Bar({ value, color = C.primary, height = 8, track = C.line }: { value: number; color?: string; height?: number; track?: string }) {
  return (
    <View style={{ height, borderRadius: height / 2, backgroundColor: track, overflow: 'hidden', flex: 1 }}>
      <View style={{ width: `${Math.max(0, Math.min(1, value)) * 100}%`, height, borderRadius: height / 2, backgroundColor: color }} />
    </View>
  );
}

/** Circular progress ring with a gradient stroke. */
export function Ring({ value, size = 84, stroke = 10, colors = GRADIENT.primary, track = C.primarySoft, children }: {
  value: number; size?: number; stroke?: number; colors?: readonly [string, string, ...string[]]; track?: string; children?: ReactNode;
}) {
  const r = (size - stroke) / 2;
  const len = 2 * Math.PI * r;
  const id = `ring-${colors.join('').replace(/#/g, '')}`;
  const v = Math.max(0, Math.min(1, value));
  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      <Svg width={size} height={size} style={StyleSheet.absoluteFill}>
        <Defs>
          <SvgGradient id={id} x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0" stopColor={colors[0]} />
            <Stop offset="1" stopColor={colors[colors.length - 1]} />
          </SvgGradient>
        </Defs>
        <Circle cx={size / 2} cy={size / 2} r={r} stroke={track} strokeWidth={stroke} fill="none" />
        {v > 0 ? (
          <Circle cx={size / 2} cy={size / 2} r={r} stroke={`url(#${id})`} strokeWidth={stroke} fill="none"
            strokeDasharray={`${len * v} ${len}`} strokeLinecap="round" transform={`rotate(-90 ${size / 2} ${size / 2})`} />
        ) : null}
      </Svg>
      {children}
    </View>
  );
}

export function Empty({ icon, title, body, children }: { icon: IconName; title: string; body: string; children?: ReactNode }) {
  return (
    <Card style={{ alignItems: 'center', paddingVertical: 30, paddingHorizontal: 22 }}>
      <LinearGradient colors={GRADIENT.primary} style={s.emptyIcon}>
        <Ionicons name={icon} size={30} color="#fff" />
      </LinearGradient>
      <Txt v="h2" style={{ textAlign: 'center' }}>{title}</Txt>
      <Txt style={{ textAlign: 'center', marginTop: 6, marginBottom: 18 }}>{body}</Txt>
      {children}
    </Card>
  );
}

export const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: C.bg },
  content: { padding: 20, paddingBottom: 48, gap: 16 },
  card: { backgroundColor: C.card, borderRadius: 24, padding: 18 },
  btn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingVertical: 15, paddingHorizontal: 20, borderRadius: 18 },
  btnSmall: { paddingVertical: 10, paddingHorizontal: 14, borderRadius: 14 },
  btnGlow: Platform.select<ViewStyle>({
    ios: { shadowColor: '#5B4BF5', shadowOpacity: 0.35, shadowRadius: 14, shadowOffset: { width: 0, height: 8 } },
    android: { elevation: 4 },
    default: { shadowColor: '#5B4BF5', shadowOpacity: 0.35, shadowRadius: 14, shadowOffset: { width: 0, height: 8 } },
  }) as ViewStyle,
  btnText: { fontFamily: F.bold, fontSize: 15.5 },
  iconBtn: { width: 44, height: 44, borderRadius: 15, alignItems: 'center', justifyContent: 'center' },
  label: { fontFamily: F.semibold, fontSize: 13, color: C.ink2, marginBottom: 8 },
  input: { backgroundColor: C.field, borderWidth: 1.5, borderColor: C.field, borderRadius: 16, paddingHorizontal: 16, paddingVertical: 14, fontSize: 15.5, color: C.ink, fontFamily: F.medium },
  inputFocus: { borderColor: C.primary, backgroundColor: '#fff' },
  chip: { paddingVertical: 9, paddingHorizontal: 16, borderRadius: 999, borderWidth: 1.5, borderColor: C.line, backgroundColor: C.card },
  chipText: { fontFamily: F.semibold, fontSize: 14, color: C.ink2 },
  pill: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 10, paddingVertical: 5, borderRadius: 999, alignSelf: 'flex-start' },
  pillText: { fontFamily: F.bold, fontSize: 12 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  between: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10 },
  emptyIcon: { width: 64, height: 64, borderRadius: 22, alignItems: 'center', justifyContent: 'center', marginBottom: 16 },
});
