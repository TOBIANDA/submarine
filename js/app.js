/**
 * Default Curated Hit Tracks by Category for Instant 0-lag Rendering
 */
const CURATED_TRACKS = {
  all: [
    { videoId: "d-diB65654g", title: "Coldplay - Viva La Vida", channelTitle: "Coldplay", thumbnailUrl: "https://i.ytimg.com/vi/d-diB65654g/hqdefault.jpg" },
    { videoId: "K0ibBPhiaG0", title: "Ed Sheeran - Castle On The Hill", channelTitle: "Ed Sheeran", thumbnailUrl: "https://i.ytimg.com/vi/K0ibBPhiaG0/hqdefault.jpg" },
    { videoId: "jGflCSowWQ4", title: "One Direction - Night Changes", channelTitle: "One Direction", thumbnailUrl: "https://i.ytimg.com/vi/jGflCSowWQ4/hqdefault.jpg" },
    { videoId: "QGJuMBdaqIw", title: "One Direction - What Makes You Beautiful", channelTitle: "One Direction", thumbnailUrl: "https://i.ytimg.com/vi/QGJuMBdaqIw/hqdefault.jpg" },
    { videoId: "450p7goxZqg", title: "John Legend - All of Me", channelTitle: "John Legend", thumbnailUrl: "https://i.ytimg.com/vi/450p7goxZqg/hqdefault.jpg" },
    { videoId: "RBumgq5yVrA", title: "Passenger - Let Her Go", channelTitle: "Passenger", thumbnailUrl: "https://i.ytimg.com/vi/RBumgq5yVrA/hqdefault.jpg" },
    { videoId: "hT_nvWreIhg", title: "OneRepublic - Counting Stars", channelTitle: "OneRepublic", thumbnailUrl: "https://i.ytimg.com/vi/hT_nvWreIhg/hqdefault.jpg" },
    { videoId: "fJ9rUzIMcZQ", title: "Queen - Bohemian Rhapsody", channelTitle: "Queen Official", thumbnailUrl: "https://i.ytimg.com/vi/fJ9rUzIMcZQ/hqdefault.jpg" }
  ],
  trending: [
    { videoId: "0bAtr47_O4I", title: "Anne Wilson - My Jesus (Official Music Video)", channelTitle: "Anne Wilson", thumbnailUrl: "https://i.ytimg.com/vi/0bAtr47_O4I/hqdefault.jpg" },
    { videoId: "yKNxeF4KMsY", title: "Coldplay - Yellow (Official Video)", channelTitle: "Coldplay", thumbnailUrl: "https://i.ytimg.com/vi/yKNxeF4KMsY/hqdefault.jpg" },
    { videoId: "kJQP7kiw5Fk", title: "Luis Fonsi - Despacito ft. Daddy Yankee", channelTitle: "Luis Fonsi", thumbnailUrl: "https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg" },
    { videoId: "CevxZvSJLk8", title: "Katy Perry - Roar (Official)", channelTitle: "Katy Perry", thumbnailUrl: "https://i.ytimg.com/vi/CevxZvSJLk8/hqdefault.jpg" }
  ],
  pop: [
    { videoId: "WcIcVapfqXw", title: "One Direction - Story of My Life", channelTitle: "One Direction", thumbnailUrl: "https://i.ytimg.com/vi/WcIcVapfqXw/hqdefault.jpg" },
    { videoId: "4NRXx6U8ABQ", title: "The Weeknd - Blinding Lights", channelTitle: "The Weeknd", thumbnailUrl: "https://i.ytimg.com/vi/4NRXx6U8ABQ/hqdefault.jpg" },
    { videoId: "fKopy74weus", title: "Imagine Dragons - Thunder", channelTitle: "Imagine Dragons", thumbnailUrl: "https://i.ytimg.com/vi/fKopy74weus/hqdefault.jpg" },
    { videoId: "papuvlVeZg8", title: "Ed Sheeran - Shape of You", channelTitle: "Ed Sheeran", thumbnailUrl: "https://i.ytimg.com/vi/papuvlVeZg8/hqdefault.jpg" }
  ],
  acoustic: [
    { videoId: "d-diB65654g", title: "Coldplay - Viva La Vida", channelTitle: "Coldplay", thumbnailUrl: "https://i.ytimg.com/vi/d-diB65654g/hqdefault.jpg" },
    { videoId: "RBumgq5yVrA", title: "Passenger - Let Her Go", channelTitle: "Passenger", thumbnailUrl: "https://i.ytimg.com/vi/RBumgq5yVrA/hqdefault.jpg" },
    { videoId: "hLQl3WQQoQ0", title: "Adele - Someone Like You", channelTitle: "Adele", thumbnailUrl: "https://i.ytimg.com/vi/hLQl3WQQoQ0/hqdefault.jpg" },
    { videoId: "rtOvBOTyX00", title: "Christina Perri - A Thousand Years", channelTitle: "Christina Perri", thumbnailUrl: "https://i.ytimg.com/vi/rtOvBOTyX00/hqdefault.jpg" }
  ],
  rock: [
    { videoId: "fJ9rUzIMcZQ", title: "Queen - Bohemian Rhapsody", channelTitle: "Queen Official", thumbnailUrl: "https://i.ytimg.com/vi/fJ9rUzIMcZQ/hqdefault.jpg" },
    { videoId: "kXYiU_JCYtU", title: "Linkin Park - Numb", channelTitle: "Linkin Park", thumbnailUrl: "https://i.ytimg.com/vi/kXYiU_JCYtU/hqdefault.jpg" },
    { videoId: "1w7OgIMMRc4", title: "Guns N' Roses - Sweet Child O' Mine", channelTitle: "Guns N' Roses", thumbnailUrl: "https://i.ytimg.com/vi/1w7OgIMMRc4/hqdefault.jpg" }
  ],
  rnb: [
    { videoId: "450p7goxZqg", title: "John Legend - All of Me", channelTitle: "John Legend", thumbnailUrl: "https://i.ytimg.com/vi/450p7goxZqg/hqdefault.jpg" },
    { videoId: "JGwWNGJdvx8", title: "Ed Sheeran - Thinking Out Loud", channelTitle: "Ed Sheeran", thumbnailUrl: "https://i.ytimg.com/vi/JGwWNGJdvx8/hqdefault.jpg" },
    { videoId: "fRh_vgS2dFE", title: "Justin Bieber - Sorry", channelTitle: "Justin Bieber", thumbnailUrl: "https://i.ytimg.com/vi/fRh_vgS2dFE/hqdefault.jpg" }
  ]
};

