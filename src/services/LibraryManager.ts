import AsyncStorage from '@react-native-async-storage/async-storage';
import * as FileSystem from 'expo-file-system';
import { ComicBook, makeComicBook } from '../models/ComicBook';
import { countPages, extractCoverUri } from './CBZService';

const STORAGE_KEY = 'philreader.library';
const DOCS_DIR = FileSystem.documentDirectory!;

// ─── Persistence ────────────────────────────────────────────────────────────

export async function loadLibrary(): Promise<ComicBook[]> {
  try {
    const json = await AsyncStorage.getItem(STORAGE_KEY);
    return json ? JSON.parse(json) : [];
  } catch {
    return [];
  }
}

export async function saveLibrary(comics: ComicBook[]): Promise<void> {
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(comics));
}

// ─── Import ─────────────────────────────────────────────────────────────────

export interface ImportResult {
  comic?: ComicBook;
  error?: string;
}

export async function importComic(sourceUri: string, originalName: string): Promise<ImportResult> {
  const safeName = originalName.replace(/[^a-zA-Z0-9._-]/g, '_');
  const fileName = `${Date.now()}_${safeName.endsWith('.cbz') ? safeName : safeName + '.cbz'}`;
  const destUri = DOCS_DIR + fileName;

  try {
    await FileSystem.copyAsync({ from: sourceUri, to: destUri });
  } catch (e: any) {
    return { error: `Could not copy file: ${e.message}` };
  }

  try {
    const [pageCount, coverUri] = await Promise.all([
      countPages(destUri),
      extractCoverUri(destUri),
    ]);

    const title = originalName.replace(/\.cbz$/i, '').replace(/_/g, ' ');
    const comic = makeComicBook(title, fileName, pageCount, coverUri ?? undefined);
    return { comic };
  } catch (e: any) {
    await FileSystem.deleteAsync(destUri, { idempotent: true });
    return { error: `Could not read archive: ${e.message}` };
  }
}

// ─── File paths ─────────────────────────────────────────────────────────────

export function comicFileUri(comic: ComicBook): string {
  return DOCS_DIR + comic.fileName;
}

// ─── Delete ──────────────────────────────────────────────────────────────────

export async function deleteComic(comic: ComicBook, comics: ComicBook[]): Promise<ComicBook[]> {
  await FileSystem.deleteAsync(comicFileUri(comic), { idempotent: true });
  const updated = comics.filter((c) => c.id !== comic.id);
  await saveLibrary(updated);
  return updated;
}

// ─── Progress ────────────────────────────────────────────────────────────────

export async function updateProgress(
  comics: ComicBook[],
  id: string,
  page: number,
): Promise<ComicBook[]> {
  const updated = comics.map((c) => (c.id === id ? { ...c, currentPage: page } : c));
  await saveLibrary(updated);
  return updated;
}
