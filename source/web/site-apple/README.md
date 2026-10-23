# FocusIn — Apple-Style Landing Page (v2)

A clean, modern landing page for FocusIn designed in Apple's signature product aesthetic.

Built with **vanilla HTML, CSS, and JavaScript** — zero build tools, zero dependencies, lightning fast.

> **Note:** The previous website in `source/web/site/` has been left completely untouched.

---

## Highlights

1. **Apple Product Aesthetic**
   - Clean SF Pro / system typography hierarchy with tight display tracking.
   - Glassmorphic translucent navigation bar with backdrop blur and scroll state.
   - Soft ambient radial glows and animated background orbs.
   - Subtle bento grid with mouse-following spotlight gradients.
   - High-contrast Focus Lock showcase.

2. **Interactive Live Demo (Faithful to Original Site)**
   - The signature two-column broadcast stage from `FocusIn官網.html`:
     - **Broadcast Source Mac**: Mini macOS display with window controls, app window ("FocusIn — Sharing"), mock lesson layout, and live animated audio equalizer bars.
     - **6 Student iMac Receivers**: 3×2 grid of connected iMacs (`iMac 01` – `iMac 06`), each with status indicator, idle display, and live mirrored screen view.
     - **Start / Stop broadcast**: Sequential connection ping animation with radial ripple waves across student Macs, jittered low-latency streaming (~12–30 ms), and real-time status banner.
     - **Dynamic device selection**: Click any iMac card to target or exclude specific Macs from the broadcast.
     - **Quality selector** (Auto, Low, Mid, High): Segmented quality controls with dynamic toast feedback.

3. **Motion & Animations**
   - Scroll-driven reveals via `IntersectionObserver` with smooth stagger.
   - Subtle 3D perspective parallax on the hero product window that responds to mouse movement.
   - Animated SVG radar sweep on the Bonjour auto-discovery card.
   - Animated stereo waveform bars.
   - Interactive "Replay lock" button in the Focus Lock section.
   - Full support for `prefers-reduced-motion: reduce`.

4. **Direct Downloads**
   - Links directly to the latest **FocusIn Delta v1.5.9** release DMG assets (`FocusIn-Delta-Teacher.dmg` and `FocusIn-Delta-Student.dmg`).
   - Links to Stable v1.4.3 and GitHub Releases archive.
   - Clear first-launch permissions guidance (Screen Recording for Teacher, Accessibility for Student).

---

## Directory Structure

```
source/web/site-apple/
├── index.html                  # Semantic, accessible HTML structure
├── styles.css                  # Apple design system, bento grid, animations
├── app.js                      # Live demo state machine, scroll spy, parallax
├── README.md                   # This documentation
└── assets/
    └── focusin-icon.svg        # Scalable macOS squircle app icon
```

---

## Local Preview

Start any local static server:

```bash
cd source/web/site-apple
python3 -m http.server 8080
```

Then open `http://localhost:8080` in Safari or Chrome.

Or simply open `index.html` directly in your browser.

---

## Deployment (Cloudflare Pages)

To deploy this new version to Cloudflare Pages:

```bash
cd source/web/site-apple
npx wrangler pages deploy . --project-name focusin
```