// YouTube API Keys for Web Search
const YT_API_KEYS = [
  'AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc',
  'AIzaSyAR4ZPC4-u95VkZnbh5VSbhtnCqhQgOgBU',
  'AIzaSyB0lBp6unUVBMvSFBGWYI5cUMJWDwZBqJk',
  'AIzaSyD0VG-fLG4xS1ASGzcZwCLFJi644YHpWmk',
  'AIzaSyC-2SQtaBNnuyfc8oQKnAawpQxjAcJoj8U'
];
let ytKeyIdx = 0;
function getYoutubeApiKey() {
  return YT_API_KEYS[ytKeyIdx % YT_API_KEYS.length];
}

// Global App State
const AppState = {
  currentCategory: 'all',
  currentTab: 'home',
  searchResults: [],
  popularTracks: [],
  recommendedTracks: []
};

// ==========================================
// Initialization
// ==========================================
document.addEventListener('DOMContentLoaded', () => {
  initEventListeners();
  loadInitialMusic();
});

function initEventListeners() {
  // Navigation Tabs
  document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const tab = item.dataset.tab;
      switchTab(tab);
    });
  });

  // Search Input
  const searchInput = document.getElementById('search-input');
  let debounceTimer;
  searchInput.addEventListener('input', (e) => {
    clearTimeout(debounceTimer);
    const query = e.target.value.trim();
    if (query.length > 1) {
      debounceTimer = setTimeout(() => searchMusic(query), 400);
    } else if (query.length === 0) {
      renderTracks(AppState.popularTracks);
    }
  });

  // Category Pills
  document.querySelectorAll('.pill-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.pill-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      AppState.currentCategory = btn.dataset.category;
      onCategoryChanged(AppState.currentCategory);
    });
  });

  // AI Creator Modal
  document.getElementById('btn-open-ai-modal').addEventListener('click', openAiModal);
  document.getElementById('btn-close-ai-modal').addEventListener('click', closeAiModal);
  document.getElementById('btn-generate-ai').addEventListener('click', handleAiGenerate);

  // Player Controls
  document.getElementById('btn-play-pause').addEventListener('click', () => window.submarinePlayer.togglePlay());
  document.getElementById('btn-next').addEventListener('click', () => window.submarinePlayer.playNext());
  document.getElementById('btn-prev').addEventListener('click', () => window.submarinePlayer.playPrevious());
  document.getElementById('btn-shuffle').addEventListener('click', () => window.submarinePlayer.toggleShuffle());
  document.getElementById('btn-repeat').addEventListener('click', () => window.submarinePlayer.toggleRepeat());

  // Seek Slider
  const seekSlider = document.getElementById('seek-slider');
  seekSlider.addEventListener('input', (e) => {
    const percent = parseFloat(e.target.value);
    const dur = window.submarinePlayer.duration;
    if (dur > 0) {
      const targetSecs = (percent / 100) * dur;
      window.submarinePlayer.seekTo(targetSecs);
    }
  });

  // Volume Slider
  const volSlider = document.getElementById('volume-slider');
  volSlider.addEventListener('input', (e) => {
    window.submarinePlayer.setVolume(parseInt(e.target.value));
  });

  // Like current song
  document.getElementById('btn-like-current').addEventListener('click', () => {
    const cur = window.submarinePlayer.currentTrack;
    if (cur) {
      const liked = StorageService.toggleLike(cur);
      document.getElementById('btn-like-current').classList.toggle('active', liked);
      showToast(liked ? 'Disimpan ke Favorit ❤️' : 'Dihapus dari Favorit');
    }
  });
}

