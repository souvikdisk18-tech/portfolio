/**
 * Ultra-Smooth Scroll Video Scrubbing Engine
 * Pure canvas implementation with frame interpolation
 */
(function () {
  'use strict';

  const TOTAL_FRAMES = 240;
  const FRAME_DIR = 'without_watermark_frames_24fps';
  const FRAME_PREFIX = 'frame_';
  const FRAME_EXT = '.jpg';
  const LERP_FACTOR = 0.12; // Smooth deceleration momentum

  const canvas = document.getElementById('animation-canvas');
  const ctx = canvas.getContext('2d', { alpha: false, desynchronized: true });

  const images = new Array(TOTAL_FRAMES);
  const loaded = new Array(TOTAL_FRAMES).fill(false);

  let targetProgress = 0;
  let currentProgress = 0;
  let currentFrameIndex = 0;
  let lastDrawnIndex = -1;
  let isResizing = false;

  // Build frame file path: 0 -> frame_00001.jpg
  function getFrameUrl(index) {
    const num = String(index + 1).padStart(5, '0');
    return `${FRAME_DIR}/${FRAME_PREFIX}${num}${FRAME_EXT}`;
  }

  // Calculate normalized scroll progress [0, 1]
  function calculateScrollProgress() {
    const doc = document.documentElement;
    const scrollY = window.pageYOffset || doc.scrollTop || document.body.scrollTop || 0;
    const maxScroll = doc.scrollHeight - window.innerHeight;
    return maxScroll > 0 ? Math.min(1, Math.max(0, scrollY / maxScroll)) : 0;
  }

  // Handle High-DPI Canvas Resizing Dynamically (Desktop & Mobile)
  function resizeCanvas() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const width = window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || window.screen.width;
    const height = window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight || window.screen.height;

    const targetWidth = Math.max(1, Math.floor(width * dpr));
    const targetHeight = Math.max(1, Math.floor(height * dpr));

    if (canvas.width !== targetWidth || canvas.height !== targetHeight) {
      canvas.width = targetWidth;
      canvas.height = targetHeight;
    }
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';

    lastDrawnIndex = -1;
    drawFrame(currentFrameIndex);
  }

  // Draw target frame with strict "object-fit: cover" logic & aspect ratio preservation
  function drawFrame(index) {
    let img = images[index];
    const isExactLoaded = loaded[index] && img && img.complete && img.naturalWidth > 0;

    if (!isExactLoaded) {
      // Find nearest loaded frame to eliminate any blank flashes
      let closest = -1;
      let minDiff = Infinity;
      for (let i = 0; i < TOTAL_FRAMES; i++) {
        if (loaded[i] && images[i] && images[i].complete && images[i].naturalWidth > 0) {
          const diff = Math.abs(i - index);
          if (diff < minDiff) {
            minDiff = diff;
            closest = i;
          }
        }
      }
      if (closest !== -1) {
        img = images[closest];
      } else {
        return; // No frames loaded yet
      }
    }

    const cw = canvas.width;
    const ch = canvas.height;
    if (cw === 0 || ch === 0) return;

    const iw = img.naturalWidth || 848;
    const ih = img.naturalHeight || 480;

    // True "object-fit: cover" logic for all viewports (Mobile Portrait & Desktop Landscape):
    // Scale so both width and height fully cover 100vw and 100vh without distortion or stretching
    const hRatio = cw / iw;
    const vRatio = ch / ih;
    const ratio = Math.max(hRatio, vRatio);

    const drawW = iw * ratio;
    const drawH = ih * ratio;

    // Center crop offsets: keeps the main subject/face centered in mobile portrait mode
    const drawX = (cw - drawW) / 2;
    const drawY = (ch - drawH) / 2;

    ctx.fillStyle = '#000000';
    ctx.fillRect(0, 0, cw, ch);
    ctx.drawImage(img, drawX, drawY, drawW, drawH);

    if (isExactLoaded) {
      lastDrawnIndex = index;
    } else {
      lastDrawnIndex = -1;
    }
  }

  // Continuous animation frame loop with smooth lerp
  function renderLoop() {
    const delta = targetProgress - currentProgress;
    if (Math.abs(delta) < 0.00005) {
      currentProgress = targetProgress;
    } else {
      currentProgress += delta * LERP_FACTOR;
    }

    const targetFrameFloat = currentProgress * (TOTAL_FRAMES - 1);
    const targetFrame = Math.min(TOTAL_FRAMES - 1, Math.max(0, Math.round(targetFrameFloat)));

    if (targetFrame !== currentFrameIndex || targetFrame !== lastDrawnIndex) {
      currentFrameIndex = targetFrame;
      drawFrame(currentFrameIndex);
    }

    requestAnimationFrame(renderLoop);
  }

  // Preload all frames
  function preloadImages() {
    // 1. Immediately load frame 0 for instant visual display
    const firstImg = new Image();
    firstImg.onload = () => {
      loaded[0] = true;
      resizeCanvas();
    };
    firstImg.src = getFrameUrl(0);
    images[0] = firstImg;

    if (firstImg.complete && firstImg.naturalWidth > 0) {
      loaded[0] = true;
      resizeCanvas();
    }

    // 2. Preload remaining frames
    for (let i = 1; i < TOTAL_FRAMES; i++) {
      const img = new Image();
      img.onload = () => {
        loaded[i] = true;
        if (i === currentFrameIndex) {
          drawFrame(i);
        }
      };
      img.src = getFrameUrl(i);
      images[i] = img;

      if (img.complete && img.naturalWidth > 0) {
        loaded[i] = true;
      }
    }
  }

  // Keyboard navigation support
  window.addEventListener('keydown', (e) => {
    const step = window.innerHeight * 0.4;
    if (e.key === 'ArrowDown' || e.key === 'PageDown' || e.key === ' ') {
      window.scrollBy({ top: step, behavior: 'smooth' });
    } else if (e.key === 'ArrowUp' || e.key === 'PageUp') {
      window.scrollBy({ top: -step, behavior: 'smooth' });
    } else if (e.key === 'Home') {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } else if (e.key === 'End') {
      window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'smooth' });
    }
  });

  // Event Listeners (Scroll, Touch, Resize & Mobile Orientation)
  window.addEventListener('scroll', () => {
    targetProgress = calculateScrollProgress();
  }, { passive: true });

  window.addEventListener('touchmove', () => {
    targetProgress = calculateScrollProgress();
  }, { passive: true });

  window.addEventListener('resize', () => {
    if (!isResizing) {
      isResizing = true;
      requestAnimationFrame(() => {
        resizeCanvas();
        targetProgress = calculateScrollProgress();
        isResizing = false;
      });
    }
  }, { passive: true });

  // Handle Mobile Orientation changes smoothly across iOS & Android
  window.addEventListener('orientationchange', () => {
    resizeCanvas();
    targetProgress = calculateScrollProgress();
    setTimeout(() => {
      resizeCanvas();
      targetProgress = calculateScrollProgress();
    }, 150);
    setTimeout(() => {
      resizeCanvas();
      targetProgress = calculateScrollProgress();
    }, 350);
  }, { passive: true });

  // Initialize
  preloadImages();
  resizeCanvas();
  targetProgress = calculateScrollProgress();
  currentProgress = targetProgress;
  requestAnimationFrame(renderLoop);
})();
