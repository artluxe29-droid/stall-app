# Stall how-to videos

Animated 1080×1920 explainers (WhatsApp Status, TikTok, Reels, Shorts). Each episode is an HTML page whose every movement is a Web Animation on one timeline; `render.mjs` steps through it frame by frame and ffmpeg makes the MP4, so the result is smooth and identical every time.

- `engine.js` – helpers: `A` (animate), `go` (slide between screens), `tap` (finger tap), `type`, `caption`, `ring`.
- `base.css` – the look: phone frame, app screens, captions, awning.
- `epN.html` + `epN.js` – the episode's screens and its timeline.

Make one:

```
python3 build.py ep1            # fills icons, grids and the domain into ep1.built.html
node peek.mjs ep1 4 10 25        # stills at those seconds, to check
node render.mjs ep1 30           # → ep1.mp4 (needs Playwright and ffmpeg with libx264)
```

The videos are silent on purpose: add a trending sound in CapCut, TikTok or Instagram when posting.

## Voiced episodes (e1–e4)

1. Create your account · 2. Find your way around · 3. How to buy safely · 4. Your Account page.

Each has `eN.script.json` (caption + what the narrator says), `eN.screens.html` (the phone screens) and `eN.js` (what moves during each line).
The narration is made with Kokoro, an open text-to-speech model that runs on your own computer (voice `af_heart`, a little slower than normal).

```
pip install kokoro-onnx soundfile        # once; put kokoro.onnx and voices.bin (kokoro-onnx releases on GitHub) in this folder
python3 voice.py e1 af_heart 0.94        # speaks every line, times the episode around it, adds a soft music bed → e1.wav, e1.times.js
python3 build2.py e1                     # → e1.built.html
node peek2.mjs e1                        # a still from the middle of every step
node render.mjs e1 30                    # → e1.mp4 with the voice-over
```

The ending shows "Get the Stall app". Once Stall has its own domain, put it there instead: `STALL_LINK=stall.ng python3 build2.py e1 e2 e3 e4`, then render again.

To change the wording, edit the script and run the four steps again; the animation re-times itself to the new speech.
