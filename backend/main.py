import yt_dlp
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="Tobitube yt-dlp API")

# Setup CORS agar aplikasi Flutter bisa mengakses API ini jika via web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_best_audio_stream(video_id: str):
    # Konfigurasi yt-dlp untuk mengambil audio terbaik
    ydl_opts = {
        'format': 'bestaudio/best',
        'quiet': True,
        'no_warnings': True,
        'skip_download': True,
        'geo_bypass': True,
        'outtmpl': '%(id)s.%(ext)s',
    }
    
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # Mengambil metadata stream tanpa mengunduh file
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            
            return {
                "videoId": video_id,
                "url": info.get('url'),
                "ext": info.get('ext'),
                "duration": info.get('duration'),
                "title": info.get('title'),
            }
    except Exception as e:
        raise Exception(str(e))

@app.get("/stream")
def stream_audio(videoId: str):
    """
    Endpoint untuk mendapatkan URL audio murni dari YouTube.
    Contoh: /stream?videoId=dQw4w9WgXcQ
    """
    if not videoId:
        raise HTTPException(status_code=400, detail="Parameter videoId wajib diisi.")
        
    try:
        data = get_best_audio_stream(videoId)
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Gagal mengambil stream: {str(e)}")

@app.get("/")
def read_root():
    return {
        "status": "ok", 
        "message": "Tobitube yt-dlp API is running!",
        "endpoints": ["/stream?videoId=YOUTUBE_VIDEO_ID"]
    }
