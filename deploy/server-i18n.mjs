// Server-side language resolution and translation for share pages and API
// errors. Only the generated tables are trusted; request values are matched
// against a strict whitelist and never reflected into HTML.
import { readFileSync } from 'node:fs';

const SUPPORTED = ['zh-CN', 'zh-TW', 'en', 'ja'];
const FALLBACK = 'zh-CN';
const PLACEHOLDER = /\{([A-Za-z_][A-Za-z0-9_]*)\}/g;
const TABLES = loadTables();

function loadTables() {
  const tables = {};
  for (const tag of ['zh-TW', 'en', 'ja']) {
    for (const base of [new URL('./i18n/', import.meta.url), new URL('../i18n/', import.meta.url)]) {
      try {
        tables[tag] = JSON.parse(readFileSync(new URL(`${tag}.json`, base), 'utf8'));
        break;
      } catch (_) {
        // Try the next deployment layout.
      }
    }
    tables[tag] ||= {};
  }
  return tables;
}

export function normalizeLocale(value) {
  const raw = String(value || '').trim().replace(/_/g, '-').toLowerCase();
  if (!raw || !/^[a-z]{2,8}(-[a-z0-9]{1,8})*$/.test(raw)) return '';
  if (raw.startsWith('zh')) return /hant|tw|hk|mo/.test(raw) ? 'zh-TW' : 'zh-CN';
  if (raw.startsWith('en')) return 'en';
  if (raw.startsWith('ja')) return 'ja';
  return '';
}

export function parseAcceptLanguage(header) {
  if (!header) return '';
  const parts = String(header).split(',').map((part, index) => {
    const [range, ...params] = part.trim().split(';');
    let quality = 1;
    for (const param of params) {
      const match = /^\s*q=([0-9.]+)\s*$/i.exec(param);
      if (match) quality = Number(match[1]);
    }
    return { range, quality: Number.isFinite(quality) ? quality : 0, index };
  }).filter((item) => item.quality > 0 && item.range)
    .sort((a, b) => b.quality - a.quality || a.index - b.index);
  for (const item of parts) {
    const tag = normalizeLocale(item.range.split(';')[0]);
    if (tag) return tag;
  }
  return '';
}

export function parseCookies(header) {
  const cookies = {};
  if (!header) return cookies;
  for (const part of String(header).split(';')) {
    const index = part.indexOf('=');
    if (index < 0) continue;
    const key = part.slice(0, index).trim();
    if (!key || key in cookies) continue;
    let value = part.slice(index + 1).trim();
    try { value = decodeURIComponent(value); } catch (_) {}
    cookies[key] = value;
  }
  return cookies;
}

/** Locale precedence: ?lang= > neko_lang cookie > Accept-Language > zh-CN. */
export function resolveLocale(req) {
  let query = '';
  try {
    const rawQuery = new URL(req.url || '/', 'http://localhost').searchParams.get('lang');
    query = normalizeLocale(rawQuery);
  } catch (_) {}
  if (query) return query;
  const cookie = normalizeLocale(parseCookies(req.headers?.cookie).neko_lang);
  if (cookie) return cookie;
  const accepted = parseAcceptLanguage(req.headers?.['accept-language']);
  if (accepted) return accepted;
  return FALLBACK;
}

/** Translate a source template for a locale. Unknown sources pass through. */
export function t(locale, source, params = {}) {
  const tag = SUPPORTED.includes(locale) ? locale : FALLBACK;
  const entry = TABLES[tag]?.[source];
  let text;
  if (typeof entry === 'string') {
    text = entry;
  } else if (entry && typeof entry === 'object') {
    let count;
    for (const value of Object.values(params)) {
      if (typeof value === 'number' && Number.isFinite(value)) { count = value; break; }
    }
    text = count === 1
      ? (entry.one ?? entry.other ?? source)
      : (entry.other ?? entry.one ?? source);
  } else {
    text = source;
  }
  return String(text).replace(PLACEHOLDER, (match, name) =>
    params[name] === undefined || params[name] === null ? match : String(params[name]));
}

/** Localizes a known server message while leaving unknown text untouched. */
export function localizeMessage(locale, message, params = {}) {
  if (typeof message !== 'string' || !message) return message;
  return t(locale, message, params);
}

export const supportedLocales = SUPPORTED;
