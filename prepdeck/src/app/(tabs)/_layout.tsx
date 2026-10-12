import { Ionicons } from '@expo/vector-icons';
import Tabs from 'expo-router/js-tabs';
import { Platform, View, type ColorValue } from 'react-native';
import { C, F, type IconName } from '../../components/ui';

/** Tab icon: outlined when idle, filled with a soft pill behind it when selected. */
function icon(name: string) {
  const TabIcon = ({ color, focused }: { color: ColorValue; focused: boolean }) => (
    <View style={{ paddingHorizontal: 16, paddingVertical: 4, borderRadius: 999, backgroundColor: focused ? C.primarySoft : 'transparent' }}>
      <Ionicons name={(focused ? name : `${name}-outline`) as IconName} size={22} color={color as string} />
    </View>
  );
  TabIcon.displayName = `TabIcon(${name})`;
  return TabIcon;
}

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: C.primary,
        tabBarInactiveTintColor: C.ink3,
        tabBarStyle: {
          backgroundColor: C.card,
          borderTopWidth: 0,
          height: Platform.OS === 'ios' ? 88 : 70,
          paddingTop: 8,
          shadowColor: '#2B2A6B', shadowOpacity: 0.07, shadowRadius: 16, shadowOffset: { width: 0, height: -4 }, elevation: 12,
        },
        tabBarLabelStyle: { fontFamily: F.semibold, fontSize: 11.5, marginTop: 2 },
      }}
    >
      <Tabs.Screen name="index" options={{ title: 'Today', tabBarIcon: icon('home') }} />
      <Tabs.Screen name="exams" options={{ title: 'Exams', tabBarIcon: icon('calendar') }} />
      <Tabs.Screen name="practice" options={{ title: 'Practice', tabBarIcon: icon('flash') }} />
      <Tabs.Screen name="progress" options={{ title: 'Progress', tabBarIcon: icon('trophy') }} />
    </Tabs>
  );
}
