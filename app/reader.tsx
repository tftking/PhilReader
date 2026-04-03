import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Dimensions,
  FlatList,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Switch,
  Text,
  TouchableOpacity,
  View,
  ViewToken,
} from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import JSZip from 'jszip';

import { ComicBook } from '../src/models/ComicBook';
import { ZoomableImage } from '../src/components/ZoomableImage';
import { comicFileUri, updateProgress } from '../src/services/LibraryManager';
import { extractPage, getPagePaths, loadZip } from '../src/services/CBZService';

const { width: W } = Dimensions.get('window');

// ─── Page item (lazy loads image from zip) ──────────────────────────────────

interface PageItemProps {
  zip: JSZip;
  path: string;
  onTap: () => void;
}

function PageItem({ zip, path, onTap }: PageItemProps) {
  const [uri, setUri] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    extractPage(zip, path).then((u) => {
      if (!cancelled) setUri(u);
    });
    return () => { cancelled = true; };
  }, [zip, path]);

  if (!uri) {
    return (
      <View style={pageStyles.loading}>
        <ActivityIndicator color="#6366f1" size="large" />
      </View>
    );
  }

  return (
    <Pressable onPress={onTap}>
      <ZoomableImage uri={uri} />
    </Pressable>
  );
}

const pageStyles = StyleSheet.create({
  loading: { width: W, height: '100%', alignItems: 'center', justifyContent: 'center', backgroundColor: '#000' },
});

// ─── Main reader ─────────────────────────────────────────────────────────────

