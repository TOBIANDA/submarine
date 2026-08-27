/**
 * player.js - YouTube IFrame Audio Engine, Queue Manager & Canvas Audio Visualizer
 */
class SubmarinePlayer {
  constructor() {
    this.ytPlayer = null;
    this.isReady = false;
    this.isPlaying = false;
    this.queue = [];
    this.currentIndex = -1;
    this.isShuffle = false;
    this.repeatMode = 'all'; // 'all' (tail-to-head loop), 'one', 'none'
    this.duration = 0;
    this.currentTime = 0;
    this.volume = 80;

    // Visualizer canvas
    this.canvas = null;
    this.ctx = null;
    this.animId = null;

    this.initYouTubeApi();
    this.initVisualizer();
  }

  initYouTubeApi() {
    window.onYouTubeIframeAPIReady = () => {
      this.ytPlayer = new YT.Player('yt-player-container', {
        height: '1',
        width: '1',
        playerVars: {
          autoplay: 0,
          controls: 0,
          disablekb: 1,
          fs: 0,
          rel: 0,
          origin: window.location.origin
        },
        events: {
          onReady: () => {
            this.isReady = true;
            this.ytPlayer.setVolume(this.volume);
            console.log('[Player] YouTube IFrame API Ready.');
          },
          onStateChange: (e) => this.onPlayerStateChange(e)
        }
      });
    };

    // Load YouTube API script if not present
    if (!window.YT) {
      const tag = document.createElement('script');
      tag.src = 'https://www.youtube.com/iframe_api';
      document.head.appendChild(tag);
    }
  }

  onPlayerStateChange(event) {
    // 1 = Playing, 2 = Paused, 0 = Ended, 3 = Buffering
    if (event.data === YT.PlayerState.PLAYING) {
      this.isPlaying = true;
      this.duration = this.ytPlayer.getDuration();
      this.updatePlayPauseIcon();
      this.startProgressTicker();
      this.startVisualizer();
    } else if (event.data === YT.PlayerState.PAUSED) {
      this.isPlaying = false;
      this.updatePlayPauseIcon();
      this.stopProgressTicker();
      this.stopVisualizer();
    } else if (event.data === YT.PlayerState.ENDED) {
      this.handleTrackEnded();
    }
  }

  /**
   * Handle song finish: Tail-to-Head Loop Navigation
   */
  handleTrackEnded() {
    const current = this.currentTrack;
    if (current) {
      StorageService.addHistory(current, 1.0);
    }

    if (this.repeatMode === 'one') {
      this.seekTo(0);
      this.play();
    } else if (this.queue.length > 0) {
      // Loop from Tail back to Head!
      this.playNext();
    }
  }

  get currentTrack() {
    return this.queue[this.currentIndex] || null;
  }

  loadQueue(tracks, startIndex = 0) {
    if (!tracks || tracks.length === 0) return;
    this.queue = [...tracks];
    this.currentIndex = Math.max(0, Math.min(startIndex, this.queue.length - 1));
    this.playCurrent();
  }

  playTrack(track) {
    const idx = this.queue.findIndex(t => t.videoId === track.videoId);
    if (idx !== -1) {
      this.currentIndex = idx;
    } else {
      this.queue.unshift(track);
      this.currentIndex = 0;
    }
    this.playCurrent();
  }

  playCurrent() {
    const track = this.currentTrack;
    if (!track) return;

    // Update UI Elements
    document.getElementById('player-thumb').src = track.thumbnailUrl || track.thumbnail || `https://i.ytimg.com/vi/${track.videoId}/hqdefault.jpg`;
    document.getElementById('player-title').textContent = track.title || 'Unknown Title';
    document.getElementById('player-artist').textContent = track.channelTitle || track.artist || 'Unknown Artist';

    const likeBtn = document.getElementById('btn-like-current');
    if (likeBtn) {
      const isLiked = StorageService.isLiked(track.videoId);
      likeBtn.classList.toggle('active', isLiked);
    }

    if (this.ytPlayer && this.isReady) {
      this.ytPlayer.loadVideoById(track.videoId);
      this.ytPlayer.playVideo();
      this.isPlaying = true;
      this.updatePlayPauseIcon();
    }
  }

  play() {
    if (this.ytPlayer && this.isReady) {
      this.ytPlayer.playVideo();
      this.isPlaying = true;
      this.updatePlayPauseIcon();
    }
  }

  pause() {
    if (this.ytPlayer && this.isReady) {
      this.ytPlayer.pauseVideo();
      this.isPlaying = false;
      this.updatePlayPauseIcon();
    }
  }

  togglePlay() {
    if (this.isPlaying) {
      this.pause();
    } else {
      this.play();
    }
  }