// ==========================================
// Navigation & Views
// ==========================================
function switchTab(tabName) {
  AppState.currentTab = tabName;
  document.querySelectorAll('.nav-item').forEach(item => {
    item.classList.toggle('active', item.dataset.tab === tabName);
  });

  const mainTitle = document.getElementById('main-section-title');
  const heroBanner = document.getElementById('hero-banner');

  if (tabName === 'home') {
    heroBanner.style.display = 'block';
    mainTitle.textContent = '🔥 Musik Populer & Trending';
    renderTracks(AppState.popularTracks);
  } else if (tabName === 'explore') {
    heroBanner.style.display = 'none';
    mainTitle.textContent = '✨ Eksplorasi Musik & Genre';
    onCategoryChanged('trending');
  } else if (tabName === 'recommendation') {
    heroBanner.style.display = 'none';
    mainTitle.textContent = '🧠 Disarankan Untukmu (Last.fm ML Graph)';
    loadSmartRecommendations();
  } else if (tabName === 'library') {
    heroBanner.style.display = 'none';
    mainTitle.textContent = '📚 Koleksi Playlist & Favorit Kamu';
    renderLibrary();
  }
}

// ==========================================
// Music Data Fetching
// ==========================================
async function searchMusic(query, limit = 16) {
  const container = document.getElementById('tracks-container');

  try {
    const key = getYoutubeApiKey();
    const url = `https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&videoCategoryId=10&maxResults=${limit}&q=${encodeURIComponent(query)}&key=${key}`;
    const res = await fetch(url, { signal: AbortSignal.timeout(4000) });
    if (!res.ok) throw new Error(`YouTube API HTTP ${res.status}`);
    
    const data = await res.json();
    if (data.items && data.items.length > 0) {
      AppState.searchResults = data.items.map(item => ({
        videoId: item.id.videoId,
        title: item.snippet.title,
        channelTitle: item.snippet.channelTitle,
        thumbnailUrl: item.snippet.thumbnails.high?.url || item.snippet.thumbnails.medium?.url
      }));
      renderTracks(AppState.searchResults);
      return;
    }
  } catch (err) {
    ytKeyIdx++;
    console.warn('[Search] YouTube API failed, using curated query matches:', err);
  }

  // Fallback: search local curated pool
  const qLower = query.toLowerCase();
  const allCurated = Object.values(CURATED_TRACKS).flat();
  const matched = allCurated.filter(t => t.title.toLowerCase().includes(qLower) || t.channelTitle.toLowerCase().includes(qLower));
  
  if (matched.length > 0) {
    renderTracks(matched);
  } else {
    // If no direct keyword match, fallback to 'all' curated
    renderTracks(CURATED_TRACKS.all);
  }
}

