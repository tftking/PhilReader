import * as FileSystem from 'expo-file-system';
import JSZip from 'jszip';

const IMAGE_EXTS = new Set(['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff']);

function ext(path: string): string {
  return path.split('.').pop()?.toLowerCase() ?? '';
}

function mimeFor(extension: string): string {
  return extension === 'jpg' || extension === 'jpeg' ? 'image/jpeg'
    : extension === 'png' ? 'image/png'
    : extension === 'gif' ? 'image/gif'
    : extension === 'webp' ? 'image/webp'
    : 'image/jpeg';
}

function naturalSort(a: string, b: string): number {
  return a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });
}

/** Load a zip archive from a local file URI. */
export async function loadZip(fileUri: string): Promise<JSZip> {
  const base64 = await FileSystem.readAsStringAsync(fileUri, {
    encoding: FileSystem.EncodingType.Base64,
  });
  return JSZip.loadAsync(base64, { base64: true });
}

/** Return sorted image paths inside the zip. */
export function getPagePaths(zip: JSZip): string[] {
  const paths: string[] = [];
  zip.forEach((path, file) => {
    if (file.dir) return;
    if (path.includes('__MACOSX') || path.startsWith('.')) return;
    if (IMAGE_EXTS.has(ext(path))) paths.push(path);
  });
  return paths.sort(naturalSort);
}

/** Extract a single page as a base64 data URI. */
export async function extractPage(zip: JSZip, path: string): Promise<string> {
  const file = zip.file(path);
  if (!file) throw new Error(`Page not found in archive: ${path}`);
  const base64 = await file.async('base64');
  return `data:${mimeFor(ext(path))};base64,${base64}`;
}

/** Extract cover (first page) for thumbnail — loads and disposes zip. */
export async function extractCoverUri(fileUri: string): Promise<string | null> {
  try {
    const zip = await loadZip(fileUri);
    const paths = getPagePaths(zip);
    if (paths.length === 0) return null;
    return extractPage(zip, paths[0]);
  } catch {
    return null;
  }
}

/** Count pages without extracting images. */
export async function countPages(fileUri: string): Promise<number> {
  const zip = await loadZip(fileUri);
  return getPagePaths(zip).length;
}
