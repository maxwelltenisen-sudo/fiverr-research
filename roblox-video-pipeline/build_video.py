#!/usr/bin/env python3
"""Build a vertical (1080x1920) Roblox-story Short from clips + a script.

Usage:  python3 build_video.py story.json [-o out.mp4] [--tts] [--keep]

story.json
{
  "voice_name": "en-US-GuyNeural",          # only used with --tts
  "music": "music.mp3",                      # optional, copyright-safe only
  "caption": {"words_per_chunk": 2, "font": "Inter", "size": 120,
              "colors": ["FFFFFF", "FFE600", "00F0FF"]},
  "scenes": [
    {"clip": "clips/01.mp4", "text": "Nobody wanted the new kid.",
     "voice": "voice/01.mp3",   # optional pre-recorded audio for this scene
     "duration": 3.5}           # optional; otherwise from voice or word count
  ]
}
Missing clips become a coloured placeholder so you can preview the timing.
"""
import argparse, json, re, shutil, subprocess, sys, tempfile
from pathlib import Path

W, H, FPS = 1080, 1920, 30
WORDS_PER_SEC = 2.8          # reading speed when there is no audio
PLACEHOLDERS = ["0x2b6cff", "0xff5a3c", "0x14b86a", "0x9b4dff", "0xffb300"]


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode:
        sys.exit(f"Command failed: {' '.join(map(str, cmd))}\n{r.stderr[-1500:]}")
    return r.stdout


def probe_duration(path):
    out = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
               "-of", "default=nw=1:nk=1", str(path)])
    return float(out.strip())


def make_tts(text, voice, dest):
    try:
        import edge_tts, asyncio
    except ImportError:
        sys.exit("--tts needs:  pip install edge-tts   (it also needs internet)")
    try:
        asyncio.run(edge_tts.Communicate(text, voice).save(str(dest)))
    except Exception as e:
        sys.exit(f"Voiceover failed ({type(e).__name__}). --tts needs an internet connection. "
                 "Run without --tts, or record your own voice and set \"voice\" per scene.")