function loadInitialMusic() {
  AppState.popularTracks = [...CURATED_TRACKS.all];
  renderTracks(AppState.popularTracks);
}

function onCategoryChanged(cat) {
  const tracks = CURATED_TRACKS[cat] || CURATED_TRACKS.all;
  renderTracks(tracks);
}

// ==========================================
// ML Recommendation System
// ==========================================
async function loadSmartRecommendations() {
  const container = document.getElementById('tracks-container');
  container.innerHTML = '<div style="color: var(--accent-cyan); padding: 20px;">Memproses Last.fm Similarity Graph... 🧠</div>';

  const history = StorageService.getHistory();
  let seedArtist = 'Ed Sheeran';
  let seedTrack = 'Castle on the Hill';

  if (history.length > 0) {
    const top = history[0];
    seedArtist = top.artist || seedArtist;
    seedTrack = top.title || seedTrack;
  }

  try {
    const candidates = await RecommendationEngine.getSimilarTracks(seedArtist, seedTrack, 12);
    const ranked = RecommendationEngine.rankCandidates(candidates);

    if (ranked.length > 0) {
      // Map candidate titles to searchable track items
      const resolved = ranked.slice(0, 8).map(c => {
        const found = CURATED_TRACKS.all.find(t => t.title.toLowerCase().includes(c.title.toLowerCase()));
        return found || {
          videoId: 'd-diB65654g', // Safe fallback ID
          title: `${c.title} - ${c.artist}`,
          channelTitle: c.artist,
          thumbnailUrl: 'https://i.ytimg.com/vi/d-diB65654g/hqdefault.jpg'
        };
      });

      AppState.recommendedTracks = resolved;
      renderTracks(resolved);
      return;
    }
  } catch (err) {
    console.error('[ML Recommendations] Error:', err);
  }

  renderTracks(CURATED_TRACKS.acoustic);
}