export default function ReaderScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const insets = useSafeAreaInsets();

  const [comic, setComic] = useState<ComicBook | null>(null);
  const [zip, setZip] = useState<JSZip | null>(null);
  const [pagePaths, setPagePaths] = useState<string[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [showUI, setShowUI] = useState(true);
  const [rtl, setRtl] = useState(false);
  const [showSettings, setShowSettings] = useState(false);

  const listRef = useRef<FlatList>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const library: ComicBook[] = (global as any).__philreader_library ?? [];

  // Load comic + zip
  useEffect(() => {
    const found = library.find((c) => c.id === id);
    if (!found) { setLoadError('Comic not found.'); setLoading(false); return; }
    setComic(found);

    loadZip(comicFileUri(found))
      .then((z) => {
        const paths = getPagePaths(z);
        setZip(z);
        setPagePaths(paths);
        setCurrentIndex(Math.min(found.currentPage, Math.max(0, paths.length - 1)));
      })
      .catch((e) => setLoadError(e.message))
      .finally(() => setLoading(false));
  }, [id]);

  // Scroll to saved page after zip loads
  useEffect(() => {
    if (pagePaths.length > 0 && currentIndex > 0) {
      setTimeout(() => {
        listRef.current?.scrollToIndex({ index: currentIndex, animated: false });
      }, 100);
    }
  }, [pagePaths.length]);

  // Auto-hide UI
  const scheduleHide = useCallback(() => {
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setShowUI(false), 3000);
  }, []);

  useEffect(() => { scheduleHide(); }, []);

  const toggleUI = useCallback(() => {
    setShowUI((v) => {
      if (!v) scheduleHide();
      return !v;
    });
  }, [scheduleHide]);

  // Save progress on unmount
  useEffect(() => {
    return () => {
      if (comic) {
        updateProgress(library, comic.id, currentIndex).then((updated) => {
          (global as any).__philreader_library = updated;
        });
      }
    };
  }, [comic, currentIndex]);

  const onViewableItemsChanged = useCallback(
    ({ viewableItems }: { viewableItems: ViewToken[] }) => {
      if (viewableItems.length > 0 && viewableItems[0].index != null) {
        setCurrentIndex(viewableItems[0].index);
      }
    },
    [],
  );

  const viewabilityConfig = useRef({ itemVisiblePercentThreshold: 50 }).current;

  const renderItem = useCallback(
    ({ item }: { item: string }) =>
      zip ? <PageItem zip={zip} path={item} onTap={toggleUI} /> : null,
    [zip, toggleUI],
  );

  // ─── Loading / Error states ────────────────────────────────────────────────

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#6366f1" size="large" />
        <Text style={styles.loadingText}>Loading…</Text>
      </View>
    );
  }

  if (loadError) {
    return (
      <View style={styles.center}>
        <Text style={styles.errorIcon}>⚠️</Text>
        <Text style={styles.errorTitle}>Could not open comic</Text>
        <Text style={styles.errorMsg}>{loadError}</Text>
        <TouchableOpacity style={styles.backBtn} onPress={() => router.back()}>
          <Text style={styles.backBtnText}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // ─── Reader ────────────────────────────────────────────────────────────────

  return (
    <View style={styles.container}>
      <FlatList
        ref={listRef}
        data={pagePaths}
        keyExtractor={(item) => item}
        renderItem={renderItem}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        inverted={rtl}
        onViewableItemsChanged={onViewableItemsChanged}
        viewabilityConfig={viewabilityConfig}
        windowSize={3}
        maxToRenderPerBatch={2}
        initialNumToRender={2}
        getItemLayout={(_, index) => ({ length: W, offset: W * index, index })}
      />

      {/* Overlay UI */}
      {showUI && (
        <>
          {/* Top bar */}
          <View style={[styles.topBar, { paddingTop: insets.top + 8 }]}>
            <TouchableOpacity style={styles.iconBtn} onPress={() => router.back()}>
              <Text style={styles.iconBtnText}>‹</Text>
            </TouchableOpacity>
            <Text style={styles.comicTitle} numberOfLines={1}>
              {comic?.title}
            </Text>
            <TouchableOpacity style={styles.iconBtn} onPress={() => setShowSettings(true)}>
              <Text style={styles.settingsIcon}>⋯</Text>
            </TouchableOpacity>
          </View>

          {/* Bottom bar */}
          <View style={[styles.bottomBar, { paddingBottom: insets.bottom + 8 }]}>
            <Text style={styles.pageIndicator}>
              {pagePaths.length > 0 ? `${currentIndex + 1} / ${pagePaths.length}` : ''}
            </Text>
          </View>
        </>
      )}

      {/* Settings modal */}
      <Modal
        visible={showSettings}
        transparent
        animationType="slide"
        onRequestClose={() => setShowSettings(false)}
      >
        <Pressable style={styles.modalBackdrop} onPress={() => setShowSettings(false)}>
          <View style={[styles.settingsSheet, { paddingBottom: insets.bottom + 24 }]}>
            <Text style={styles.settingsTitle}>Reader Settings</Text>
            <View style={styles.settingsRow}>
              <Text style={styles.settingsLabel}>Right-to-Left (Manga)</Text>
              <Switch
                value={rtl}
                onValueChange={setRtl}
                trackColor={{ true: '#6366f1' }}
                thumbColor="#fff"
              />
            </View>
            <TouchableOpacity
              style={styles.settingsDone}
              onPress={() => setShowSettings(false)}
            >
              <Text style={styles.settingsDoneText}>Done</Text>
            </TouchableOpacity>
          </View>
        </Pressable>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#111', gap: 12 },
  loadingText: { color: '#888', marginTop: 8 },
  errorIcon: { fontSize: 48 },
  errorTitle: { fontSize: 18, fontWeight: '700', color: '#fff' },
  errorMsg: { color: '#888', textAlign: 'center', paddingHorizontal: 32 },
  backBtn: { marginTop: 8, backgroundColor: '#6366f1', paddingHorizontal: 24, paddingVertical: 12, borderRadius: 100 },
  backBtnText: { color: '#fff', fontWeight: '700' },

  topBar: {
    position: 'absolute',
    top: 0, left: 0, right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingBottom: 12,
    backgroundColor: 'rgba(0,0,0,0.55)',
    gap: 8,
  },
  iconBtn: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center' },
  iconBtnText: { color: '#fff', fontSize: 32, lineHeight: 36, fontWeight: '300' },
  settingsIcon: { color: '#fff', fontSize: 22 },
  comicTitle: { flex: 1, color: '#fff', fontWeight: '700', fontSize: 16, textAlign: 'center' },

  bottomBar: {
    position: 'absolute',
    bottom: 0, left: 0, right: 0,
    alignItems: 'center',
    paddingTop: 12,
    backgroundColor: 'rgba(0,0,0,0.55)',
  },
  pageIndicator: { color: 'rgba(255,255,255,0.7)', fontSize: 13 },

  modalBackdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(0,0,0,0.5)' },
  settingsSheet: {
    backgroundColor: '#1e1e1e',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    padding: 24,
    gap: 20,
  },
  settingsTitle: { color: '#fff', fontSize: 18, fontWeight: '700', textAlign: 'center' },
  settingsRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  settingsLabel: { color: '#ccc', fontSize: 16 },
  settingsDone: { backgroundColor: '#6366f1', borderRadius: 100, paddingVertical: 14, alignItems: 'center' },
  settingsDoneText: { color: '#fff', fontWeight: '700', fontSize: 16 },
});
