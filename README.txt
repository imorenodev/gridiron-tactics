GRIDIRON TACTICS — Phaser Edition

HOW TO RUN
==========
This game must be served over HTTP (browsers block local-file asset loading).

Option 1 — Python (any OS with Python 3):
  cd into this folder, then run:
    python3 -m http.server 8000
  Open http://localhost:8000 in your browser.

Option 2 — Node:
    npx serve .
  Open the URL it prints.

Option 3 — VS Code:
  Install the "Live Server" extension, right-click index.html → Open with Live Server.

Option 4 — Deploy anywhere static (Netlify, Vercel, GitHub Pages, itch.io, etc.):
  Drag the entire folder onto the platform. It's pure HTML/JS/PNG.

CONTROLS
========
• Drag cards from hand onto a lane to play them.
• Tap SNAP! to reveal both sides and resolve the drive.
• Win by scoring more points than the CPU across 8 drives.

FILES
=====
  index.html          — game entry point (Phaser 3.70 loaded via CDN)
  assets/ui/*.png     — your art pack, all referenced by index.html

CDN NOTE
========
Phaser is loaded from cdnjs.cloudflare.com. If you want a fully offline build,
download phaser.min.js and host it locally, then change the <script src=...>
in index.html to point at the local file.
