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
