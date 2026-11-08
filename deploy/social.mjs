// NekoPlayer 社区：关注、公开主页、私信、歌曲分享与 SSE 推送。
// 数据保存在 SuperPlayer-Web 的 SQLite 中；用户资料由账户中心公开 API 提供。
import { t as translateMessage } from './server-i18n.mjs';
import { DatabaseSync } from 'node:sqlite';
import { chmodSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { createHash, randomBytes, randomUUID } from 'node:crypto';

const USER_ID = /^[A-Za-z0-9_-]{8,64}$/;
const SHARE_TOKEN = /^[A-Za-z0-9_-]{16,64}$/;
const SOURCE = /^[A-Za-z0-9_.-]{1,64}$/;
const CONTROL = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/;
const DEFAULT_OPTIONS = Object.freeze({
  showSharer: true,
  cover: true,
  album: false,
  lyric: false,
  progress: false,
});

const fail = (status, message) => {
  const error = new Error(message);
  error.status = status;
  throw error;
};
const cleanId = (value) => String(value ?? '');
const userId = (value) => {
  const id = cleanId(value);
  if (!USER_ID.test(id)) fail(400, '无效的用户 ID');
  return id;
};
const text = (value, max, field, { optional = false, multiline = true } = {}) => {
  if (value == null || value === '') {
    if (optional) return '';
    fail(400, `缺少${field}`);
  }
  if (typeof value !== 'string') fail(400, `${field}格式无效`);
  const trimmed = value.trim();
  if (!trimmed && !optional) fail(400, `缺少${field}`);
  if ([...trimmed].length > max) fail(400, `${field}过长`);
  if (CONTROL.test(trimmed) || (!multiline && /[\r\n]/.test(trimmed))) {
    fail(400, `${field}包含无效字符`);
  }
  return trimmed;
};
const safeUrl = (value) => {
  if (typeof value !== 'string' || !value) return '';
  try {
    const url = new URL(value);
    return ['http:', 'https:'].includes(url.protocol) && value.length <= 1024
      ? url.toString()
      : '';
  } catch {
    return '';
  }
};
const integer = (value, { min = 0, max = Number.MAX_SAFE_INTEGER, fallback = 0 } = {}) => {
  const number = Number(value ?? fallback);
  return Number.isSafeInteger(number) && number >= min && number <= max ? number : fallback;
};

function normalizeSong(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail(400, '歌曲格式无效');
  const source = typeof input.source === 'string' && SOURCE.test(input.source)
    ? input.source
    : 'netease';
  const id = integer(input.id, { max: 9007199254740991 }) || integer(input.providerMediaId);
  const title = text(input.nm ?? input.title, 200, '歌名');
  const artist = text(input.ar ?? input.artist, 200, '歌手');
  const hash = text(input.hash, 64, 'hash', { optional: true }).toLowerCase();
  if (source === 'kugou' && !/^[a-f0-9]{32}$/.test(hash)) fail(400, '酷狗歌曲标识无效');
  const song = {
    id,
    nm: title,
    ar: artist,
    source,
    hash,
    albumId: text(input.albumId, 128, 'albumId', { optional: true }),
    albumAudioId: integer(input.albumAudioId),
    providerSource: text(input.providerSource, 32, 'providerSource', { optional: true }),
    providerMediaId: text(input.providerMediaId, 128, 'providerMediaId', { optional: true }),
    pluginMetadata: text(input.pluginMetadata, 2048, 'pluginMetadata', { optional: true }),
  };
  const cover = safeUrl(input.pc ?? input.artwork);
  if (cover) song.pc = cover;
  const album = text(input.al ?? input.album, 200, '专辑', { optional: true });
  if (album) song.al = album;
  for (const key of ['pluginSource', 'pluginData']) {
    const value = input[key];
    if (value && typeof value === 'object') {
      let encoded;
      try {
        encoded = JSON.stringify(value);
      } catch {
        fail(400, '插件歌曲信息无效');
      }
      if (encoded.length > 8192) fail(400, '插件歌曲信息过大');
      song[key] = value;
    }
  }
  return song;
}

function normalizeOptions(input) {
  const options = { ...DEFAULT_OPTIONS };
  if (input && typeof input === 'object') {
    for (const key of Object.keys(DEFAULT_OPTIONS)) {
      if (typeof input[key] === 'boolean') options[key] = input[key];
    }
  }
  return options;
}

function normalizeProgress(input) {
  if (!input || typeof input !== 'object') return null;
  const durationMs = integer(input.durationMs, { max: 24 * 3600 * 1000 });
  if (!durationMs) return null;
  const positionMs = Math.min(integer(input.positionMs, { max: durationMs }), durationMs);
  return { positionMs, durationMs };
}

function platformName(value) {
  if (typeof value === 'string') {
    const clean = value.trim().slice(0, 32);
    if (clean) return clean;
  }
  return '音乐';
}

function hashConversation(first, second) {
  const [a, b] = [String(first), String(second)].sort();
  return createHash('sha256').update(`${a}:${b}`).digest('hex').slice(0, 32);
}

function isBlocked(db, first, second) {
  return !!db.prepare(
    `SELECT 1 FROM blocks WHERE (blocker=? AND blocked=?) OR (blocker=? AND blocked=?)`,
  ).get(first, second, second, first);
}

function parseJson(value, fallback) {
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' ? parsed : fallback;
  } catch {
    return fallback;
  }
}

