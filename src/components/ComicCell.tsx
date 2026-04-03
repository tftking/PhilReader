import React from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { Image } from 'expo-image';
import { ComicBook, getProgress } from '../models/ComicBook';

interface Props {
  comic: ComicBook;
  onPress: () => void;
  onLongPress: () => void;
  width: number;
}

export function ComicCell({ comic, onPress, onLongPress, width }: Props) {
  const progress = getProgress(comic);
  const coverHeight = width * 1.4;

  return (
    <TouchableOpacity
      style={[styles.container, { width }]}
      onPress={onPress}
      onLongPress={onLongPress}
      activeOpacity={0.75}
    >
      <View style={[styles.coverWrapper, { height: coverHeight }]}>
        {comic.coverUri ? (
          <Image
            source={{ uri: comic.coverUri }}
            style={styles.cover}
            contentFit="cover"
            transition={200}
          />
        ) : (
          <View style={styles.placeholder}>
            <Text style={styles.placeholderIcon}>📖</Text>
          </View>
        )}

        {progress > 0 && (
          <View style={styles.badgeContainer}>
            <Text style={styles.badgeText}>{Math.round(progress * 100)}%</Text>
          </View>
        )}

        {/* Progress bar at bottom of cover */}
        {progress > 0 && (
          <View style={styles.progressTrack}>
            <View style={[styles.progressFill, { width: `${progress * 100}%` }]} />
          </View>
        )}
      </View>

      <Text style={styles.title} numberOfLines={2}>{comic.title}</Text>
      {comic.pageCount > 0 && (
        <Text style={styles.subtitle}>
          {comic.currentPage + 1} / {comic.pageCount}
        </Text>
      )}
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: 16,
  },
  coverWrapper: {
    borderRadius: 8,
    overflow: 'hidden',
    backgroundColor: '#1e1e1e',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 4,
    elevation: 4,
  },
  cover: {
    width: '100%',
    height: '100%',
  },
  placeholder: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  placeholderIcon: {
    fontSize: 40,
  },
  badgeContainer: {
    position: 'absolute',
    top: 6,
    right: 6,
    backgroundColor: 'rgba(0,0,0,0.65)',
    borderRadius: 10,
    paddingHorizontal: 7,
    paddingVertical: 2,
  },
  badgeText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: '700',
  },
  progressTrack: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 3,
    backgroundColor: 'rgba(255,255,255,0.2)',
  },
  progressFill: {
    height: 3,
    backgroundColor: '#6366f1',
  },
  title: {
    marginTop: 6,
    fontSize: 13,
    fontWeight: '600',
    color: '#f0f0f0',
  },
  subtitle: {
    fontSize: 11,
    color: '#888',
    marginTop: 2,
  },
});