  /**
   * Play Next with seamless wrap-around loop (Tail to Head)
   */
  playNext() {
    if (this.queue.length === 0) return;

    if (this.isShuffle) {
      this.currentIndex = Math.floor(Math.random() * this.queue.length);
    } else {
      // Modulo wraps index from length - 1 (tail) back to 0 (head)!
      this.currentIndex = (this.currentIndex + 1) % this.queue.length;
    }
    this.playCurrent();
  }

  /**
   * Play Previous with seamless wrap-around (Head to Tail)
   */
  playPrevious() {
    if (this.queue.length === 0) return;

    if (this.currentIndex > 0) {
      this.currentIndex--;
    } else {
      // Wrap from 0 back to tail!
      this.currentIndex = this.queue.length - 1;
    }
    this.playCurrent();
  }

  seekTo(seconds) {
    if (this.ytPlayer && this.isReady) {
      this.ytPlayer.seekTo(seconds, true);
      this.currentTime = seconds;
    }
  }

  setVolume(val) {
    this.volume = Math.max(0, Math.min(100, val));
    if (this.ytPlayer && this.isReady) {
      this.ytPlayer.setVolume(this.volume);
    }
  }

  toggleShuffle() {
    this.isShuffle = !this.isShuffle;
    const btn = document.getElementById('btn-shuffle');
    if (btn) btn.classList.toggle('active', this.isShuffle);
  }

  toggleRepeat() {
    if (this.repeatMode === 'all') this.repeatMode = 'one';
    else if (this.repeatMode === 'one') this.repeatMode = 'none';
    else this.repeatMode = 'all';

    const btn = document.getElementById('btn-repeat');
    if (btn) {
      btn.classList.toggle('active', this.repeatMode !== 'none');
      btn.title = `Repeat: ${this.repeatMode.toUpperCase()}`;
    }
  }

  updatePlayPauseIcon() {
    const btn = document.getElementById('btn-play-pause');
    if (!btn) return;
    if (this.isPlaying) {
      btn.innerHTML = `<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>`;
    } else {
      btn.innerHTML = `<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>`;
    }
  }

  startProgressTicker() {
    this.stopProgressTicker();
    this.progressInterval = setInterval(() => {
      if (this.ytPlayer && this.isPlaying) {
        this.currentTime = this.ytPlayer.getCurrentTime() || 0;
        this.duration = this.ytPlayer.getDuration() || 0;

        const slider = document.getElementById('seek-slider');
        const timeCur = document.getElementById('time-current');
        const timeDur = document.getElementById('time-duration');

        if (slider && this.duration > 0) {
          slider.value = (this.currentTime / this.duration) * 100;
        }
        if (timeCur) timeCur.textContent = this.formatTime(this.currentTime);
        if (timeDur) timeDur.textContent = this.formatTime(this.duration);
      }
    }, 500);
  }

  stopProgressTicker() {
    if (this.progressInterval) clearInterval(this.progressInterval);
  }

  formatTime(secs) {
    if (isNaN(secs) || secs < 0) return '0:00';
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  // ==========================================
  // Audio Waveform Visualizer
  // ==========================================
  initVisualizer() {
    this.canvas = document.getElementById('visualizer-canvas');
    if (!this.canvas) return;
    this.ctx = this.canvas.getContext('2d');
    this.resizeCanvas();
    window.addEventListener('resize', () => this.resizeCanvas());
  }

  resizeCanvas() {
    if (this.canvas) {
      this.canvas.width = window.innerWidth;
      this.canvas.height = window.innerHeight;
    }
  }

  startVisualizer() {
    if (!this.ctx) return;
    this.stopVisualizer();

    let step = 0;
    const draw = () => {
      this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
      const width = this.canvas.width;
      const height = this.canvas.height;
      const bars = 48;
      const barWidth = width / bars;

      for (let i = 0; i < bars; i++) {
        const heightMultiplier = Math.sin(step * 0.05 + i * 0.25) * 0.5 + 0.5;
        const barHeight = heightMultiplier * (height * 0.35);

        const gradient = this.ctx.createLinearGradient(0, height, 0, height - barHeight);
        gradient.addColorStop(0, 'rgba(0, 242, 254, 0.6)');
        gradient.addColorStop(1, 'rgba(79, 172, 254, 0.05)');

        this.ctx.fillStyle = gradient;
        this.ctx.fillRect(i * barWidth, height - barHeight, barWidth - 4, barHeight);
      }

      step++;
      this.animId = requestAnimationFrame(draw);
    };
    draw();
  }

  stopVisualizer() {
    if (this.animId) {
      cancelAnimationFrame(this.animId);
      this.animId = null;
    }
    if (this.ctx && this.canvas) {
      this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    }
  }
}

// Global instance
window.submarinePlayer = new SubmarinePlayer();
