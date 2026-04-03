import React, { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Dimensions,
  FlatList,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import * as DocumentPicker from 'expo-document-picker';
import { router } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { ComicBook } from '../src/models/ComicBook';
import { ComicCell } from '../src/components/ComicCell';
import {
  deleteComic,
  importComic,
  loadLibrary,
  saveLibrary,
} from '../src/services/LibraryManager';

const PADDING = 16;
const COLUMNS = 2;

export default function LibraryScreen() {
  const insets = useSafeAreaInsets();
  const [comics, setComics] = useState<ComicBook[]>([]);
  const [importing, setImporting] = useState(false);
  const [loaded, setLoaded] = useState(false);

  const cellWidth =
    (Dimensions.get('window').width - PADDING * 2 - (COLUMNS - 1) * 12) / COLUMNS;

  useEffect(() => {
    loadLibrary().then((saved) => {
      setComics(saved);
      setLoaded(true);
    });
  }, []);

  const handleImport = useCallback(async () => {
    const result = await DocumentPicker.getDocumentAsync({
      type: ['application/x-cbz', 'application/zip', 'public.zip-archive', '*/*'],
      multiple: true,
      copyToCacheDirectory: true,
    });
    if (result.canceled) return;

    setImporting(true);
    const newComics: ComicBook[] = [];

    for (const asset of result.assets) {
      const { comic, error } = await importComic(asset.uri, asset.name);
      if (comic) newComics.push(comic);
      else if (error) Alert.alert('Import Failed', error);
    }

    if (newComics.length > 0) {
      const updated = [...newComics, ...comics];
      setComics(updated);
      await saveLibrary(updated);
    }
    setImporting(false);
  }, [comics]);

  const handleLongPress = useCallback(
    (comic: ComicBook) => {
      Alert.alert(comic.title, 'What would you like to do?', [
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            const updated = await deleteComic(comic, comics);
            setComics(updated);
          },
        },
        { text: 'Cancel', style: 'cancel' },
      ]);
    },
    [comics],
  );

  const handleOpen = useCallback((comic: ComicBook) => {
    router.push({ pathname: '/reader', params: { id: comic.id } });
  }, []);

  // Pass comics via a global store approach — simpler than URL params for large data
  useEffect(() => {
    (global as any).__philreader_library = comics;
  }, [comics]);

  const renderItem = useCallback(
    ({ item, index }: { item: ComicBook; index: number }) => (
      <View style={{ marginLeft: index % 2 === 1 ? 12 : 0 }}>
        <ComicCell
          comic={item}
          width={cellWidth}
          onPress={() => handleOpen(item)}
          onLongPress={() => handleLongPress(item)}
        />
      </View>
    ),
    [cellWidth, handleOpen, handleLongPress],
  );

  if (!loaded) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#6366f1" size="large" />
      </View>
    );
  }

  return (
    <View style={[styles.container, { paddingBottom: insets.bottom }]}>
      {comics.length === 0 ? (
        <View style={styles.empty}>
          <Text style={styles.emptyIcon}>📚</Text>
          <Text style={styles.emptyTitle}>No Comics Yet</Text>
          <Text style={styles.emptySubtitle}>
            Tap + to import a .cbz file{'\n'}or open one from the Files app.
          </Text>
          <TouchableOpacity style={styles.importBtn} onPress={handleImport}>
            <Text style={styles.importBtnText}>Import Comic</Text>
          </TouchableOpacity>
        </View>
      ) : (
        <FlatList
          data={comics}
          keyExtractor={(item) => item.id}
          renderItem={renderItem}
          numColumns={COLUMNS}
          contentContainerStyle={styles.grid}
          showsVerticalScrollIndicator={false}
        />
      )}

      {/* FAB */}
      <TouchableOpacity
        style={[styles.fab, { bottom: insets.bottom + 24 }]}
        onPress={handleImport}
        disabled={importing}
      >
        {importing ? (
          <ActivityIndicator color="#fff" size="small" />
        ) : (
          <Text style={styles.fabIcon}>+</Text>
        )}
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#111' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#111' },
  grid: { padding: PADDING, paddingBottom: 100 },
  empty: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
    gap: 12,
  },
  emptyIcon: { fontSize: 64 },
  emptyTitle: { fontSize: 22, fontWeight: '700', color: '#fff' },
  emptySubtitle: { fontSize: 14, color: '#888', textAlign: 'center', lineHeight: 22 },
  importBtn: {
    marginTop: 8,
    backgroundColor: '#6366f1',
    paddingHorizontal: 28,
    paddingVertical: 14,
    borderRadius: 100,
  },
  importBtnText: { color: '#fff', fontWeight: '700', fontSize: 16 },
  fab: {
    position: 'absolute',
    right: 24,
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: '#6366f1',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#6366f1',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.5,
    shadowRadius: 8,
    elevation: 8,
  },
  fabIcon: { color: '#fff', fontSize: 28, lineHeight: 30, fontWeight: '300' },
});
