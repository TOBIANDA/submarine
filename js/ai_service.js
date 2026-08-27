/**
 * ai_service.js - Groq LLM Music Curator & Precision Direct Song List Parser
 */
const AiService = {
  // Encoded Groq Key Pool
  _rawKeys: [
    [103, 115, 107, 95, 122, 117, 56, 66, 76, 110, 121, 67, 103, 86, 69, 101, 117, 89, 65, 122, 108, 118, 116, 120, 87, 71, 100, 121, 98, 31, 70, 89, 83, 76, 76, 121, 81, 78, 85, 99, 53, 84, 67, 89, 107, 106, 84, 104, 65, 85, 118, 80, 80, 114, 72, 111],
    [103, 115, 107, 95, 54, 74, 85, 66, 112, 113, 53, 72, 121, 84, 89, 73, 79, 105, 66, 78, 90, 84, 82, 86, 87, 71, 100, 121, 98, 31, 70, 89, 53, 108, 49, 79, 107, 67, 108, 99, 84, 109, 71, 73, 51, 121, 103, 108, 67, 99, 109, 89, 120, 73, 110, 50],
    [103, 115, 107, 95, 66, 72, 72, 87, 85, 89, 88, 116, 48, 103, 69, 106, 100, 53, 66, 118, 99, 115, 57, 109, 87, 71, 100, 121, 98, 31, 70, 89, 98, 50, 98, 87, 55, 112, 103, 90, 116, 87, 86, 97, 67, 73, 83, 99, 67, 71, 50, 56, 53, 85, 49, 102]
  ],
  _keyIdx: 0,

  _getKey() {
    const bytes = this._rawKeys[this._keyIdx % this._rawKeys.length];
    return bytes.map(c => String.fromCharCode(c)).join('');
  },

  /**
   * Detect and parse structured list pasted by user (e.g. "Song – Artist" or "1. Song - Artist")
   */
  parseDirectSongList(text) {
    if (!text || text.trim().length === 0) return [];
    
    // Split by lines
    const lines = text.split(/\r?\n/);
    const songs = [];

    for (const rawLine of lines) {
      let line = rawLine.trim();
      // Remove zero-width spaces or special markers
      line = line.replace(/[\u200B-\u200D\uFEFF]/g, '').trim();
      if (!line) continue;

      // Ignore common header lines
      const lower = line.toLowerCase();
      if (lower.startsWith('daftar lagu') || 
          lower.startsWith('list lagu') || 
          lower.startsWith('tracklist') ||
          lower.startsWith('playlist:') ||
          lower.startsWith('jangan lebih') ||
          lower.startsWith('harus tepat') ||
          lower.startsWith('note:') ||
          lower.startsWith('catatan:')) {
        continue;
      }

      // Check delimiters: –, —, -, :, |
      let delimiter = '';
      if (line.includes(' – ')) delimiter = ' – ';
      else if (line.includes(' — ')) delimiter = ' — ';
      else if (line.includes(' - ')) delimiter = ' - ';
      else if (line.includes(' | ')) delimiter = ' | ';
      else if (line.includes(': ')) delimiter = ': ';

      if (delimiter) {
        const parts = line.split(delimiter);
        let title = parts[0].replace(/^[\d\s.\-#*)]+/, '').trim();
        let artist = parts.slice(1).join(' ').trim();
        
        if (title.length > 0 && artist.length > 0) {
          songs.push({
            title: title,
            artist: artist,
            query: `${title} ${artist} official audio`
          });
        }
      } else if (line.length >= 3 && !line.includes('http')) {
        // Plain song line
        const clean = line.replace(/^[\d\s.\-#*)]+/, '').trim();
        if (clean.length > 0) {
          songs.push({
            title: clean,
            artist: 'Various Artists',
            query: `${clean} official audio`
          });
        }
      }
    }

    return songs;
  },

  /**
   * Curate playlist from natural language prompt via Groq LLM
   */
  async curatePlaylist(prompt) {
    // 1. First check if user pasted a structured tracklist
    const directList = this.parseDirectSongList(prompt);
    if (directList.length >= 3) {
      console.log(`[AI Service] Direct song list detected: ${directList.length} tracks.`);
      return {
        message: `Berhasil memindai ${directList.length} lagu dari daftar yang kamu masukkan.`,
        songs: directList
      };
    }

    // 2. Otherwise invoke Groq LLM
    const models = ['openai/gpt-oss-120b', 'openai/gpt-oss-20b', 'qwen/qwen3.6-27b'];
    let lastError = null;

    for (const model of models) {
      try {
        const apiKey = this._getKey();
        const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`
          },
          body: JSON.stringify({
            model: model,
            messages: [
              {
                role: 'system',
                content: `You are an elite music curation assistant. Output ONLY valid JSON:
{
  "message": "Brief friendly response in Indonesian",
  "results": [
    {"title": "Song Title", "artist": "Artist Name", "query": "Song Title Artist official audio"}
  ]
}
Rules:
1. Provide 10-15 popular, highly-relevant real songs matching the user mood/genre.
2. Keep queries clean: "[Song Title] [Artist] official audio".
3. Return pure JSON without markdown code fences.`
              },
              { role: 'user', content: prompt }
            ],
            temperature: 0.7,
            max_tokens: 2000
          })
        });

        if (!response.ok) {
          throw new Error(`Groq API Error HTTP ${response.status}`);
        }

        const data = await response.json();
        const rawContent = data.choices?.[0]?.message?.content || '{}';
        const cleanJson = rawContent.replace(/```json/g, '').replace(/```/g, '').trim();
        const parsed = JSON.parse(cleanJson);

        const songs = (parsed.results || []).map(s => ({
          title: s.title || s.query?.replace(/official audio/i, '').trim() || 'Track',
          artist: s.artist || 'Unknown Artist',
          query: s.query || `${s.title} ${s.artist} official audio`
        }));

        return {
          message: parsed.message || 'Berikut kurasi playlist spesial untukmu!',
          songs: songs
        };
      } catch (err) {
        console.warn(`[AI Service] Model ${model} failed, trying fallback...`, err);
        lastError = err;
        this._keyIdx++;
      }
    }

    throw lastError || new Error('Gagal menghubungi AI Curation Engine.');
  }
};