// ==========================================
// Render Track Grid
// ==========================================
function renderTracks(tracks) {
  const container = document.getElementById('tracks-container');
  if (!tracks || tracks.length === 0) {
    container.innerHTML = '<div style="color: var(--text-muted); padding: 20px;">Tidak ada lagu ditemukan.</div>';
    return;
  }

  container.innerHTML = tracks.map((track, idx) => `
    <div class="music-card" onclick="playTrackAt(${idx})">
      <div class="card-image-wrap">
        <img class="card-image" src="${track.thumbnailUrl || `https://i.ytimg.com/vi/${track.videoId}/hqdefault.jpg`}" alt="${escapeHtml(track.title)}" loading="lazy" />
        <div class="card-play-hover">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
        </div>
      </div>
      <div class="card-song-title">${escapeHtml(track.title)}</div>
      <div class="card-song-artist">${escapeHtml(track.channelTitle || track.artist || 'Unknown Artist')}</div>
    </div>
  `).join('');

  // Store current active list in window for indexing
  window.currentRenderedTracks = tracks;
}

window.playTrackAt = function(index) {
  if (window.currentRenderedTracks && window.currentRenderedTracks[index]) {
    window.submarinePlayer.loadQueue(window.currentRenderedTracks, index);
    showToast(`Memutar: ${window.currentRenderedTracks[index].title}`);
  }
};

// ==========================================
// Library View (Playlists & Favorites)
// ==========================================
function renderLibrary() {
  const container = document.getElementById('tracks-container');
  const likes = StorageService.getLikes();

  let html = `
    <div style="grid-column: 1 / -1; margin-bottom: 24px;">
      <h3 style="font-family: var(--font-heading); margin-bottom: 12px;">❤️ Lagu Favorit (${likes.length})</h3>
    </div>
  `;

  if (likes.length > 0) {
    html += likes.map((track, idx) => `
      <div class="track-card" onclick="playLikedTrack(${idx})">
        <div class="card-thumb-wrap">
          <img class="card-thumb" src="${track.thumbnailUrl}" alt="${escapeHtml(track.title)}" />
          <div class="play-hover-btn"><svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor"><path d="M8 5v14l11-7z"/></svg></div>
        </div>
        <div class="card-title">${escapeHtml(track.title)}</div>
        <div class="card-artist">${escapeHtml(track.channelTitle || track.artist || '')}</div>
      </div>
    `).join('');
  } else {
    html += `<div style="grid-column: 1 / -1; color: var(--text-muted);">Belum ada lagu favorit yang disimpan. Tekan tombol hati saat memutar lagu!</div>`;
  }

  container.innerHTML = html;
  window.currentRenderedTracks = likes;
}

window.playLikedTrack = function(index) {
  const likes = StorageService.getLikes();
  if (likes[index]) {
    window.submarinePlayer.loadQueue(likes, index);
  }
};

// ==========================================
// AI Playlist Modal
// ==========================================
function openAiModal() {
  document.getElementById('ai-modal').classList.add('open');
}

function closeAiModal() {
  document.getElementById('ai-modal').classList.remove('open');
}

async function handleAiGenerate() {
  const input = document.getElementById('ai-prompt-input');
  const prompt = input.value.trim();
  if (!prompt) return;

  const btn = document.getElementById('btn-generate-ai');
  btn.disabled = true;
  btn.textContent = 'Memproses Kurasi AI & Last.fm... ⏳';

  try {
    const result = await AiService.curatePlaylist(prompt);
    showToast(result.message);

    // Map AI parsed songs to player format
    const resolvedTracks = result.songs.map((song, idx) => {
      const match = CURATED_TRACKS.all[idx % CURATED_TRACKS.all.length];
      return {
        videoId: match.videoId,
        title: `${song.title} - ${song.artist}`,
        channelTitle: song.artist,
        thumbnailUrl: match.thumbnailUrl
      };
    });

    if (resolvedTracks.length > 0) {
      closeAiModal();
      input.value = '';
      
      // Save AI Playlist to local storage
      const playlist = {
        id: 'ai_' + Date.now(),
        title: prompt.slice(0, 30) + ' (AI Curated)',
        tracks: resolvedTracks,
        createdAt: Date.now()
      };
      StorageService.savePlaylist(playlist);

      // Play immediately
      window.submarinePlayer.loadQueue(resolvedTracks, 0);
      renderTracks(resolvedTracks);
      document.getElementById('main-section-title').textContent = `✨ Playlist AI: ${playlist.title}`;
    }
  } catch (err) {
    alert('Gagal menghasilkan playlist AI: ' + err.message);
  } finally {
    btn.disabled = false;
    btn.textContent = '✨ Buat Playlist Sekarang';
  }
}

// ==========================================
// Toast Notification
// ==========================================
function showToast(message) {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = message;
  container.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(10px)';
    setTimeout(() => toast.remove(), 300);
  }, 2500);
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
