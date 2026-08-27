/**
 * recommendation.js - Last.fm Similarity Graph & On-Device Affinity Recommendation Engine
 */
const RecommendationEngine = {
  API_KEYS: [
    '2c687e9112443a502f689e3a6c1e5c46',
    'b25b959554ed76058ac220b7b2e0a026',
    'c08a9010f3c5ea70d0b04a081a2f9b84'
  ],
  _keyIdx: 0,

  _getKey() {
    return this.API_KEYS[this._keyIdx % this.API_KEYS.length];
  },

  /**
   * 1. Query Last.fm Similarity Graph for similar tracks
   */
  async getSimilarTracks(artist, track, limit = 12) {
    try {
      const cleanArtist = encodeURIComponent(artist.trim());
      const cleanTrack = encodeURIComponent(track.trim());
      const url = `https://ws.audioscrobbler.com/2.0/?method=track.getsimilar&artist=${cleanArtist}&track=${cleanTrack}&api_key=${this._getKey()}&format=json&limit=${limit}&autocorrect=1`;
      
      const res = await fetch(url);
      if (!res.ok) throw new Error(`Last.fm HTTP ${res.status}`);
      
      const data = await res.json();
      const tracks = data.similartracks?.track;
      if (Array.isArray(tracks)) {
        return tracks.map(t => ({
          title: t.name,
          artist: t.artist?.name || 'Unknown Artist',
          matchScore: parseFloat(t.match || 0.5),
          query: `${t.name} ${t.artist?.name || ''} official audio`
        }));
      }
    } catch (e) {
      console.warn('[ML Recommender] Last.fm track query failed:', e);
      this._keyIdx++;
    }

    // Fallback: Query artist similarity
    return this.getSimilarArtists(artist, limit);
  },

  /**
   * 2. Query Last.fm Similarity Graph for similar artists
   */
  async getSimilarArtists(artist, limit = 8) {
    try {
      const cleanArtist = encodeURIComponent(artist.trim());
      const url = `https://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=${cleanArtist}&api_key=${this._getKey()}&format=json&limit=${limit}&autocorrect=1`;
      
      const res = await fetch(url);
      if (!res.ok) throw new Error(`Last.fm HTTP ${res.status}`);
      
      const data = await res.json();
      const artists = data.similarartists?.artist;
      if (Array.isArray(artists)) {
        return artists.map(a => ({
          title: 'Top Hits',
          artist: a.name,
          matchScore: parseFloat(a.match || 0.5) * 0.8,
          query: `${a.name} popular official audio`
        }));
      }
    } catch (e) {
      console.warn('[ML Recommender] Last.fm artist query failed:', e);
    }
    return [];
  },

  /**
   * 3. Compute Local User Taste Affinity & Negative Skip Filter
   */
  computeUserAffinity() {
    const history = StorageService.getHistory();
    const affinity = {};
    const now = Date.now();

    for (const item of history) {
      const artist = (item.artist || '').toLowerCase().trim();
      if (!artist) continue;

      const daysAgo = (now - item.playedAt) / (1000 * 60 * 60 * 24);
      const recencyDecay = Math.exp(-daysAgo / 7.0); // 7-day decay

      let signal = 0.5;
      if (item.completionRate >= 0.70) {
        signal = 1.5; // Loved track (completed)
      } else if (item.completionRate < 0.25) {
        signal = -1.5; // Skipped early (penalty)
      }

      affinity[artist] = (affinity[artist] || 0.0) + (signal * recencyDecay);
    }

    return affinity;
  },

  /**
   * 4. Smart Hybrid Ranker
   */
  rankCandidates(candidates) {
    const affinity = this.computeUserAffinity();
    return candidates.sort((a, b) => {
      const matchA = a.matchScore || 0.5;
      const matchB = b.matchScore || 0.5;
      const affA = Math.max(-1.0, Math.min(2.0, affinity[(a.artist || '').toLowerCase()] || 0.0));
      const affB = Math.max(-1.0, Math.min(2.0, affinity[(b.artist || '').toLowerCase()] || 0.0));

      const scoreA = (matchA * 0.7) + (affA * 0.15);
      const scoreB = (matchB * 0.7) + (affB * 0.15);
      return scoreB - scoreA;
    });
  }
};
