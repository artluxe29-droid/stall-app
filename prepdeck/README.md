# PrepDeck

Exam countdown, revision planner and past-question quiz app, built with Expo (React Native) for Android and iOS.

## What it does
- **Countdown** to every exam, live on the home screen.
- **Revision plan**: enter each course's topics and rate them Shaky / Okay / Solid. The app spreads revision sessions over the days before each exam (weak topics, hard courses and nearer exams first), adds a timed mock the day before each paper, and reshuffles automatically when you miss a day.
- **Past questions**: paste them in a simple format (`Q:`, `A)`–`D)`, `Answer:`), or add them one by one. Multiple-choice and theory questions are both supported.
- **Practice modes**: quick practice with instant answers, timed mock exams marked at the end, and spaced review that brings back questions you missed (1, 2, 4, 7, then 14 days).
- **Reminders**: a daily notification with that day's tasks and a nudge the evening before each exam.
- Everything is stored on the phone; no account or internet needed.

## Run it
```bash
npm install
npx expo start          # scan the QR code with Expo Go, or press w for the web preview
npm test                # planner, importer and spaced-repetition tests
npm run typecheck
npx expo lint
```

## Build an Android APK
Builds run on Expo's servers, so no Android Studio is needed.
```bash
npx eas-cli@latest login                              # free account at expo.dev
npx eas-cli@latest build -p android --profile preview # gives a link to download the .apk
```
Use `--profile production` for a Play Store `.aab`.

## Code map
- `src/app/` – screens (Expo Router): Today, Exams, Practice, Progress tabs; course, import, quiz and settings screens.
- `src/lib/planner.ts` – builds the day-by-day revision plan.
- `src/lib/importer.ts` – parses pasted past questions.
- `src/lib/srs.ts` – spaced-repetition review (Leitner boxes).
- `src/lib/store.tsx` – app state, saved with AsyncStorage.
- `src/lib/notifications.ts` – daily and exam-eve reminders.
