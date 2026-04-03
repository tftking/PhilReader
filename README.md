# PhilReader

A clean, fast CBZ comic reader for iOS (and Android) built with React Native + Expo.

## Features

- 📚 Library grid with cover thumbnails and reading progress
- 📖 Horizontal paged reader
- 🔍 Pinch-to-zoom + double-tap zoom on every page
- 🔄 Right-to-Left mode for manga
- 📥 Import via Files app or the + button
- 💾 Reading progress auto-saved
- 🗑️ Long-press a comic to delete
- 📱 iPhone, iPad, and Android

## Stack

- [Expo](https://expo.dev) SDK 51 (managed workflow)
- [Expo Router](https://expo.github.io/router) v3 for navigation
- [JSZip](https://stuk.github.io/jszip/) for .cbz extraction (pure JS, no native module)
- [react-native-gesture-handler](https://docs.swmansion.com/react-native-gesture-handler/) + [react-native-reanimated](https://docs.swmansion.com/react-native-reanimated/) for zoom
- [expo-image](https://docs.expo.dev/versions/latest/sdk/image/) for efficient image rendering
- [AsyncStorage](https://react-native-async-storage.github.io/async-storage/) for persistence

## Setup

```bash
# Install dependencies
npm install

# Start dev server
npx expo start

# Run on iOS simulator
npx expo start --ios

# Run on Android
npx expo start --android
```

> **Note:** To run on a physical device without building, install the **Expo Go** app and scan the QR code.

## Building for production

```bash
# Install EAS CLI
npm install -g eas-cli

# Build for iOS
eas build --platform ios

# Build for Android
eas build --platform android
```

## Importing Comics

- **In-app:** Tap the **+** FAB → pick any `.cbz` file
- **From Files app (iOS):** Long-press a `.cbz` → Share → Open with PhilReader

## Project Structure

```
app/
  _layout.tsx      Root layout (gesture handler + navigation)
  index.tsx        Library screen
  reader.tsx       Full-screen reader
src/
  models/
    ComicBook.ts   Data model
  services/
    CBZService.ts  ZIP/CBZ extraction via JSZip
    LibraryManager.ts  Import, persist, delete, progress
  components/
    ComicCell.tsx      Library grid cell
    ZoomableImage.tsx  Pinch/double-tap zoomable image
```
