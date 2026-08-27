/**
 * storage.js - LocalStorage Persistence for Submarine Web
 */
const StorageService = {
  KEYS: {
    PLAYLISTS: 'submarine_web_playlists',
    HISTORY: 'submarine_web_history',
    LIKES: 'submarine_web_likes',
    AFFINITY: 'submarine_web_affinity',
    SETTINGS: 'submarine_web_settings'
  },

  // Playlists
  getPlaylists() {
    try {
      const data = localStorage.getItem(this.KEYS.PLAYLISTS);
      return data ? JSON.parse(data) : [];
    } catch (e) {
      console.error('[Storage] Error reading playlists:', e);
      return [];
    }
  },

  savePlaylist(playlist) {
    const list = this.getPlaylists();
    const idx = list.findIndex(p => p.id === playlist.id);
    if (idx !== -1) {
      list[idx] = playlist;
    } else {
      list.unshift(playlist);
    }
    localStorage.setItem(this.KEYS.PLAYLISTS, JSON.stringify(list));
  },

  deletePlaylist(playlistId) {
    const list = this.getPlaylists().filter(p => p.id !== playlistId);
    localStorage.setItem(this.KEYS.PLAYLISTS, JSON.stringify(list));
  },

  // History & Completion Tracking
  getHistory() {
    try {
      const data = localStorage.getItem(this.KEYS.HISTORY);
      return data ? JSON.parse(data) : [];
    } catch (e) {
      return [];
    }
  },

  addHistory(track, completionRate = 1.0) {
    const history = this.getHistory();
    const item = {
      videoId: track.videoId,
      title: track.title,
      artist: track.channelTitle || track.artist || 'Unknown Artist',
      thumbnail: track.thumbnailUrl || track.thumbnail || `https://i.ytimg.com/vi/${track.videoId}/hqdefault.jpg`,
      playedAt: Date.now(),
      completionRate: Math.max(0.0, Math.min(1.0, completionRate))
    };
    // Keep max 60 history items
    const updated = [item, ...history.filter(h => h.videoId !== track.videoId)].slice(0, 60);
    localStorage.setItem(this.KEYS.HISTORY, JSON.stringify(updated));
  },

  // Likes / Favorites
  getLikes() {
    try {
      const data = localStorage.getItem(this.KEYS.LIKES);
      return data ? JSON.parse(data) : [];
    } catch (e) {
      return [];
    }
  },

  toggleLike(track) {
    const likes = this.getLikes();
    const exists = likes.some(l => l.videoId === track.videoId);
    let updated;
    if (exists) {
      updated = likes.filter(l => l.videoId !== track.videoId);
    } else {
      updated = [track, ...likes];
    }
    localStorage.setItem(this.KEYS.LIKES, JSON.stringify(updated));
    return !exists;
  },

  isLiked(videoId) {
    return this.getLikes().some(l => l.videoId === videoId);
  }
};
