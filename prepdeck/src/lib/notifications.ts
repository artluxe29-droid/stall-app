import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';
import { addDays, dayKey, fromKey } from './dates';
import type { Plan } from './planner';
import type { Course, Settings } from './types';

Notifications.setNotificationHandler({
  handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false }),
});

export async function ensurePermission(): Promise<boolean> {
  if (Platform.OS === 'web') return false;
  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('study', { name: 'Study reminders', importance: Notifications.AndroidImportance.HIGH });
  }
  const current = await Notifications.getPermissionsAsync();
  if (current.granted) return true;
  const asked = await Notifications.requestPermissionsAsync();
  return asked.granted;
}

/**
 * Replaces all scheduled reminders with fresh ones for the next week: a daily
 * study reminder with that day's task count, and an evening-before nudge for
 * each exam. Called whenever the plan or settings change.
 */
export async function scheduleReminders(plan: Plan, courses: Course[], settings: Settings): Promise<void> {
  if (Platform.OS === 'web') return;
  await Notifications.cancelAllScheduledNotificationsAsync();
  if (!settings.remindersOn || !(await ensurePermission())) return;

  const now = Date.now();
  const today = dayKey();
  const at = (key: string, h: number, m: number) => {
    const d = fromKey(key);
    d.setHours(h, m, 0, 0);
    return d;
  };

  for (let i = 0; i < 7; i++) {
    const key = addDays(today, i);
    const day = plan.days.find(d => d.date === key);
    if (!day || day.tasks.length === 0) continue;
    const when = at(key, settings.reminderHour, settings.reminderMinute);
    if (when.getTime() <= now) continue;
    const next = courses
      .filter(c => new Date(c.examAt).getTime() > when.getTime())
      .sort((a, b) => a.examAt.localeCompare(b.examAt))[0];
    const days = next ? Math.ceil((new Date(next.examAt).getTime() - when.getTime()) / 86400000) : 0;
    await Notifications.scheduleNotificationAsync({
      content: {
        title: `${day.tasks.length} revision task${day.tasks.length === 1 ? '' : 's'} today`,
        body: next ? `${next.code} is ${days === 1 ? 'tomorrow' : `in ${days} days`}. Open PrepDeck to tick them off.` : 'Open PrepDeck to tick them off.',
      },
      trigger: { type: Notifications.SchedulableTriggerInputTypes.DATE, date: when, channelId: 'study' },
    });
  }

  for (const c of courses) {
    const eve = at(addDays(dayKey(new Date(c.examAt)), -1), 20, 0);
    if (eve.getTime() <= now) continue;
    await Notifications.scheduleNotificationAsync({
      content: { title: `${c.code} is tomorrow`, body: 'Do a last timed mock, then rest. You have prepared for this.' },
      trigger: { type: Notifications.SchedulableTriggerInputTypes.DATE, date: eve, channelId: 'study' },
    });
  }
}
