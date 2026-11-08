(() => {
  "use strict";
  const params = new URLSearchParams(location.search);
  const native = params.get("native") === "1";
  // The app window already shows track info, so only the style picker stays.
  if (params.get("embedded") === "1") document.documentElement.classList.add("embedded");
  const status = document.getElementById("status");
  const title = document.getElementById("track");
  const mode = document.getElementById("mode");
  let snapshot = null;
  let disconnected = false;
  let timer;
  let polling = false;
  let sentLyricsKey = null;
  let sentLyrics = null;

  const cjk = "\\u3040-\\u30ff\\u3400-\\u9fff\\uf900-\\ufaff\\uac00-\\ud7af";
  const tokenPattern = new RegExp(`[${cjk}]\\s*|[^\\s${cjk}]+\\s*|\\s+`, "g");

  // The engine animates word by word, so plain LRC lines get evenly spaced
  // synthetic word timings; otherwise they would never become visible.
  function timedWords(line) {
    const text = String(line.fullText || "");
    const tokens = text.match(tokenPattern) || [];
    const weight = tokens.reduce((sum, token) => sum + Math.max(1, token.trim().length), 0);
    if (!weight) return [];
    const start = Number(line.startTime) || 0;
    const end = Math.max(start + 0.001, Number(line.endTime) || start + 5);
    const span = Math.min(end - start, 1 + weight * 0.3);
    let cursor = start;
    return tokens.map(token => {
      const length = span * Math.max(1, token.trim().length) / weight;
      const word = { text: token, startTime: cursor, endTime: cursor + length };
      cursor += length;
      return word;
    });
  }

  function withWordTimings(lyrics) {
    if (!lyrics || !Array.isArray(lyrics.lines)) return lyrics;
    return {
      ...lyrics,
      lines: lyrics.lines.map(line => Array.isArray(line.words) && line.words.length
        ? line
        : { ...line, words: timedWords(line) })
    };
  }

  function render() {
    if (!snapshot) return;
    const hidden = document.hidden || disconnected;
    const { lyrics, ...rest } = snapshot;
    const lyricsKey = JSON.stringify([snapshot.track?.seed ?? null, lyrics ?? null]);
    if (lyricsKey !== sentLyricsKey) {
      sentLyricsKey = lyricsKey;
      sentLyrics = withWordTimings(lyrics ?? null);
    }
    const update = {
      ...rest,
      lyrics: sentLyrics,
      clock: { ...snapshot.clock, playing: !hidden && snapshot.clock.playing },
      appearance: {
        ...snapshot.appearance,
        mode: mode.value,
        transparent: true,
        isDaylight: false,
        staticMode: hidden || !snapshot.clock.playing,
        lyricsFontStyle: { fontFamily: "Neko CJK" },
        subtitleFontStyle: { fontFamily: "Neko CJK" }
      }
    };
    title.textContent = snapshot.track
      ? [snapshot.track.name, snapshot.track.artist].filter(Boolean).join(" · ")
      : "NekoPlayer";
    status.textContent = disconnected ? "播放器已断开，歌词已暂停"
      : !snapshot.track ? "尚未播放"
      : !snapshot.lyrics?.lines?.length ? "当前歌曲暂无歌词"
      : snapshot.clock.playing ? "同步播放中" : "已暂停";
    if (window.__pony?.ready) window.__pony.push(update);
    else window.__ponyPending = update;
    document.title = "NekoPlayer · 动态歌词";
  }

  window.nekoLyrics = {
    push(value) {
      if (!value || typeof value !== "object" || !value.clock) return;
      snapshot = value;
      disconnected = false;
      render();
    },
    suspend() {
      disconnected = true;
      render();
    }
  };

  async function poll() {
    clearTimeout(timer);
    if (polling) return;
    polling = true;
    if (!document.hidden) {
      try {
        const response = await fetch("./state.json", {
          cache: "no-store",
          credentials: "omit",
          signal: AbortSignal.timeout(4000)
        });
        if (!response.ok) throw new Error("Disconnected");
        window.nekoLyrics.push(await response.json());
      } catch (_) {
        window.nekoLyrics.suspend();
        if (!snapshot) status.textContent = "未连接播放器，请从播放器重新打开";
      }
    }
    polling = false;
    timer = setTimeout(poll, document.hidden ? 2000 : disconnected ? 2000 : 500);
  }

  mode.addEventListener("change", render);
  document.addEventListener("visibilitychange", () => {
    render();
    if (!native) void poll();
  });
  if (!native) void poll();
})();
