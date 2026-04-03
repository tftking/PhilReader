import React from 'react';
import { Dimensions, StyleSheet } from 'react-native';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withTiming,
  clamp,
} from 'react-native-reanimated';
import {
  Gesture,
  GestureDetector,
} from 'react-native-gesture-handler';
import { Image } from 'expo-image';

const { width: W, height: H } = Dimensions.get('window');
const MAX_SCALE = 5;

interface Props {
  uri: string;
}

export function ZoomableImage({ uri }: Props) {
  const scale = useSharedValue(1);
  const savedScale = useSharedValue(1);
  const offsetX = useSharedValue(0);
  const offsetY = useSharedValue(0);
  const savedOffsetX = useSharedValue(0);
  const savedOffsetY = useSharedValue(0);

  function resetPosition() {
    'worklet';
    scale.value = withTiming(1, { duration: 250 });
    offsetX.value = withTiming(0, { duration: 250 });
    offsetY.value = withTiming(0, { duration: 250 });
    savedScale.value = 1;
    savedOffsetX.value = 0;
    savedOffsetY.value = 0;
  }

  const pinch = Gesture.Pinch()
    .onUpdate((e) => {
      scale.value = clamp(savedScale.value * e.scale, 1, MAX_SCALE);
    })
    .onEnd(() => {
      if (scale.value <= 1) {
        resetPosition();
      } else {
        savedScale.value = scale.value;
      }
    });

  const pan = Gesture.Pan()
    .onUpdate((e) => {
      if (scale.value <= 1) return;
      const maxX = (W * (scale.value - 1)) / 2;
      const maxY = (H * (scale.value - 1)) / 2;
      offsetX.value = clamp(savedOffsetX.value + e.translationX, -maxX, maxX);
      offsetY.value = clamp(savedOffsetY.value + e.translationY, -maxY, maxY);
    })
    .onEnd(() => {
      savedOffsetX.value = offsetX.value;
      savedOffsetY.value = offsetY.value;
    });

  const doubleTap = Gesture.Tap()
    .numberOfTaps(2)
    .onEnd(() => {
      if (scale.value > 1) {
        resetPosition();
      } else {
        scale.value = withTiming(2.5, { duration: 250 });
        savedScale.value = 2.5;
      }
    });

  const composed = Gesture.Simultaneous(
    Gesture.Race(doubleTap, pan),
    pinch,
  );

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [
      { translateX: offsetX.value },
      { translateY: offsetY.value },
      { scale: scale.value },
    ],
  }));

  return (
    <GestureDetector gesture={composed}>
      <Animated.View style={styles.container}>
        <Animated.View style={[styles.imageWrapper, animatedStyle]}>
          <Image
            source={{ uri }}
            style={styles.image}
            contentFit="contain"
            transition={100}
          />
        </Animated.View>
      </Animated.View>
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  container: {
    width: W,
    height: H,
    backgroundColor: '#000',
    overflow: 'hidden',
  },
  imageWrapper: {
    width: W,
    height: H,
  },
  image: {
    width: '100%',
    height: '100%',
  },
});
