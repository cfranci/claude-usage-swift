# Title
I made a free macOS menu bar app that shows your Claude usage limits in real-time

---

# Post

If you're on Claude Pro or Max, you've probably noticed there's no easy way to see how close you are to hitting your rate limits without opening the console.

I built a tiny menu bar app that shows your 5-hour session usage right in the macOS menu bar. Click it to see:

- **5-hour session**: 34% (resets 2h 15m)
- **Weekly limit**: 32% (resets Feb 13)
- **Sonnet weekly**: 15% (resets Feb 9)
- **Extra usage**: $8.47/$20 spent

## How it works

The app reads your Claude Code OAuth credentials from macOS Keychain (the same ones Claude Code uses when you log in). It then calls Anthropic's usage API endpoint to get your current limits.

**No API key needed** - if you've logged into Claude Code once, it just works.

The usage API is free to call - it doesn't consume any tokens.

## Why I made this

I kept hitting my limits unexpectedly. Now I can glance at my menu bar and see "72%" and know I should probably slow down, or "12%" and know I have plenty of headroom.

## Download

**Swift version** (recommended, ~50MB RAM):
https://github.com/cfranci/claude-usage-swift/releases

**Python version** (if you want to hack on it):
https://github.com/cfranci/claude-usage-tracker

## Requirements

- macOS 12+
- Claude Code installed and logged in (run `claude` in terminal once)
- Claude Pro or Max subscription

---

Open source, MIT license. PRs welcome!
