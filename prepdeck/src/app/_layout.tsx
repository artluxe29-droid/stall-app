import {
  PlusJakartaSans_400Regular, PlusJakartaSans_500Medium, PlusJakartaSans_600SemiBold, PlusJakartaSans_700Bold, PlusJakartaSans_800ExtraBold, useFonts,
} from '@expo-google-fonts/plus-jakarta-sans';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { C, F } from '../components/ui';
import { scheduleReminders } from '../lib/notifications';
import { StoreProvider, useStore } from '../lib/store';
import { usePlan } from '../lib/usePlan';

SplashScreen.preventAutoHideAsync().catch(() => {});

function Reminders() {
  const { ready, state } = useStore();
  const plan = usePlan();
  const { remindersOn, reminderHour, reminderMinute } = state.settings;
  useEffect(() => {
    if (!ready) return;
    const t = setTimeout(() => {
      scheduleReminders(plan, state.courses, state.settings).catch(() => {});
    }, 800);
    return () => clearTimeout(t);
    // Reschedule when the plan or reminder settings change.
  }, [ready, plan, state.courses, remindersOn, reminderHour, reminderMinute]); // eslint-disable-line react-hooks/exhaustive-deps
  return null;
}

export default function RootLayout() {
  const [fontsLoaded, fontError] = useFonts({
    PlusJakartaSans_400Regular, PlusJakartaSans_500Medium, PlusJakartaSans_600SemiBold, PlusJakartaSans_700Bold, PlusJakartaSans_800ExtraBold,
  });
  const ready = fontsLoaded || !!fontError;

  useEffect(() => {
    if (ready) SplashScreen.hideAsync().catch(() => {});
  }, [ready]);

  if (!ready) return null;

  return (
    <StoreProvider>
      <StatusBar style="dark" />
      <Reminders />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: C.bg },
          headerShadowVisible: false,
          headerTintColor: C.ink,
          headerTitleStyle: { fontFamily: F.bold, fontSize: 17 },
          headerBackButtonDisplayMode: 'minimal',
          contentStyle: { backgroundColor: C.bg },
        }}
      >
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen name="course/new" options={{ title: '', presentation: 'modal' }} />
        <Stack.Screen name="course/[id]/index" options={{ title: '' }} />
        <Stack.Screen name="course/[id]/import" options={{ title: 'Add past questions' }} />
        <Stack.Screen name="course/[id]/question" options={{ title: '', presentation: 'modal' }} />
        <Stack.Screen name="quiz" options={{ title: '' }} />
        <Stack.Screen name="settings" options={{ title: 'Settings' }} />
      </Stack>
    </StoreProvider>
  );
}