export function createSocialStore(filename, {
  now = () => Date.now(),
  fetchUsers = async () => [],
  publicBaseUrl = 'https://player.nekoh2o.top',
  profileTtlMs = 5 * 60 * 1000,
} = {}) {
  if (filename !== ':memory:') mkdirSync(dirname(filename), { recursive: true, mode: 0o700 });
  const db = new DatabaseSync(filename);
  if (filename !== ':memory:') chmodSync(filename, 0o600);
  db.exec(`
    PRAGMA journal_mode=WAL;
    PRAGMA foreign_keys=ON;
    PRAGMA busy_timeout=5000;
    CREATE TABLE IF NOT EXISTS profiles (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL DEFAULT '',
      nickname TEXT NOT NULL DEFAULT '',
      avatar TEXT NOT NULL DEFAULT '',
      bio TEXT NOT NULL DEFAULT '',
      fetched INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS profile_misses (
      id TEXT PRIMARY KEY,
      fetched INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS follows (
      follower TEXT NOT NULL,
      followee TEXT NOT NULL,
      created INTEGER NOT NULL,
      PRIMARY KEY (follower, followee)
    );
    CREATE INDEX IF NOT EXISTS follows_followee ON follows(followee, created DESC);
    CREATE TABLE IF NOT EXISTS blocks (
      blocker TEXT NOT NULL,
      blocked TEXT NOT NULL,
      created INTEGER NOT NULL,
      PRIMARY KEY (blocker, blocked)
    );
    CREATE TABLE IF NOT EXISTS conversations (
      id TEXT PRIMARY KEY,
      a TEXT NOT NULL,
      b TEXT NOT NULL,
      created INTEGER NOT NULL,
      updated INTEGER NOT NULL,
      UNIQUE (a, b)
    );
    CREATE INDEX IF NOT EXISTS conversations_a ON conversations(a, updated DESC);
    CREATE INDEX IF NOT EXISTS conversations_b ON conversations(b, updated DESC);
    CREATE TABLE IF NOT EXISTS messages (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      id TEXT NOT NULL UNIQUE,
      conversation TEXT NOT NULL REFERENCES conversations(id),
      sender TEXT NOT NULL,
      client_id TEXT,
      kind TEXT NOT NULL CHECK (kind IN ('text', 'song')),
      body TEXT NOT NULL DEFAULT '',
      song TEXT,
      share_token TEXT,
      created INTEGER NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      UNIQUE (sender, client_id)
    );
    CREATE INDEX IF NOT EXISTS messages_conversation_seq
      ON messages(conversation, seq DESC);
    CREATE TABLE IF NOT EXISTS conversation_reads (
      conversation TEXT NOT NULL,
      user TEXT NOT NULL,
      last_seq INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (conversation, user)
    );
    CREATE TABLE IF NOT EXISTS shares (
      token TEXT PRIMARY KEY,
      owner TEXT NOT NULL,
      song TEXT NOT NULL,
      platform TEXT NOT NULL,
      message TEXT NOT NULL DEFAULT '',
      lyric TEXT NOT NULL DEFAULT '',
      progress TEXT,
      options TEXT NOT NULL,
      created INTEGER NOT NULL,
      revoked INTEGER NOT NULL DEFAULT 0,
      views INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS shares_owner ON shares(owner, created DESC);
    CREATE TABLE IF NOT EXISTS mutations (
      user TEXT NOT NULL,
      bucket TEXT NOT NULL,
      created INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS mutations_user_bucket
      ON mutations(user, bucket, created);
    CREATE TABLE IF NOT EXISTS social_prefs (
      user TEXT PRIMARY KEY,
      dm_policy TEXT NOT NULL DEFAULT 'everyone',
      updated INTEGER NOT NULL
    );
  `);

  const baseUrl = publicBaseUrl.replace(/\/+$/, '');
  const transaction = (fn) => {
    db.exec('BEGIN IMMEDIATE');
    try {
      const result = fn();
      db.exec('COMMIT');
      return result;
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
  };
  const profileRow = (id) => {
    const row = db.prepare('SELECT * FROM profiles WHERE id=?').get(id);
    return row
      ? {
          id: row.id,
          username: row.username || '用户',
          nickname: row.nickname || row.username || '用户',
          avatar: row.avatar || '',
          bio: row.bio || '',
        }
      : { id, username: '用户', nickname: '用户', avatar: '', bio: '' };
  };
  const knownProfile = (id) => !!db.prepare('SELECT 1 FROM profiles WHERE id=?').get(id);
  const upsertProfile = (user) => {
    const id = cleanId(user?.id);
    if (!USER_ID.test(id)) return;
    db.prepare(
      `INSERT INTO profiles(id,username,nickname,avatar,bio,fetched)
       VALUES(?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET
         username=excluded.username, nickname=excluded.nickname,
         avatar=excluded.avatar, bio=excluded.bio, fetched=excluded.fetched`,
    ).run(
      id,
      String(user.username || '').slice(0, 80),
      String(user.nickname || user.username || '').slice(0, 80),
      safeUrl(user.avatar),
      String(user.bio || '').slice(0, 300),
      now(),
    );
    db.prepare('DELETE FROM profile_misses WHERE id=?').run(id);
  };
  const ensureProfiles = async (ids) => {
    const unique = [...new Set(ids.map(cleanId).filter((id) => USER_ID.test(id)))];
    if (!unique.length) return;
    const missing = [];
    for (const id of unique) {
      const row = db.prepare('SELECT fetched FROM profiles WHERE id=?').get(id);
      const miss = db.prepare('SELECT fetched FROM profile_misses WHERE id=?').get(id);
      const fresh = row && now() - row.fetched < profileTtlMs;
      const missed = miss && now() - miss.fetched < 60 * 1000;
      if (!fresh && !missed) missing.push(id);
    }
    if (!missing.length) return;
    try {
      const users = await fetchUsers(missing);
      const found = new Set();
      for (const user of Array.isArray(users) ? users : []) {
        upsertProfile(user);
        found.add(cleanId(user?.id));
      }
      for (const id of missing) {
        if (!found.has(id)) {
          db.prepare(
            `INSERT INTO profile_misses(id,fetched) VALUES(?,?)
             ON CONFLICT(id) DO UPDATE SET fetched=excluded.fetched`,
          ).run(id, now());
        }
      }
    } catch {
      // 账户中心短暂不可用时优先使用旧缓存；未缓存用户保持占位资料。
    }
  };
  const rate = (user, bucket, perMinute, perDay) => {
    const stamp = now();
    db.prepare('DELETE FROM mutations WHERE created<?').run(stamp - 24 * 3600 * 1000);
    const minute = db.prepare(
      'SELECT COUNT(*) AS n FROM mutations WHERE user=? AND bucket=? AND created>?',
    ).get(user, bucket, stamp - 60000).n;
    const day = db.prepare(
      'SELECT COUNT(*) AS n FROM mutations WHERE user=? AND bucket=? AND created>?',
    ).get(user, bucket, stamp - 24 * 3600 * 1000).n;
    if (minute >= perMinute || day >= perDay) fail(429, '操作过于频繁，请稍后重试');
    db.prepare('INSERT INTO mutations(user,bucket,created) VALUES(?,?,?)').run(user, bucket, stamp);
  };
  const countUnread = (conversation, user) => {
    const read = db.prepare(
      'SELECT last_seq FROM conversation_reads WHERE conversation=? AND user=?',
    ).get(conversation, user)?.last_seq || 0;
    return db.prepare(
      `SELECT COUNT(*) AS n FROM messages
       WHERE conversation=? AND sender<>? AND deleted=0 AND seq>?`,
    ).get(conversation, user, read).n;
  };
  const messageDto = (row, viewerId) => {
    const deleted = !!row.deleted;
    const sender = profileRow(row.sender);
    return {
      id: row.id,
      seq: row.seq,
      conversationId: row.conversation,
      sender,
      senderId: sender.id,
      kind: row.kind,
      text: deleted ? '' : row.body,
      song: deleted || !row.song ? null : parseJson(row.song, null),
      shareToken: deleted ? null : row.share_token || null,
      createdAt: row.created,
      deleted,
      owned: row.sender === viewerId,
    };
  };
  const conversationDto = (row, viewerId, { ensure = true } = {}) => {
    const peerId = row.a === viewerId ? row.b : row.a;
    if (ensure) void ensureProfiles([peerId]);
    const last = db.prepare(
      'SELECT * FROM messages WHERE conversation=? ORDER BY seq DESC LIMIT 1',
    ).get(row.id);
    return {
      id: row.id,
      peer: profileRow(peerId),
      peerId,
      lastMessage: last ? messageDto(last, viewerId) : null,
      unread: countUnread(row.id, viewerId),
      updatedAt: row.updated,
      createdAt: row.created,
    };
  };
  const shareDto = (row, viewerId) => {
    const options = { ...DEFAULT_OPTIONS, ...parseJson(row.options, {}) };
    const song = parseJson(row.song, null) || { id: 0, nm: '未知歌曲', ar: '未知歌手', source: 'netease' };
    if (!options.cover) delete song.pc;
    if (!options.album) delete song.al;
    return {
      token: row.token,
      url: `${baseUrl}/s/${row.token}`,
      appUrl: `nekoplayer://share?token=${row.token}`,
      platform: row.platform,
      song,
      message: row.message || '',
      lyricSnippet: options.lyric ? row.lyric || '' : '',
      progress: options.progress ? parseJson(row.progress, null) : null,
      options,
      sharer: options.showSharer ? profileRow(row.owner) : null,
      createdAt: row.created,
      revoked: !!row.revoked,
      views: row.views || 0,
      owned: row.owner === viewerId,
    };
  };
  const shareVisibleTo = (row, viewerId) => {
    if (row.revoked) return false;
    if (!viewerId) return true;
    return !isBlocked(db, row.owner, viewerId);
  };
  const conversationRow = (user, peer) => {
    const [a, b] = [String(user), String(peer)].sort();
    return db.prepare('SELECT * FROM conversations WHERE a=? AND b=?').get(a, b);
  };
  const ensureConversation = (user, peer) => {
    const [a, b] = [String(user), String(peer)].sort();
    let row = conversationRow(user, peer);
    if (row) {
      db.prepare('UPDATE conversations SET updated=? WHERE id=?').run(now(), row.id);
      return db.prepare('SELECT * FROM conversations WHERE id=?').get(row.id);
    }
    const stamp = now();
    const id = hashConversation(a, b);
    db.prepare(
      'INSERT INTO conversations(id,a,b,created,updated) VALUES(?,?,?,?,?)',
    ).run(id, a, b, stamp, stamp);
    row = db.prepare('SELECT * FROM conversations WHERE id=?').get(id);
    return row;
  };
  const participant = (conversationId, user) => {
    const row = db.prepare('SELECT * FROM conversations WHERE id=?').get(conversationId);
    if (!row) fail(404, '会话不存在');
    if (row.a !== user && row.b !== user) fail(403, '无权访问该会话');
    return row;
  };
  const insertShare = (owner, input, optionsOverride = null) => {
    const song = normalizeSong(input.song);
    const options = optionsOverride || normalizeOptions(input.options);
    const message = text(input.message, 200, '留言', { optional: true });
    const lyric = options.lyric
      ? text(input.lyricSnippet, 300, '歌词片段', { optional: true })
      : '';
    const progress = options.progress ? normalizeProgress(input.progress) : null;
    const token = randomBytes(16).toString('base64url').slice(0, 22);
    const stamp = now();
    db.prepare(
      `INSERT INTO shares(token,owner,song,platform,message,lyric,progress,options,created)
       VALUES(?,?,?,?,?,?,?,?,?)`,
    ).run(
      token,
      owner,
      JSON.stringify(song),
      platformName(input.platform),
      message,
      lyric,
      progress ? JSON.stringify(progress) : null,
      JSON.stringify(options),
      stamp,
    );
    return db.prepare('SELECT * FROM shares WHERE token=?').get(token);
  };
  const followCounts = (id) => ({
    followers: db.prepare('SELECT COUNT(*) AS n FROM follows WHERE followee=?').get(id).n,
    following: db.prepare('SELECT COUNT(*) AS n FROM follows WHERE follower=?').get(id).n,
  });
  const preference = (user) =>
    db.prepare('SELECT dm_policy FROM social_prefs WHERE user=?').get(user)?.dm_policy || 'everyone';

  return {
    close() {
      db.close();
    },
    ensureProfiles,
    upsertProfile,
    async getProfile(id, viewerId = '') {
      id = userId(id);
      await ensureProfiles([id, viewerId].filter(Boolean));
      if (!knownProfile(id)) fail(404, '用户不存在');
      const profile = profileRow(id);
      const counts = followCounts(id);
      return {
        ...profile,
        ...counts,
        isFollowing: !!viewerId && !!db.prepare(
          'SELECT 1 FROM follows WHERE follower=? AND followee=?',
        ).get(viewerId, id),
        isSelf: viewerId === id,
        blocked: !!viewerId && isBlocked(db, viewerId, id),
      };
    },
    async follow(user, target, following) {
      user = userId(user);
      target = userId(target);
      if (user === target) fail(400, '不能关注自己');
      await ensureProfiles([target]);
      if (!knownProfile(target)) fail(404, '用户不存在');
      if (isBlocked(db, user, target)) fail(403, '无法关注该用户');
      const exists = !!db.prepare(
        'SELECT 1 FROM follows WHERE follower=? AND followee=?',
      ).get(user, target);
      if (following !== exists) {
        transaction(() => {
          rate(user, 'follow', 30, 300);
          if (following) {
            db.prepare('INSERT INTO follows(follower,followee,created) VALUES(?,?,?)')
              .run(user, target, now());
          } else {
            db.prepare('DELETE FROM follows WHERE follower=? AND followee=?').run(user, target);
          }
        });
      }
      const counts = followCounts(target);
      return {
        following,
        followers: counts.followers,
        followingCount: counts.following,
      };
    },
    async listFollows(id, kind, { offset = 0, limit = 30 } = {}) {
      id = userId(id);
      offset = Math.max(0, Math.min(10000, Number(offset) || 0));
      limit = Math.max(1, Math.min(50, Number(limit) || 30));
      const rows = kind === 'followers'
        ? db.prepare(
            'SELECT follower AS id FROM follows WHERE followee=? ORDER BY created DESC LIMIT ? OFFSET ?',
          ).all(id, limit, offset)
        : db.prepare(
            'SELECT followee AS id FROM follows WHERE follower=? ORDER BY created DESC LIMIT ? OFFSET ?',
          ).all(id, limit, offset);
      await ensureProfiles(rows.map((row) => row.id));
      return rows.map((row) => profileRow(row.id));
    },
    async setBlock(user, target, blocked) {
      user = userId(user);
      target = userId(target);
      if (user === target) fail(400, '不能拉黑自己');
      await ensureProfiles([target]);
      if (!knownProfile(target)) fail(404, '用户不存在');
      const exists = !!db.prepare(
        'SELECT 1 FROM blocks WHERE blocker=? AND blocked=?',
      ).get(user, target);
      if (blocked !== exists) {
        transaction(() => {
          rate(user, 'block', 30, 300);
          if (blocked) {
            db.prepare('INSERT INTO blocks(blocker,blocked,created) VALUES(?,?,?)')
              .run(user, target, now());
          } else {
            db.prepare('DELETE FROM blocks WHERE blocker=? AND blocked=?').run(user, target);
          }
        });
      }
      return { blocked };
    },
    async getPreferences(user) {
      return { dmPolicy: preference(user) };
    },
    async setPreferences(user, { dmPolicy }) {
      if (!['everyone', 'following'].includes(dmPolicy)) fail(400, '无效的私信设置');
      db.prepare(
        `INSERT INTO social_prefs(user,dm_policy,updated) VALUES(?,?,?)
         ON CONFLICT(user) DO UPDATE SET dm_policy=excluded.dm_policy, updated=excluded.updated`,
      ).run(user, dmPolicy, now());
      return { dmPolicy };
    },
    async createShare(user, input) {
      user = userId(user);
      await ensureProfiles([user]);
      return transaction(() => {
        rate(user, 'share', 10, 100);
        const row = insertShare(user, input);
        return shareDto(row, user);
      });
    },
    async getShare(token, { viewerId = '', allowRevoked = false, countView = false } = {}) {
      if (!SHARE_TOKEN.test(String(token || ''))) fail(404, '分享不存在');
      const row = db.prepare('SELECT * FROM shares WHERE token=?').get(token);
      if (!row) fail(404, '分享不存在或已被删除');
      if (row.revoked && !allowRevoked) fail(410, '分享已失效');
      if (!row.revoked && !shareVisibleTo(row, viewerId)) fail(404, '分享不存在或已被删除');
      if (countView && !row.revoked) {
        db.prepare('UPDATE shares SET views=views+1 WHERE token=?').run(token);
        row.views += 1;
      }
      if (!row.revoked) await ensureProfiles([row.owner]);
      return shareDto(row, viewerId);
    },
    async revokeShare(token, user) {
      const row = db.prepare('SELECT * FROM shares WHERE token=?').get(token);
      if (!row) fail(404, '分享不存在');
      if (row.owner !== user) fail(403, '只能删除自己的分享');
      db.prepare('UPDATE shares SET revoked=1 WHERE token=?').run(token);
      return { revoked: true };
    },
    async listUserShares(id, viewerId = '', { limit = 30 } = {}) {
      id = userId(id);
      await ensureProfiles([id]);
      if (viewerId && isBlocked(db, viewerId, id)) return [];
      return db.prepare(
        'SELECT * FROM shares WHERE owner=? AND revoked=0 ORDER BY created DESC LIMIT ?',
      ).all(id, Math.max(1, Math.min(50, Number(limit) || 30)))
        .map((row) => shareDto(row, viewerId))
        .filter((share) => share.options.showSharer);
    },
    async feed(user, { limit = 30 } = {}) {
      const rows = db.prepare(
        `SELECT s.* FROM shares s
         JOIN follows f ON f.followee=s.owner
         WHERE f.follower=? AND s.revoked=0
         ORDER BY s.created DESC LIMIT ?`,
      ).all(user, Math.max(1, Math.min(50, Number(limit) || 30)));
      const visible = rows.filter((row) => !isBlocked(db, user, row.owner));
      await ensureProfiles(visible.map((row) => row.owner));
      return visible
        .map((row) => shareDto(row, user))
        .filter((share) => share.options.showSharer);
    },
    async listConversations(user, { limit = 50 } = {}) {
      user = userId(user);
      const rows = db.prepare(
        'SELECT * FROM conversations WHERE a=? OR b=? ORDER BY updated DESC LIMIT ?',
      ).all(user, user, Math.max(1, Math.min(100, Number(limit) || 50)));
      const peers = rows.map((row) => (row.a === user ? row.b : row.a));
      await ensureProfiles(peers);
      return rows.map((row) => conversationDto(row, user));
    },
    async openConversation(user, peer) {
      user = userId(user);
      peer = userId(peer);
      if (user === peer) fail(400, '不能和自己创建会话');
      await ensureProfiles([peer]);
      if (!knownProfile(peer)) fail(404, '用户不存在');
      if (isBlocked(db, user, peer)) fail(403, '无法与该用户私信');
      const row = transaction(() => ensureConversation(user, peer));
      return conversationDto(row, user);
    },
    async getConversation(user, conversationId) {
      user = userId(user);
      const row = participant(String(conversationId), user);
      await ensureProfiles([row.a, row.b]);
      return conversationDto(row, user);
    },
    async listMessages(user, conversationId, { afterSeq = 0, beforeSeq = 0, limit = 50 } = {}) {
      user = userId(user);
      const conversation = participant(String(conversationId), user);
      limit = Math.max(1, Math.min(100, Number(limit) || 50));
      let rows;
      if (Number(afterSeq) > 0) {
        rows = db.prepare(
          'SELECT * FROM messages WHERE conversation=? AND seq>? ORDER BY seq ASC LIMIT ?',
        ).all(conversation.id, Number(afterSeq), limit);
      } else if (Number(beforeSeq) > 0) {
        rows = db.prepare(
          'SELECT * FROM messages WHERE conversation=? AND seq<? ORDER BY seq DESC LIMIT ?',
        ).all(conversation.id, Number(beforeSeq), limit).reverse();
      } else {
        rows = db.prepare(
          'SELECT * FROM messages WHERE conversation=? ORDER BY seq DESC LIMIT ?',
        ).all(conversation.id, limit).reverse();
      }
      await ensureProfiles(rows.map((row) => row.sender));
      const messages = rows.map((row) => messageDto(row, user));
      return {
        conversation: conversationDto(conversation, user),
        messages,
        more: messages.length >= limit,
      };
    },
    async sendMessage(user, { to, kind = 'text', body = '', song = null, platform = '', clientId = '' } = {}) {
      user = userId(user);
      to = userId(to);
      if (user === to) fail(400, '不能给自己发消息');
      if (!['text', 'song'].includes(kind)) fail(400, '消息类型无效');
      await ensureProfiles([to]);
      if (!knownProfile(to)) fail(404, '接收者不存在');
      if (isBlocked(db, user, to)) fail(403, '无法向该用户发送消息');
      clientId = text(clientId, 80, 'clientId', { optional: true, multiline: false });
      if (clientId) {
        const existing = db.prepare(
          'SELECT * FROM messages WHERE sender=? AND client_id=?',
        ).get(user, clientId);
        if (existing) {
          return {
            message: messageDto(existing, user),
            conversation: conversationDto(participant(existing.conversation, user), user),
            duplicate: true,
          };
        }
      }
      let conversation = conversationRow(user, to);
      if (!conversation) {
        if (preference(to) === 'following') {
          const allowed = db.prepare(
            'SELECT 1 FROM follows WHERE follower=? AND followee=?',
          ).get(to, user);
          if (!allowed) fail(403, '对方只接受关注对象的私信');
        }
      }
      const caption = kind === 'song' ? text(body, 200, '消息', { optional: true }) : '';
      const content = kind === 'text' ? text(body, 2000, '消息') : caption;
      return transaction(() => {
        rate(user, 'message', 20, 500);
        conversation = ensureConversation(user, to);
        let shareToken = null;
        let songJson = null;
        if (kind === 'song') {
          const row = insertShare(user, { song, platform, message: '' }, {
            showSharer: false,
            cover: true,
            album: true,
            lyric: false,
            progress: false,
          });
          shareToken = row.token;
          songJson = row.song;
        }
        const id = randomUUID();
        const stamp = now();
        db.prepare(
          `INSERT INTO messages(id,conversation,sender,client_id,kind,body,song,share_token,created)
           VALUES(?,?,?,?,?,?,?,?,?)`,
        ).run(
          id,
          conversation.id,
          user,
          clientId || null,
          kind,
          content,
          songJson,
          shareToken,
          stamp,
        );
        db.prepare('UPDATE conversations SET updated=? WHERE id=?').run(stamp, conversation.id);
        const row = db.prepare('SELECT * FROM messages WHERE id=?').get(id);
        return {
          message: messageDto(row, user),
          conversation: conversationDto(conversation, user),
          duplicate: false,
        };
      });
    },
    async markRead(user, conversationId, seq) {
      user = userId(user);
      const conversation = participant(String(conversationId), user);
      const last = Math.max(0, integer(seq));
      const existing = db.prepare(
        'SELECT last_seq FROM conversation_reads WHERE conversation=? AND user=?',
      ).get(conversation.id, user)?.last_seq || 0;
      if (last > existing) {
        db.prepare(
          `INSERT INTO conversation_reads(conversation,user,last_seq) VALUES(?,?,?)
           ON CONFLICT(conversation,user) DO UPDATE SET last_seq=excluded.last_seq`,
        ).run(conversation.id, user, last);
      }
      return { unread: countUnread(conversation.id, user), lastSeq: Math.max(last, existing) };
    },
    async deleteMessage(user, messageId) {
      user = userId(user);
      const row = db.prepare('SELECT * FROM messages WHERE id=?').get(String(messageId));
      if (!row) fail(404, '消息不存在');
      if (row.sender !== user) fail(403, '只能撤回自己的消息');
      transaction(() => {
        db.prepare(
          `UPDATE messages SET deleted=1,body='',song=NULL,share_token=NULL WHERE id=?`,
        ).run(row.id);
        if (row.share_token) {
          db.prepare('UPDATE shares SET revoked=1 WHERE token=?').run(row.share_token);
        }
      });
      const updated = db.prepare('SELECT * FROM messages WHERE id=?').get(row.id);
      return { message: messageDto(updated, user), conversationId: row.conversation };
    },
    async unreadTotal(user) {
      const rows = db.prepare(
        'SELECT id FROM conversations WHERE a=? OR b=?',
      ).all(user, user);
      return rows.reduce((total, row) => total + countUnread(row.id, user), 0);
    },
  };
}

export function createEventHub({ heartbeatMs = 20000, maxPerUser = 3, lifetimeMs = 30 * 60 * 1000 } = {}) {
  const users = new Map();
  const subscribe = (id, res) => {
    let entry = users.get(id);
    if (!entry) {
      entry = { connections: new Set(), timer: null };
      users.set(id, entry);
    }
    while (entry.connections.size >= maxPerUser) {
      const oldest = entry.connections.values().next().value;
      clearTimeout(oldest.timer);
      try {
        oldest.res.end();
      } catch {}
      entry.connections.delete(oldest);
    }
    const connection = { res, timer: null };
    entry.connections.add(connection);
    if (!entry.timer) {
      entry.timer = setInterval(() => {
        for (const current of [...entry.connections]) {
          try {
            current.res.write(': ping\n\n');
          } catch {
            entry.connections.delete(current);
          }
        }
        if (!entry.connections.size && users.get(id) === entry) {
          clearInterval(entry.timer);
          users.delete(id);
        }
      }, heartbeatMs);
      entry.timer.unref?.();
    }
    connection.timer = setTimeout(() => {
      try {
        res.end();
      } catch {}
      entry.connections.delete(connection);
      if (!entry.connections.size && users.get(id) === entry) {
        clearInterval(entry.timer);
        users.delete(id);
      }
    }, lifetimeMs);
    connection.timer.unref?.();
    return {
      send(event, payload) {
        try {
          res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
        } catch {}
      },
      close() {
        clearTimeout(connection.timer);
        entry.connections.delete(connection);
        if (!entry.connections.size && users.get(id) === entry) {
          clearInterval(entry.timer);
          users.delete(id);
        }
      },
    };
  };
  const publish = (id, event, payload) => {
    const entry = users.get(String(id));
    if (!entry) return 0;
    let count = 0;
    for (const connection of [...entry.connections]) {
      try {
        connection.res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
        count += 1;
      } catch {
        entry.connections.delete(connection);
      }
    }
    return count;
  };
  return {
    subscribe,
    publish,
    closeAll() {
      for (const entry of users.values()) {
        clearInterval(entry.timer);
        for (const connection of entry.connections) {
          clearTimeout(connection.timer);
          try {
            connection.res.end();
          } catch {}
        }
      }
      users.clear();
    },
    connectionCount(id) {
      return users.get(String(id))?.connections.size || 0;
    },
  };
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function safeJsonForHtml(value) {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

export function renderShareHtml(template, share, { publicBaseUrl = 'https://player.nekoh2o.top', locale = 'zh-CN' } = {}) {
  const tr = (source, params) => translateMessage(locale, source, params);
  const base = publicBaseUrl.replace(/\/+$/, '');
  let title = tr('NekoPlayer 音乐分享');
  let metas = '<meta name="robots" content="noindex">';
  let data = { error: share?.revoked ? 'revoked' : 'notFound' };
  if (share && !share.revoked) {
    const song = share.song || {};
    title = `${song.nm || tr('音乐')} - ${song.ar || tr('未知歌手')}`;
    data = { share };
    const description = [
      song.ar,
      share.platform,
      share.sharer?.nickname,
      share.message,
    ].filter(Boolean).join(' · ');
    metas = [
      `<meta property="og:type" content="music.song">`,
      `<meta property="og:site_name" content="NekoPlayer">`,
      `<meta property="og:locale" content="${locale === 'zh-CN' ? 'zh_CN' : locale === 'zh-TW' ? 'zh_TW' : locale === 'ja' ? 'ja_JP' : 'en_US'}">`,
      `<meta property="og:title" content="${escapeHtml(title)}">`,
      `<meta property="og:description" content="${escapeHtml(description)}">`,
      `<meta property="og:url" content="${escapeHtml(share.url || `${base}/s/${share.token}`)}">`,
      `<meta name="twitter:card" content="${song.pc ? 'summary_large_image' : 'summary'}">`,
      song.pc
        ? `<meta property="og:image" content="${escapeHtml(song.pc)}">`
        : '',
      `<meta property="al:android:package" content="top.nekoh2o.player">`,
      `<meta property="al:android:app_name" content="NekoPlayer">`,
      `<meta property="al:android:url" content="${escapeHtml(share.appUrl || `nekoplayer://share?token=${share.token}`)}">`,
    ].filter(Boolean).join('\n    ');
  }
  return template
    .replace('<html lang="zh-CN"', `<html lang="${locale}"`)
    .replaceAll('<!--SHARE_TITLE-->', escapeHtml(title))
    .replace('<!--SHARE_META-->', metas)
    .replace('<!--SHARE_DATA-->', safeJsonForHtml(data));
}

export function installSocial(app, {
  dataRoot,
  resolveUser,
  accountCenterUrl = 'https://account.nekoh2o.top',
  publicBaseUrl = 'https://player.nekoh2o.top',
  enabled = true,
  fetchImpl = globalThis.fetch,
  jsonParser = null,
} = {}) {
  if (!enabled) {
    console.warn('[社区] SOCIAL_ENABLED=0，社区接口未启用');
    return null;
  }
  const center = new URL(accountCenterUrl);
  if (center.protocol !== 'https:') throw new Error('账户中心地址必须使用 HTTPS');
  const fetchUsers = async (ids) => {
    const url = new URL('/api/public/users', center);
    url.searchParams.set('ids', ids.join(','));
    const response = await fetchImpl(url, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(3500),
    });
    if (!response.ok) throw new Error(`账户中心返回 ${response.status}`);
    const body = await response.json();
    return body.code === 0 && Array.isArray(body.users) ? body.users : [];
  };
  const searchUsers = async (query) => {
    const url = new URL('/api/public/users/search', center);
    url.searchParams.set('q', query);
    const response = await fetchImpl(url, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(3500),
    });
    if (!response.ok) throw new Error(`账户中心返回 ${response.status}`);
    const body = await response.json();
    return body.code === 0 && Array.isArray(body.users) ? body.users : [];
  };
  const store = createSocialStore(join(dataRoot, 'social', 'social.sqlite'), {
    fetchUsers,
    publicBaseUrl,
  });
  const hub = createEventHub();
  const json = jsonParser || ((req, res, next) => next());
  const viewer = (req) => resolveUser(req)?.user || null;
  const required = (req) => {
    const user = viewer(req);
    if (!user || user.id == null) fail(401, '请先登录本站账号');
    return user;
  };
  const handle = (action) => (req, res) => {
    res.set('Cache-Control', 'no-store, no-cache, must-revalidate');
    res.set('X-Accel-Buffering', 'no');
    res.set('X-Accel-Expires', '0');
    Promise.resolve()
      .then(() => action(req, res))
      .catch((error) => {
        const status = Number(error.status) || 500;
        if (status >= 500) console.error('[社区]', error);
        if (!res.headersSent) {
          res.status(status).json({
            code: status,
            msg: status >= 500 ? '社区服务暂时不可用' : error.message,
          });
        }
      });
  };
  const publicLimits = new Map();
  const publicLimit = (req) => {
    const key = req.ip || req.socket?.remoteAddress || 'anonymous';
    const cutoff = Date.now() - 60000;
    const hits = (publicLimits.get(key) || []).filter((time) => time > cutoff);
    if (hits.length >= 120) fail(429, '请求过于频繁，请稍后再试');
    hits.push(Date.now());
    publicLimits.set(key, hits);
    if (publicLimits.size > 2000) {
      for (const [name, times] of publicLimits) {
        if (!times.some((time) => time > cutoff)) publicLimits.delete(name);
      }
    }
  };

  app.get('/social/shares/:token', handle(async (req) => {
    publicLimit(req);
    const share = await store.getShare(req.params.token, {
      viewerId: viewer(req)?.id || '',
      countView: true,
    });
    req.res.json({ code: 0, share });
  }));

  app.post('/social/shares', json, handle(async (req, res) => {
    const user = required(req);
    const share = await store.createShare(user.id, req.body || {});
    res.json({ code: 0, share });
  }));

  app.delete('/social/shares/:token', handle(async (req, res) => {
    const user = required(req);
    res.json({ code: 0, ...(await store.revokeShare(req.params.token, String(user.id))) });
  }));

  app.get('/social/users/search', handle(async (req, res) => {
    const user = required(req);
    const query = String(req.query.q || '').trim();
    if (query.length < 2 || query.length > 64) fail(400, '搜索词需为 2–64 个字符');
    const users = await searchUsers(query);
    await store.ensureProfiles(users.map((entry) => entry.id));
    const blocked = new Set();
    const result = [];
    for (const entry of users) {
      const profile = await store.getProfile(entry.id, String(user.id));
      if (!profile.blocked) result.push(profile);
    }
    res.json({ code: 0, users: result });
  }));

  app.get('/social/users/:id', handle(async (req, res) => {
    publicLimit(req);
    const profile = await store.getProfile(req.params.id, viewer(req)?.id || '');
    res.json({ code: 0, profile });
  }));

  app.get('/social/users/:id/shares', handle(async (req, res) => {
    const shares = await store.listUserShares(req.params.id, viewer(req)?.id || '');
    res.json({ code: 0, shares });
  }));

  app.get('/social/users/:id/followers', handle(async (req, res) => {
    res.json({
      code: 0,
      users: await store.listFollows(req.params.id, 'followers', req.query),
    });
  }));

  app.get('/social/users/:id/following', handle(async (req, res) => {
    res.json({
      code: 0,
      users: await store.listFollows(req.params.id, 'following', req.query),
    });
  }));

  app.post('/social/users/:id/follow', json, handle(async (req, res) => {
    const user = required(req);
    const following = req.body?.following !== false;
    const result = await store.follow(String(user.id), req.params.id, following);
    hub.publish(req.params.id, 'follow', { followerId: String(user.id) });
    res.json({ code: 0, ...result });
  }));

  app.delete('/social/users/:id/follow', handle(async (req, res) => {
    const user = required(req);
    res.json({
      code: 0,
      ...(await store.follow(String(user.id), req.params.id, false)),
    });
  }));

  app.post('/social/blocks/:id', json, handle(async (req, res) => {
    const user = required(req);
    const blocked = req.body?.blocked !== false;
    res.json({ code: 0, ...(await store.setBlock(String(user.id), req.params.id, blocked)) });
  }));

  app.delete('/social/blocks/:id', handle(async (req, res) => {
    const user = required(req);
    res.json({ code: 0, ...(await store.setBlock(String(user.id), req.params.id, false)) });
  }));

  app.get('/social/feed', handle(async (req, res) => {
    const user = required(req);
    res.json({ code: 0, shares: await store.feed(String(user.id), req.query) });
  }));

  app.get('/social/conversations', handle(async (req, res) => {
    const user = required(req);
    const conversations = await store.listConversations(String(user.id), req.query);
    res.json({ code: 0, conversations });
  }));

  app.get('/social/conversations/with/:peerId', handle(async (req, res) => {
    const user = required(req);
    try {
      const conversation = await store.openConversation(String(user.id), req.params.peerId);
      res.json({ code: 0, conversation });
    } catch (error) {
      if (error.status === 404) return res.json({ code: 0, conversation: null });
      throw error;
    }
  }));

  app.post('/social/conversations', json, handle(async (req, res) => {
    const user = required(req);
    const conversation = await store.openConversation(
      String(user.id),
      req.body?.peer || req.body?.to,
    );
    res.json({ code: 0, conversation });
  }));

  app.get('/social/conversations/:id/messages', handle(async (req, res) => {
    const user = required(req);
    const result = await store.listMessages(
      String(user.id),
      req.params.id,
      req.query,
    );
    res.json({ code: 0, ...result });
  }));

  app.post('/social/conversations/:id/read', json, handle(async (req, res) => {
    const user = required(req);
    res.json({
      code: 0,
      ...(await store.markRead(String(user.id), req.params.id, req.body?.seq)),
    });
  }));

  app.post('/social/messages', json, handle(async (req, res) => {
    const user = required(req);
    const result = await store.sendMessage(String(user.id), req.body || {});
    const senderConversation = await store.getConversation(String(user.id), result.conversation.id);
    const peer = senderConversation.peerId;
    const recipientConversation = await store.getConversation(peer, result.conversation.id);
    hub.publish(peer, 'message', {
      message: { ...result.message, owned: false },
      conversation: recipientConversation,
      peerId: String(user.id),
    });
    hub.publish(String(user.id), 'message', {
      message: result.message,
      conversation: senderConversation,
      peerId: peer,
    });
    res.json({ code: 0, ...result });
  }));

  app.delete('/social/messages/:id', handle(async (req, res) => {
    const user = required(req);
    const result = await store.deleteMessage(String(user.id), req.params.id);
    const conversation = await store.getConversation(String(user.id), result.conversationId);
    hub.publish(conversation.peerId, 'messageDeleted', {
      messageId: result.message.id,
      conversationId: result.conversationId,
    });
    hub.publish(String(user.id), 'messageDeleted', {
      messageId: result.message.id,
      conversationId: result.conversationId,
    });
    res.json({ code: 0, message: result.message });
  }));

  app.get('/social/preferences', handle(async (req, res) => {
    const user = required(req);
    res.json({ code: 0, preferences: await store.getPreferences(String(user.id)) });
  }));

  app.put('/social/preferences', json, handle(async (req, res) => {
    const user = required(req);
    res.json({
      code: 0,
      preferences: await store.setPreferences(String(user.id), req.body || {}),
    });
  }));

  app.get('/social/unread', handle(async (req, res) => {
    const user = required(req);
    res.json({ code: 0, unread: await store.unreadTotal(String(user.id)) });
  }));

  app.get('/social/events', (req, res) => {
    let user;
    try {
      user = required(req);
    } catch (error) {
      return res.status(error.status || 401).json({ code: error.status || 401, msg: error.message });
    }
    res.status(200);
    res.set({
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
      'X-Accel-Expires': '0',
    });
    res.flushHeaders?.();
    const connection = hub.subscribe(String(user.id), res);
    connection.send('ready', { userId: String(user.id) });
    res.write('retry: 3000\n\n');
    req.on('close', () => connection.close());
  });

  return { store, hub, renderShareHtml };
}
