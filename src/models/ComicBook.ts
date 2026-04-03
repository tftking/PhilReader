export interface ComicBook {
  id: string;
  title: string;
  fileName: string;   // Stored in FileSystem.documentDirectory
  pageCount: number;
  currentPage: number;
  dateAdded: string;  // ISO string
  coverUri?: string;  // base64 data URI of cover thumbnail
}

export function makeComicBook(
  title: string,
  fileName: string,
  pageCount: number,
  coverUri?: string,
): ComicBook {
  return {
    id: Math.random().toString(36).slice(2) + Date.now().toString(36),
    title,
    fileName,
    pageCount,
    currentPage: 0,
    dateAdded: new Date().toISOString(),
    coverUri,
  };
}

export function getProgress(comic: ComicBook): number {
  if (comic.pageCount <= 1) return 0;
  return comic.currentPage / (comic.pageCount - 1);
}
