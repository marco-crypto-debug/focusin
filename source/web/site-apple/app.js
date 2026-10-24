/* ============================================================
   FocusIn — Apple-style product site
   Vanilla JS. No dependencies.
   ============================================================ */

(() => {
  'use strict';

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const finePointer = window.matchMedia('(pointer: fine)');
  const clamp = (n, min, max) => Math.min(max, Math.max(min, n));
  const random = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;
  const prefersReduced = () => reduceMotion.matches;

  /* ------------------------------------------------------------------
     Header: scroll state, progress bar, mobile menu
  ------------------------------------------------------------------ */
  const header = $('#siteHeader');
  const progress = $('#scrollProgress');
  const menuToggle = $('#menuToggle');
  const mobileMenu = $('#mobileMenu');
  let scrollTicking = false;

  function onScroll() {
    const y = window.scrollY || window.pageYOffset;
    header?.classList.toggle('is-scrolled', y > 8);
    if (progress) {
      const docHeight = document.documentElement.scrollHeight - window.innerHeight;
      const ratio = docHeight > 0 ? clamp(y / docHeight, 0, 1) : 0;
      progress.style.transform = `scaleX(${ratio})`;
    }
    scrollTicking = false;
  }

  window.addEventListener('scroll', () => {
    if (!scrollTicking) {
      scrollTicking = true;
      requestAnimationFrame(onScroll);
    }
  }, { passive: true });
  onScroll();

  function setMenu(open) {
    if (!menuToggle || !mobileMenu) return;
    menuToggle.setAttribute('aria-expanded', String(open));
    menuToggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    mobileMenu.classList.toggle('is-open', open);
  }

  menuToggle?.addEventListener('click', () => {
    setMenu(menuToggle.getAttribute('aria-expanded') !== 'true');
  });

  $$('#mobileMenu a').forEach((link) => {
    link.addEventListener('click', () => setMenu(false));
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') setMenu(false);
  });

  window.addEventListener('resize', () => {
    if (window.innerWidth > 860) setMenu(false);
  }, { passive: true });

  /* ------------------------------------------------------------------
     Scroll reveal
  ------------------------------------------------------------------ */
  const revealItems = $$('[data-reveal]');
  if (prefersReduced() || !('IntersectionObserver' in window)) {
    revealItems.forEach((item) => item.classList.add('is-visible'));
  } else {
    const revealObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          revealObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.08, rootMargin: '0px 0px -6% 0px' });

    revealItems.forEach((item) => revealObserver.observe(item));
  }

  /* ------------------------------------------------------------------
     Hero stats counters
  ------------------------------------------------------------------ */
  const statsBlock = $('.hero-stats');
  const counters = $$('[data-count]');
  let countersPlayed = false;

  function animateCounter(el) {
    const target = Number(el.dataset.count || 0);
    if (prefersReduced() || target === 0) {
      el.textContent = String(target);
      return;
    }
    const duration = 1300;
    const start = performance.now();
    const tick = (now) => {
      const t = clamp((now - start) / duration, 0, 1);
      const eased = 1 - Math.pow(1 - t, 3);
      el.textContent = String(Math.round(target * eased));
      if (t < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  if (statsBlock && 'IntersectionObserver' in window) {
    const statsObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting && !countersPlayed) {
          countersPlayed = true;
          counters.forEach(animateCounter);
          statsObserver.disconnect();
        }
      });
    }, { threshold: 0.35 });
    statsObserver.observe(statsBlock);
  } else {
    counters.forEach(animateCounter);
  }

  /* ------------------------------------------------------------------
     Nav scroll spy
  ------------------------------------------------------------------ */
  const navLinks = $$('.nav-links a[href^="#"]');
  const spySections = navLinks
    .map((link) => $(link.getAttribute('href')))
    .filter(Boolean);

  if (spySections.length && 'IntersectionObserver' in window) {
    const visibleIds = new Set();
    const updateActiveNav = () => {
      // Find the first section in document order that is currently visible
      let currentId = null;
      for (const section of spySections) {
        if (visibleIds.has(section.id)) {
          currentId = section.id;
          break;
        }
      }
      navLinks.forEach((link) => {
        const matches = currentId && link.getAttribute('href') === `#${currentId}`;
        link.classList.toggle('is-active', Boolean(matches));
      });
    };

    const spy = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          visibleIds.add(entry.target.id);
        } else {
          visibleIds.delete(entry.target.id);
        }
      });
      updateActiveNav();
    }, { rootMargin: '-20% 0px -60% 0px', threshold: 0 });

    spySections.forEach((section) => spy.observe(section));
  }

  /* ------------------------------------------------------------------
     Hero parallax
  ------------------------------------------------------------------ */
  const hero = $('.hero');
  const heroStage = $('#heroStage');
  let parallaxFrame = 0;
  let pointer = { x: 0, y: 0 };

  function applyParallax() {
    if (!heroStage) return;
    const rotateY = pointer.x * 2.6;
    const rotateX = pointer.y * -2.2;
    const tx = pointer.x * 9;
    const ty = pointer.y * 7;
    heroStage.style.transform = `translate3d(${tx}px, ${ty}px, 0) rotateX(${rotateX}deg) rotateY(${rotateY}deg)`;
    parallaxFrame = 0;
  }

  if (hero && heroStage && finePointer.matches && !prefersReduced()) {
    hero.addEventListener('pointermove', (event) => {
      const rect = hero.getBoundingClientRect();
      pointer = {
        x: clamp(((event.clientX - rect.left) / rect.width - 0.5) * 2, -1, 1),
        y: clamp(((event.clientY - rect.top) / rect.height - 0.5) * 2, -1, 1)
      };
      if (!parallaxFrame) parallaxFrame = requestAnimationFrame(applyParallax);
    }, { passive: true });

    hero.addEventListener('pointerleave', () => {
      pointer = { x: 0, y: 0 };
      if (!parallaxFrame) parallaxFrame = requestAnimationFrame(applyParallax);
    });
  }

  /* ------------------------------------------------------------------
     Hero background orbs: pause animations when off-screen to save CPU/GPU
  ------------------------------------------------------------------ */
  const orbs = $$('.orb');
  if (hero && orbs.length && 'IntersectionObserver' in window && !prefersReduced()) {
    const orbObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        orbs.forEach((orb) => orb.classList.toggle('orb-play', entry.isIntersecting));
      });
    }, { threshold: 0.05 });
    orbObserver.observe(hero);
  } else {
    orbs.forEach((orb) => orb.classList.add('orb-play'));
  }

  /* ------------------------------------------------------------------
     Bento card spotlight
  ------------------------------------------------------------------ */
  $$('.bento-card').forEach((card) => {
    card.addEventListener('pointermove', (event) => {
      const rect = card.getBoundingClientRect();
      card.style.setProperty('--mx', `${event.clientX - rect.left}px`);
      card.style.setProperty('--my', `${event.clientY - rect.top}px`);
    }, { passive: true });
  });

  /* ------------------------------------------------------------------
     Steps line
  ------------------------------------------------------------------ */
  const steps = $('#steps');
  if (steps && 'IntersectionObserver' in window) {
    const stepsObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          steps.classList.add('is-visible');
          stepsObserver.disconnect();
        }
      });
    }, { threshold: 0.25 });
    stepsObserver.observe(steps);
  } else {
    steps?.classList.add('is-visible');
  }

  /* ------------------------------------------------------------------
     Focus lock demonstration
  ------------------------------------------------------------------ */
  const focusVisual = $('#focusVisual');
  const replayLock = $('#replayLock');

  function showLock() {
    if (!focusVisual) return;
    focusVisual.classList.add('is-locked');
  }

  if (focusVisual && 'IntersectionObserver' in window && !prefersReduced()) {
    const lockObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) showLock();
      });
    }, { threshold: 0.38 });
    lockObserver.observe(focusVisual);
  } else {
    showLock();
  }

  replayLock?.addEventListener('click', () => {
    if (!focusVisual) return;
    focusVisual.classList.remove('is-locked');
    void focusVisual.offsetWidth;
    window.setTimeout(showLock, 120);
  });

  /* ------------------------------------------------------------------
     FAQ accordion
  ------------------------------------------------------------------ */
  $$('.faq-item').forEach((item) => {
    const button = $('.faq-q', item);
    button?.addEventListener('click', () => {
      const open = item.classList.toggle('is-open');
      button.setAttribute('aria-expanded', String(open));
    });
  });

  /* ------------------------------------------------------------------
     Live Demo State Machine
  ------------------------------------------------------------------ */
  const demoApp = $('#demoApp');
  const deviceList = $('#deviceList');
  const studentGrid = $('#studentGrid');
  const selectAll = $('#selectAll');
  const selectedCountLabel = $('#selectedCountLabel');
  const onlineCount = $('#onlineCount');
  const demoStatus = $('#demoStatus');
  const broadcastToggle = $('#broadcastToggle');
  const broadcastLabel = $('#broadcastLabel');
  const broadcastIcon = $('#broadcastIcon');
  const lockToggle = $('#lockToggle');
  const lockLabel = $('#lockLabel');
  const audioToggle = $('#audioToggle');
  const audioLabel = $('#audioLabel');
  const qualityGroup = $('#qualityGroup');
  const avgLatency = $('#avgLatency');
  const latencyStat = $('#latencyStat');
  const fpsReadout = $('#fpsReadout');
  const bitrateReadout = $('#bitrateReadout');
  const resolutionReadout = $('#resolutionReadout');
  const connectedStat = $('#connectedStat');
  const demoTimer = $('#demoTimer');
  const selectedHint = $('#selectedHint');
  const demoLiveBadge = $('#demoLiveBadge');
  const demoLog = $('#demoLog');
  const resetDemo = $('#resetDemo');
  const toast = $('#toast');

  if (demoApp && deviceList && studentGrid) {
    const DEVICES = [
      { id: '01', name: 'iMac 01', student: 'Ava', baseline: 12 },
      { id: '02', name: 'iMac 02', student: 'Leo', baseline: 14 },
      { id: '03', name: 'iMac 03', student: 'Mia', baseline: 11 },
      { id: '04', name: 'iMac 04', student: 'Noah', baseline: 18 },
      { id: '05', name: 'iMac 05', student: 'Iris', baseline: 22 },
      { id: '06', name: 'iMac 06', student: 'Kai', baseline: 16 }
    ];

    const QUALITY = {
      auto: { label: 'Auto', fps: 30, resolution: 'Native', bitrate: 'Adaptive' },
      low: { label: 'Low', fps: 24, resolution: '720p', bitrate: '1.2 Mbps' },
      medium: { label: 'Mid', fps: 30, resolution: '1080p', bitrate: '2.8 Mbps' },
      high: { label: 'High', fps: 30, resolution: 'Native', bitrate: '5.4 Mbps' }
    };

    const state = {
      devices: DEVICES.map((device) => ({ ...device, selected: true, latency: device.baseline })),
      broadcasting: false,
      locked: false,
      audio: false,
      quality: 'auto',
      startedAt: 0,
      elapsed: 0,
      latencyHistory: [],
      timerId: 0,
      latencyId: 0
    };

    let toastTimer = 0;

    function toastMessage(message) {
      if (!toast) return;
      window.clearTimeout(toastTimer);
      toast.textContent = message;
      toast.classList.add('is-visible');
      toastTimer = window.setTimeout(() => toast.classList.remove('is-visible'), 2400);
    }

    function plural(n, singular, pluralForm) {
      return `${n} ${n === 1 ? singular : (pluralForm || `${singular}s`)}`;
    }

    function formatTime(seconds) {
      const mins = Math.floor(seconds / 60).toString().padStart(2, '0');
      const secs = Math.floor(seconds % 60).toString().padStart(2, '0');
      return `${mins}:${secs}`;
    }

    function iconMarkup(type) {
      if (type === 'stop') {
        return '<svg viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="1.5" fill="currentColor" stroke="none"/></svg>';
      }
      return '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z" fill="currentColor" stroke="none"/></svg>';
    }

    const deviceIcon = '<svg viewBox="0 0 24 24"><rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/></svg>';
    const checkIcon = '<svg viewBox="0 0 24 24"><path d="m5 12 4.5 4.5L19 7"/></svg>';
    const lockIcon = '<svg viewBox="0 0 24 24"><rect x="4" y="10" width="16" height="11" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg>';

    function renderDevices() {
      deviceList.innerHTML = state.devices.map((device) => `
        <button type="button" class="device-row" data-id="${device.id}" aria-pressed="true">
          <span class="device-check" aria-hidden="true">${checkIcon}</span>
          <span class="device-icon" aria-hidden="true">${deviceIcon}</span>
          <span class="device-info"><strong>${device.name}</strong><small>${device.student} · Online</small></span>
          <span class="device-latency">${device.latency} ms</span>
          <span class="device-lock" aria-hidden="true">${lockIcon}</span>
        </button>
      `).join('');
    }

    function renderTiles() {
      studentGrid.innerHTML = state.devices.map((device) => `
        <button type="button" class="student-tile" data-id="${device.id}" aria-pressed="true">
          <span class="tile-top">
            <span class="tile-status" aria-hidden="true"></span>
            <span class="tile-name">${device.name}</span>
            <span class="tile-state">Ready</span>
          </span>
          <span class="tile-screen">
            <span class="tile-mirror" aria-hidden="true"></span>
            <span class="tile-lock" aria-hidden="true">${lockIcon}<span>Locked</span></span>
          </span>
          <span class="tile-foot">
            <span class="tile-latency">${device.latency} ms</span>
            <span class="tile-quality">Native</span>
          </span>
        </button>
      `).join('');

      const previewSlide = $('#previewSlide');
      if (previewSlide) {
        $$('.tile-mirror', studentGrid).forEach((mirror) => {
          const clone = previewSlide.cloneNode(true);
          clone.removeAttribute('id');
          mirror.appendChild(clone);
        });
      }
    }

    function selectedDevices() {
      return state.devices.filter((device) => device.selected);
    }

    function averageLatency() {
      const selected = selectedDevices();
      if (!selected.length) return 0;
      return Math.round(selected.reduce((sum, device) => sum + device.latency, 0) / selected.length);
    }

    function updateButtons() {
      if (broadcastToggle) {
        broadcastToggle.classList.toggle('is-on', state.broadcasting);
        broadcastToggle.setAttribute('aria-pressed', String(state.broadcasting));
      }
      if (broadcastLabel) broadcastLabel.textContent = state.broadcasting ? 'Stop broadcast' : 'Start broadcast';
      if (broadcastIcon) broadcastIcon.innerHTML = iconMarkup(state.broadcasting ? 'stop' : 'play');
      if (lockToggle) {
        lockToggle.classList.toggle('is-on', state.locked);
        lockToggle.setAttribute('aria-pressed', String(state.locked));
      }
      if (lockLabel) lockLabel.textContent = state.locked ? 'Unlock screens' : 'Lock screens';
      if (audioToggle) {
        audioToggle.classList.toggle('is-on', state.audio);
        audioToggle.setAttribute('aria-pressed', String(state.audio));
      }
    }

    function updateQuality() {
      const config = QUALITY[state.quality];
      $$('button[data-quality]', qualityGroup || document).forEach((button) => {
        const active = button.dataset.quality === state.quality;
        button.classList.toggle('is-active', active);
        button.setAttribute('aria-pressed', String(active));
      });
      if (fpsReadout) fpsReadout.textContent = String(config.fps);
      if (bitrateReadout) bitrateReadout.textContent = config.bitrate;
      if (resolutionReadout) resolutionReadout.textContent = config.resolution;
    }

    function updateTiles() {
      $$('.student-tile', studentGrid).forEach((tile) => {
        const device = state.devices.find((item) => item.id === tile.dataset.id);
        if (!device) return;
        const isLive = state.broadcasting && device.selected;
        const isLocked = state.locked && device.selected;
        tile.classList.toggle('is-selected', device.selected);
        tile.classList.toggle('is-live', isLive);
        tile.classList.toggle('is-locked', isLocked);
        tile.setAttribute('aria-pressed', String(device.selected));
        tile.setAttribute('aria-label', `${device.name}, ${device.student}, ${device.selected ? 'included' : 'excluded'}${isLive ? ', live' : ''}${isLocked ? ', locked' : ''}`);

        const stateLabel = $('.tile-state', tile);
        if (stateLabel) {
          if (isLocked) stateLabel.textContent = 'Locked';
          else if (isLive) stateLabel.textContent = 'Live';
          else if (device.selected) stateLabel.textContent = 'Ready';
          else stateLabel.textContent = 'Off';
        }
        const latencyLabel = $('.tile-latency', tile);
        if (latencyLabel) latencyLabel.textContent = `${device.latency} ms`;
        const qualityLabel = $('.tile-quality', tile);
        if (qualityLabel) qualityLabel.textContent = QUALITY[state.quality].resolution;
      });
    }

    function updateDeviceRows() {
      $$('.device-row', deviceList).forEach((row) => {
        const device = state.devices.find((item) => item.id === row.dataset.id);
        if (!device) return;
        row.classList.toggle('is-selected', device.selected);
        row.classList.toggle('is-locked', state.locked && device.selected);
        row.setAttribute('aria-pressed', String(device.selected));
        row.setAttribute('aria-label', `${device.name}, ${device.student}, ${device.selected ? 'included' : 'excluded'}${state.locked && device.selected ? ', locked' : ''}`);
        const latency = $('.device-latency', row);
        if (latency) {
          latency.textContent = `${device.latency} ms`;
          latency.classList.toggle('is-high', device.latency > 30);
        }
      });
    }

    function updateSparkline() {
      const line = $('#latencyLine');
      const area = $('#latencyArea');
      if (!line || !area) return;

      if (!state.broadcasting || state.latencyHistory.length < 2) {
        line.setAttribute('points', '');
        area.setAttribute('d', '');
        return;
      }

      const width = 140;
      const height = 40;
      const pad = 4;
      const values = state.latencyHistory;
      const min = Math.min(...values) - 2;
      const max = Math.max(...values) + 2;
      const span = Math.max(max - min, 1);
      const points = values.map((value, index) => {
        const x = (index / (values.length - 1)) * width;
        const y = height - pad - ((value - min) / span) * (height - pad * 2);
        return `${x.toFixed(1)},${y.toFixed(1)}`;
      });
      line.setAttribute('points', points.join(' '));
      area.setAttribute('d', `M0,${height} L${points.join(' L')} L${width},${height} Z`);
    }

    function updateMetrics() {
      const selected = selectedDevices();
      const avg = state.broadcasting ? averageLatency() : 0;
      if (avgLatency) avgLatency.textContent = state.broadcasting ? `${avg} ms` : '— ms';
      if (latencyStat) latencyStat.textContent = state.broadcasting ? `${avg} ms` : '— ms';
      if (connectedStat) connectedStat.textContent = String(state.devices.length);
      if (onlineCount) onlineCount.textContent = String(state.devices.length);
      if (selectedCountLabel) selectedCountLabel.textContent = `${selected.length} selected`;
      if (selectAll) {
        selectAll.checked = selected.length === state.devices.length;
        selectAll.indeterminate = selected.length > 0 && selected.length < state.devices.length;
      }

      if (selectedHint) {
        if (!selected.length) selectedHint.textContent = 'Select a Mac to begin';
        else if (state.locked && state.broadcasting) selectedHint.textContent = `Broadcasting to ${plural(selected.length, 'Mac')} · ${plural(selected.length, 'screen')} locked`;
        else if (state.locked) selectedHint.textContent = `${plural(selected.length, 'screen')} locked`;
        else if (state.broadcasting) selectedHint.textContent = `Broadcasting to ${plural(selected.length, 'Mac')}`;
        else selectedHint.textContent = `Ready to broadcast to ${plural(selected.length, 'Mac')}`;
      }

      if (demoStatus) {
        if (state.broadcasting && state.locked) demoStatus.textContent = 'Broadcasting · Locked';
        else if (state.broadcasting) demoStatus.textContent = 'Broadcasting';
        else if (state.locked) demoStatus.textContent = 'Locked';
        else demoStatus.textContent = 'Ready';
      }

      if (demoTimer) demoTimer.textContent = formatTime(state.elapsed);
      if (demoLiveBadge) {
        const label = $('span', demoLiveBadge);
        if (label) label.textContent = state.broadcasting ? 'LIVE' : 'Preview';
      }

      demoApp.classList.toggle('is-live', state.broadcasting);

      // EQ bars animation state
      const eq = $('#previewEq');
      if (eq) {
        eq.style.opacity = state.audio ? '1' : '0.25';
      }

      updateQuality();
      updateButtons();
      updateTiles();
      updateDeviceRows();
      updateSparkline();
    }

    function updateLatencies() {
      selectedDevices().forEach((device) => {
        device.latency = clamp(device.baseline + random(-3, 5), 8, 38);
      });
      const avg = averageLatency();
      state.latencyHistory.push(avg);
      if (state.latencyHistory.length > 26) state.latencyHistory.shift();
      updateMetrics();
    }

    function startTimers() {
      window.clearInterval(state.timerId);
      window.clearInterval(state.latencyId);
      state.startedAt = Date.now() - state.elapsed * 1000;
      state.timerId = window.setInterval(() => {
        state.elapsed = Math.floor((Date.now() - state.startedAt) / 1000);
        if (demoTimer) demoTimer.textContent = formatTime(state.elapsed);
      }, 1000);
      updateLatencies();
      state.latencyId = window.setInterval(updateLatencies, 2200);
    }

    function stopTimers() {
      window.clearInterval(state.timerId);
      window.clearInterval(state.latencyId);
      state.timerId = 0;
      state.latencyId = 0;
    }

    function addLog(message, type) {
      if (!demoLog) return;
      const now = new Date();
      const time = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
      const item = document.createElement('li');
      if (type) item.classList.add(`is-${type}`);
      const timeEl = document.createElement('time');
      timeEl.textContent = time;
      const dot = document.createElement('span');
      dot.className = 'log-dot';
      const text = document.createElement('span');
      text.textContent = message;
      item.append(timeEl, dot, text);
      demoLog.appendChild(item);
      while (demoLog.children.length > 30) demoLog.firstElementChild.remove();
      demoLog.scrollTop = demoLog.scrollHeight;
    }

    function toggleDevice(id) {
      const device = state.devices.find((item) => item.id === id);
      if (!device) return;
      device.selected = !device.selected;
      if (state.broadcasting) {
        addLog(`${device.name} ${device.selected ? 'joined' : 'left'} the broadcast`, device.selected ? 'good' : '');
      }
      if (!state.devices.some((item) => item.selected)) {
        toastMessage('Select at least one Mac to keep broadcasting.');
      }
      updateMetrics();
    }

    function resetState(silent) {
      stopTimers();
      state.broadcasting = false;
      state.locked = false;
      state.audio = false;
      state.quality = 'auto';
      state.startedAt = 0;
      state.elapsed = 0;
      state.latencyHistory = [];
      state.devices = DEVICES.map((device) => ({ ...device, selected: true, latency: device.baseline }));
      if (demoLog) demoLog.innerHTML = '';
      addLog('Bonjour discovery complete · 6 students online', 'good');
      addLog('Ready. Select students, then start a broadcast.', '');
      updateMetrics();
      if (!silent) toastMessage('Demo reset. Ready when you are.');
    }

    deviceList.addEventListener('click', (event) => {
      const row = event.target.closest('.device-row');
      if (!row) return;
      toggleDevice(row.dataset.id);
    });

    studentGrid.addEventListener('click', (event) => {
      const tile = event.target.closest('.student-tile');
      if (!tile) return;
      toggleDevice(tile.dataset.id);
    });

    selectAll?.addEventListener('change', () => {
      const checked = selectAll.checked;
      state.devices.forEach((device) => { device.selected = checked; });
      if (state.broadcasting) {
        addLog(checked ? 'All students joined the broadcast' : 'Broadcast paused for all students', checked ? 'good' : '');
      }
      updateMetrics();
    });

    broadcastToggle?.addEventListener('click', () => {
      const selected = selectedDevices();
      if (!selected.length) {
        toastMessage('Select at least one Mac first.');
        selectAll?.focus();
        return;
      }
      state.broadcasting = !state.broadcasting;
      if (state.broadcasting) {
        state.startedAt = Date.now();
        state.latencyHistory = [];
        addLog(`Broadcast started · ${plural(selected.length, 'Mac')}`, 'accent');
        startTimers();
      } else {
        stopTimers();
        state.elapsed = 0;
        state.latencyHistory = [];
        addLog('Broadcast stopped', '');
      }
      updateMetrics();
    });

    lockToggle?.addEventListener('click', () => {
      const selected = selectedDevices();
      if (!selected.length) {
        toastMessage('Select at least one Mac first.');
        return;
      }
      state.locked = !state.locked;
      addLog(
        state.locked
          ? `Focus lock sent · ${plural(selected.length, 'screen')} locked`
          : `Focus lock released · ${plural(selected.length, 'screen')} unlocked`,
        state.locked ? 'warn' : 'good'
      );
      updateMetrics();
    });

    audioToggle?.addEventListener('click', () => {
      state.audio = !state.audio;
      addLog(
        state.audio
          ? 'Audio stream enabled · 48 kHz stereo (Alpha)'
          : 'Audio stream disabled · Video only',
        state.audio ? 'good' : ''
      );
      toastMessage(state.audio ? 'Audio streaming enabled (Alpha)' : 'Audio streaming disabled');
      updateMetrics();
    });

    qualityGroup?.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-quality]');
      if (!button) return;
      const next = button.dataset.quality;
      if (!QUALITY[next] || next === state.quality) return;
      state.quality = next;
      addLog(`Quality set to ${QUALITY[next].label} · ${QUALITY[next].resolution}`, '');
      updateMetrics();
    });

    resetDemo?.addEventListener('click', () => resetState(false));

    /* Build the demo */
    renderDevices();
    renderTiles();
    resetState(true);

    /* Pause ambient updates when the tab is hidden */
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && state.broadcasting) {
        stopTimers();
      } else if (!document.hidden && state.broadcasting) {
        startTimers();
      }
    });
  }

  /* ------------------------------------------------------------------
     Trilingual Localization (en, zh-Hant, zh-Hans)
  ------------------------------------------------------------------ */
  const DICT = {
    "zh-Hant": {
      "nav.demo": "即時示範",
      "nav.features": "功能",
      "nav.focus": "專注鎖定",
      "nav.download": "下載",
      "nav.cta": "下載",
      "hero.announce": "FocusIn Delta 1.5.9 正式推出",
      "hero.title": "一個畫面，<br><span class=\"text-gradient\">送達每一部 Mac。</span>",
      "hero.sub": "FocusIn 把你的 Mac 變成即時課堂廣播工作室。在同一 Wi-Fi 下將屏幕即時串流到每一部學生機，鎖定屏幕並下發指令 —— 零硬件、零帳號、零雲端。",
      "hero.dl": "下載 Mac 版",
      "hero.demo": "體驗即時示範",
      "hero.note": "免費 · macOS 14 或以上 · 支援 Apple 晶片與 Intel",
      "demo.eyebrow": "即時示範",
      "demo.h2": "整個課室。<br><span class=\"text-gradient\">一鍵掌控。</span>",
      "demo.sub": "這是一個可操作的 FocusIn 教師端模擬環境。點擊開始廣播、切換畫質、鎖定屏幕 —— 全部即時響應，無需安裝。",
      "demo.all": "全部學生",
      "demo.bonjour": "Bonjour 發現已啟動",
      "demo.quality": "畫質",
      "demo.latency": "延遲",
      "demo.bitrate": "碼率",
      "demo.previewTitle": "屏幕預覽",
      "demo.lessonLabel": "今日課程",
      "demo.lessonTitle": "水循環",
      "demo.lessonSub": "蒸發 · 凝結 · 降水",
      "demo.start": "開始廣播",
      "demo.lock": "鎖定屏幕",
      "demo.connected": "已連線",
      "demo.connectedSub": "台區域網內的 Mac",
      "demo.avgLatency": "平均延遲",
      "demo.res": "解析度",
      "demo.trans": "傳輸",
      "demo.net": "網路",
      "demo.local": "本地區域網",
      "demo.students": "學生端",
      "demo.clickHint": "點擊任何屏幕以加入或移出廣播",
      "demo.activity": "即時紀錄",
      "demo.reset": "重設示範",
      "demo.caption": "即時模擬運作，非錄製視頻。每個控制元件均可實際操作。",
      "nav.pricing": "定價",
      "price.eyebrow": "定價",
      "price.title": "簡單定價，沒有驚喜。",
      "price.sub": "在本頁即時取得 License Key，於 App 輸入即可解鎖 Pro。附送 7 天免費試用。",
      "price.freeName": "免費版",
      "price.freeDesc": "廣播所需的一切",
      "price.freePer": "· 永久免費",
      "price.popular": "熱門",
      "price.freeBtn": "免費下載",
      "price.f1": "即時屏幕廣播（高清）",
      "price.f2": "一對多串流",
      "price.f3": "專注鎖定與遠端指令",
      "price.f4": "檔案清理（DELETE 確認）",
      "price.f5": "自動更新與 Homebrew",
      "price.proName": "Pro",
      "price.proDesc": "解鎖全部功能",
      "price.monthly": "/ 月",
      "price.trial": "7 天免費試用 · 隨時取消",
      "price.p1": "包含免費版全部功能",
      "price.p2": "穩定輕量化核心",
      "price.p3": "新功能優先體驗",
      "price.p4": "優先支援",
      "price.p5": "每月 License Key，解鎖全部 Pro",
      "price.proBtn": "購買 Pro",
      "price.schoolName": "學校",
      "price.schoolDesc": "全校部署",
      "price.custom": "自訂",
      "price.schoolPer": "批量定價 · 聯絡我們",
      "price.s1": "包含 Pro 全部功能",
      "price.s2": "不限教師人數",
      "price.s3": "多課室管理",
      "price.s4": "優先支援",
      "price.schoolBtn": "聯絡",
      "price.note": "Pro 每月 US$12.99，7 天免費試用。付款渠道即將上線；目前本頁即時生成 License Key 供測試。",
      "key.title": "取得你的 Pro License Key",
      "key.sub": "輸入管理員 Key 與電郵，即時生成 License Key。貼到 App 即可解鎖 Pro。",
      "key.emailPlaceholder": "you@example.com",
      "key.adminPlaceholder": "管理員 Key（開發者）",
      "key.months": "月數",
      "key.genBtn": "生成 License Key",
      "key.err": "請輸入有效電郵地址。",
      "key.errAdmin": "需要管理員 Key 才能生成。",
      "key.errServer": "生成失敗，請稍後再試。",
      "key.resultLabel": "你的 License Key",
      "key.copy": "複製",
      "key.copied": "已複製！"
    },
    "zh-Hans": {
      "nav.demo": "在线演示",
      "nav.features": "功能",
      "nav.focus": "专注锁定",
      "nav.download": "下载",
      "nav.cta": "下载",
      "hero.announce": "FocusIn Delta 1.5.9 正式发布",
      "hero.title": "一个屏幕，<br><span class=\"text-gradient\">广播到每台 Mac。</span>",
      "hero.sub": "FocusIn 将你的 Mac 变成实时课堂广播工作室。在局域网内将屏幕瞬间广播给所有学生机，一键锁定全屏并下发指令 —— 无需外接硬件、无需账号、无需云端。",
      "hero.dl": "下载 Mac 版",
      "hero.demo": "体验在线演示",
      "hero.note": "免费 · macOS 14 或更高 · 支持 Apple 芯片与 Intel",
      "demo.eyebrow": "在线演示",
      "demo.h2": "整个教室。<br><span class=\"text-gradient\">触手可及。</span>",
      "demo.sub": "这是一个真实的 FocusIn 教师端模拟环境。点击开始广播、切换画质、锁定屏幕 —— 一切即时响应，无需安装。",
      "demo.all": "全部学生",
      "demo.bonjour": "Bonjour 发现已就绪",
      "demo.quality": "画质",
      "demo.latency": "延迟",
      "demo.bitrate": "码率",
      "demo.previewTitle": "屏幕预览",
      "demo.lessonLabel": "今日课程",
      "demo.lessonTitle": "水循环",
      "demo.lessonSub": "蒸发 · 凝结 · 降水",
      "demo.start": "开始广播",
      "demo.lock": "锁定屏幕",
      "demo.connected": "已连接",
      "demo.connectedSub": "台局域网内的 Mac",
      "demo.avgLatency": "平均延迟",
      "demo.res": "分辨率",
      "demo.trans": "传输",
      "demo.net": "网络",
      "demo.local": "本地局域网",
      "demo.students": "学生端",
      "demo.clickHint": "点击任意屏幕以加入或移出广播",
      "demo.activity": "动态日志",
      "demo.reset": "重置演示",
      "demo.caption": "真实交互模拟，非录屏视频。所有控件均可实时操作。",
      "nav.pricing": "定价",
      "price.eyebrow": "定价",
      "price.title": "简单定价，没有意外。",
      "price.sub": "在本页即时获取 License Key，在 App 中输入即可解锁 Pro。附赠 7 天免费试用。",
      "price.freeName": "免费版",
      "price.freeDesc": "广播所需的一切",
      "price.freePer": "· 永久免费",
      "price.popular": "热门",
      "price.freeBtn": "免费下载",
      "price.f1": "实时屏幕广播（高清）",
      "price.f2": "一对多串流",
      "price.f3": "专注锁定与远程指令",
      "price.f4": "文件清理（DELETE 确认）",
      "price.f5": "自动更新与 Homebrew",
      "price.proName": "Pro",
      "price.proDesc": "解锁全部功能",
      "price.monthly": "/ 月",
      "price.trial": "7 天免费试用 · 随时取消",
      "price.p1": "包含免费版全部功能",
      "price.p2": "稳定轻量化核心",
      "price.p3": "新功能优先体验",
      "price.p4": "优先支持",
      "price.p5": "每月 License Key，解锁全部 Pro",
      "price.proBtn": "购买 Pro",
      "price.schoolName": "学校",
      "price.schoolDesc": "全校部署",
      "price.custom": "自定义",
      "price.schoolPer": "批量定价 · 联系我们",
      "price.s1": "包含 Pro 全部功能",
      "price.s2": "不限教师人数",
      "price.s3": "多教室管理",
      "price.s4": "优先支持",
      "price.schoolBtn": "联系",
      "price.note": "Pro 每月 US$12.99，7 天免费试用。支付渠道即将上线；目前本页即时生成 License Key 供测试。",
      "key.title": "获取你的 Pro License Key",
      "key.sub": "输入管理员 Key 与邮箱，即时生成 License Key。粘贴到 App 即可解锁 Pro。",
      "key.emailPlaceholder": "you@example.com",
      "key.adminPlaceholder": "管理员 Key（开发者）",
      "key.months": "月数",
      "key.genBtn": "生成 License Key",
      "key.err": "请输入有效邮箱地址。",
      "key.errAdmin": "需要管理员 Key 才能生成。",
      "key.errServer": "生成失败，请稍后重试。",
      "key.resultLabel": "你的 License Key",
      "key.copy": "复制",
      "key.copied": "已复制！"
    }
  };

  const defaultStrings = {};
  $$('[data-i18n]').forEach((el) => {
    defaultStrings[el.dataset.i18n] = el.innerHTML;
  });

  function setLanguage(lang) {
    document.documentElement.lang = lang;
    $$('.lang-btn').forEach((btn) => {
      btn.classList.toggle('is-active', btn.dataset.lang === lang);
    });

    $$('[data-i18n]').forEach((el) => {
      const key = el.dataset.i18n;
      if (lang === 'en') {
        if (defaultStrings[key]) el.innerHTML = defaultStrings[key];
      } else if (DICT[lang] && DICT[lang][key]) {
        el.innerHTML = DICT[lang][key];
      }
    });

    $$('[data-i18n-placeholder]').forEach((el) => {
      const key = el.dataset.i18nPlaceholder;
      if (lang !== 'en' && DICT[lang] && DICT[lang][key]) {
        el.setAttribute('placeholder', DICT[lang][key]);
      } else if (defaultStrings[key]) {
        el.setAttribute('placeholder', defaultStrings[key]);
      }
    });
  }

  $$('.lang-btn').forEach((btn) => {
    btn.addEventListener('click', () => setLanguage(btn.dataset.lang));
  });

  /* ------------------------------------------------------------------
     Homebrew 1-Click Copy
  ------------------------------------------------------------------ */
  const copyBrewBtn = $('#copyBrewBtn');
  copyBrewBtn?.addEventListener('click', () => {
    const cmd = 'brew install --cask marco-crypto-debug/focusin/focusin-teacher focusin-student';
    navigator.clipboard?.writeText(cmd).then(() => {
      const span = $('span', copyBrewBtn);
      if (span) span.textContent = 'Copied!';
      toastMessage('Copied Homebrew command to clipboard');
      setTimeout(() => {
        if (span) span.textContent = 'Copy';
      }, 2000);
    }).catch(() => {
      toastMessage('Command: ' + cmd);
    });
  });

  /* ------------------------------------------------------------------
     License Key Generation (worker backend)
  ------------------------------------------------------------------ */
  const LICENSE_WORKER_URL = 'https://focusin-license.marcoattck.workers.dev';
  const licenseErr = $('#license-err');
  const licenseRes = $('#license-res');
  const licenseKeyText = $('#license-key-text');

  function showLicenseErr(msg) {
    licenseErr.textContent = msg;
    licenseErr.style.display = msg ? 'block' : 'none';
  }
  function i18nOf(key) {
    const lang = document.documentElement.lang === 'zh-Hant' || document.documentElement.lang === 'zh-Hans'
      ? document.documentElement.lang : 'en';
    if (lang !== 'en') {
      const v = DICT[lang] && DICT[lang][key];
      if (v) return v;
    }
    return defaultStrings[key] || key;
  }

  $('#license-gen')?.addEventListener('click', async () => {
    const email = $('#license-email').value.trim();
    const admin = $('#license-admin').value.trim();
    const months = parseInt($('#license-months').value, 10) || 1;
    licenseRes.hidden = true;
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      showLicenseErr(i18nOf('key.err'));
      return;
    }
    if (!admin) {
      showLicenseErr(i18nOf('key.errAdmin'));
      return;
    }
    showLicenseErr('');
    const btn = $('#license-gen');
    const original = btn.textContent;
    btn.disabled = true;
    btn.textContent = '...';
    try {
      const r = await fetch(LICENSE_WORKER_URL + '/api/license/gen', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-admin-key': admin },
        body: JSON.stringify({ email, months })
      });
      const data = await r.json();
      if (!r.ok || data.error) throw new Error(data.error || 'HTTP ' + r.status);
      licenseKeyText.textContent = data.key;
      licenseRes.hidden = false;
      showLicenseErr('');
      licenseRes.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    } catch (e) {
      showLicenseErr(i18nOf('key.errServer') + ' (' + e.message + ')');
    } finally {
      btn.disabled = false;
      btn.textContent = original;
    }
  });

  $('#license-copy')?.addEventListener('click', () => {
    const key = licenseKeyText.textContent;
    navigator.clipboard?.writeText(key).then(() => {
      toastMessage(i18nOf('key.copied'));
      $('#license-copy').textContent = i18nOf('key.copied');
      setTimeout(() => { $('#license-copy').textContent = i18nOf('key.copy'); }, 2000);
    }).catch(() => toastMessage(key));
  });

})();