def render_scene(scene, idx, dur, base, work):
    out = work / f"scene_{idx:02d}.mp4"
    clip = base / scene["clip"] if scene.get("clip") else None
    vf = (f"scale={W}:{H}:force_original_aspect_ratio=increase,"
          f"crop={W}:{H},fps={FPS},format=yuv420p")
    if clip and clip.exists():
        cmd = ["ffmpeg", "-y", "-stream_loop", "-1", "-i", str(clip), "-t", f"{dur:.3f}",
               "-an", "-vf", vf]
    else:
        if clip:
            print(f"  ! clip missing, using placeholder: {clip}")
        col = PLACEHOLDERS[idx % len(PLACEHOLDERS)]
        cmd = ["ffmpeg", "-y", "-f", "lavfi", "-i",
               f"color=c={col}:s={W}x{H}:r={FPS}", "-t", f"{dur:.3f}", "-an",
               "-vf", "format=yuv420p"]
    run(cmd + ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", str(out)])
    return out


def ass_time(t):
    cs = int(round(t * 100))
    return f"{cs // 360000}:{cs // 6000 % 60:02d}:{cs // 100 % 60:02d}.{cs % 100:02d}"


def build_ass(scenes_timing, cfg, dest):
    font = cfg.get("font", "Inter")
    size = cfg.get("size", 120)
    colors = cfg.get("colors", ["FFFFFF", "FFE600", "00F0FF"])
    n = max(1, cfg.get("words_per_chunk", 2))
    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2

[V4+ Styles]
Format: Name,Fontname,Fontsize,PrimaryColour,SecondaryColour,OutlineColour,BackColour,Bold,Italic,Underline,StrikeOut,ScaleX,ScaleY,Spacing,Angle,BorderStyle,Outline,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding
Style: Cap,{font},{size},&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,10,4,5,60,60,0,1

[Events]
Format: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text
"""
    lines, ci = [], 0
    for start, dur, text in scenes_timing:
        words = re.findall(r"\S+", text)
        if not words:
            continue
        chunks = [words[i:i + n] for i in range(0, len(words), n)]
        weights = [sum(len(w) + 2 for w in c) for c in chunks]
        total, t = sum(weights), start
        for c, wgt in zip(chunks, weights):
            d = dur * wgt / total
            col = colors[ci % len(colors)]
            ci += 1
            bgr = col[4:6] + col[2:4] + col[0:2]
            txt = " ".join(c).replace("{", "(").replace("}", ")").upper()
            pop = r"{\fscx70\fscy70\t(0,90,\fscx110\fscy110)\t(90,160,\fscx100\fscy100)"
            lines.append(f"Dialogue: 0,{ass_time(t)},{ass_time(t + d)},Cap,,0,0,0,,"
                         f"{pop}\\c&H{bgr}&" + "}" + txt)
            t += d
    dest.write_text(head + "\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("story")
    ap.add_argument("-o", "--output", default="out.mp4")
    ap.add_argument("--tts", action="store_true", help="make voiceover with edge-tts")
    ap.add_argument("--keep", action="store_true", help="keep temp files")
    a = ap.parse_args()

    story_path = Path(a.story).resolve()
    base = story_path.parent
    story = json.loads(story_path.read_text())
    work = Path(tempfile.mkdtemp(prefix="rbxvid_"))
    scenes = story["scenes"]

    timing, voice_files, seg_videos, t0 = [], [], [], 0.0
    for i, sc in enumerate(scenes):
        text = sc.get("text", "")
        voice = base / sc["voice"] if sc.get("voice") else None
        if a.tts and text and not (voice and voice.exists()):
            voice = work / f"voice_{i:02d}.mp3"
            make_tts(text, story.get("voice_name", "en-US-GuyNeural"), voice)
        if voice and voice.exists():
            dur = probe_duration(voice) + 0.25
        else:
            voice = None
            dur = sc.get("duration") or max(1.5, len(text.split()) / WORDS_PER_SEC + 0.3)
        print(f"scene {i + 1}: {dur:.1f}s  {text[:50]}")
        seg_videos.append(render_scene(sc, i, dur, base, work))
        voice_files.append((voice, dur))
        timing.append((t0, dur, text))
        t0 += dur

    # concat video
    listf = work / "list.txt"
    listf.write_text("".join(f"file '{p}'\n" for p in seg_videos))
    video = work / "video.mp4"
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(listf), "-c", "copy", str(video)])

    # captions
    ass = work / "caps.ass"
    build_ass(timing, story.get("caption", {}), ass)

    # audio: voice track padded to scene length, optional music underneath
    inputs, filt = [], []
    for k, (v, dur) in enumerate(voice_files):
        if v:
            inputs += ["-i", str(v)]
        else:
            inputs += ["-f", "lavfi", "-t", f"{dur:.3f}", "-i", "anullsrc=r=44100:cl=stereo"]
        filt.append(f"[{k}:a]aresample=44100,apad=whole_dur={dur:.3f},atrim=0:{dur:.3f}[a{k}]")
    n = len(voice_files)
    filt.append("".join(f"[a{k}]" for k in range(n)) + f"concat=n={n}:v=0:a=1[voice]")
    amap = "[voice]"
    music = base / story["music"] if story.get("music") else None
    if music and music.exists():
        inputs += ["-stream_loop", "-1", "-i", str(music)]
        filt.append(f"[{n}:a]volume=0.12[m]")
        filt.append("[voice][m]amix=inputs=2:duration=first:dropout_transition=0[mix]")
        amap = "[mix]"
    audio = work / "audio.m4a"
    run(["ffmpeg", "-y", *inputs, "-filter_complex", ";".join(filt), "-map", amap,
         "-c:a", "aac", "-b:a", "192k", str(audio)])

    # burn captions + mux
    out = Path(a.output).resolve()
    run(["ffmpeg", "-y", "-i", str(video), "-i", str(audio),
         "-vf", f"ass={ass}", "-c:v", "libx264", "-preset", "medium", "-crf", "19",
         "-pix_fmt", "yuv420p", "-c:a", "copy", "-shortest", "-movflags", "+faststart", str(out)])
    print(f"\nDone: {out}  ({t0:.1f}s)")
    if not a.keep:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
