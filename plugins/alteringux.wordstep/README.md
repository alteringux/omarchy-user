# Wordstep Reader

- **Super + Ctrl + Alt + E** reads the current text selection.
- **Super + Ctrl + Shift + E** lets you drag a screen region, extracts its text
  with local Tesseract OCR, and opens it in Wordstep. **Esc** cancels capture.
- **Esc** closes the reader; **Space** pauses or resumes.
- Click a word or character in the passage to continue from its word or symbol.
- Voice is off by default. Turn on **Voice** to hear each word with local Piper
  speech; pausing also pauses playback.

Voice, syllable colour, looping, reading mode, and speed settings are saved.
Speed ranges from 0.5× to 18× (50–1800 WPM).

Region capture uses `slurp`, `grim`, and `tesseract`, leaves the clipboard alone,
and removes its temporary image and text after opening the reader. Set
`OMARCHY_OCR_LANGS` to installed Tesseract language codes (default: `eng`).

The passage uses a few colour spans and preserves whitespace for code reading.
Its font weight stays fixed as the highlight moves, keeping wrapped lines stable.
