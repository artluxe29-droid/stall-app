import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { C } from '../components/ui';
import { scheduleReminders } from '../lib/notifications';
import { StoreProvider, useStore } from '../lib/store';
import { usePlan } from '../lib/usePlan';

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
  return (
    <StoreProvider>
      <StatusBar style="dark" />
      <Reminders />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: C.bg },
          headerShadowVisible: false,
          headerTintColor: C.ink,
          headerTitleStyle: { fontWeight: '700' },
          contentStyle: { backgroundColor: C.bg },
        }}
      >
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen name="course/new" options={{ title: 'Course', presentation: 'modal' }} />
        <Stack.Screen name="course/[id]/index" options={{ title: '' }} />
        <Stack.Screen name="course/[id]/import" options={{ title: 'Add past questions' }} />
        <Stack.Screen name="course/[id]/question" options={{ title: 'New question', presentation: 'modal' }} />
        <Stack.Screen name="quiz" options={{ title: '' }} />
        <Stack.Screen name="settings" options={{ title: 'Settings' }} />
      </Stack>
    </StoreProvider>
  );
}
