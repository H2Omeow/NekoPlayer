import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, chmodSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { resolveLocale, t as translateMessage } from './server-i18n.mjs';

const fail = (status, message) => { const error = new Error(message); error.status = status; throw error; };
const resource = value => {
  if (typeof value !== 'string' || !/^(netease:[1-9][0-9]{0,19}|kugou:[a-fA-F0-9]{32})$/.test(value)) fail(400, '无效歌曲标识');
  return value.toLowerCase();
};
const identity = user => {
  if (!user?.id || typeof user.id === 'object') fail(401, '请先登录本站账号');
  return { id: String(user.id), name: String(user.username || '用户').slice(0, 80) };
};

export function createCommentStore(filename, { now = () => Date.now() } = {}) {
  if (filename !== ':memory:') mkdirSync(dirname(filename), { recursive: true, mode: 0o700 });
  const db = new DatabaseSync(filename);
  if (filename !== ':memory:') chmodSync(filename, 0o600);
  db.exec('PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;');
  db.exec('CREATE TABLE IF NOT EXISTS comments (id TEXT PRIMARY KEY, song TEXT NOT NULL, author TEXT NOT NULL, name TEXT NOT NULL, content TEXT NOT NULL, parent TEXT REFERENCES comments(id), created INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0); CREATE INDEX IF NOT EXISTS comment_song ON comments(song,parent,created DESC); CREATE INDEX IF NOT EXISTS comment_author ON comments(author,created); CREATE TABLE IF NOT EXISTS likes (comment TEXT REFERENCES comments(id), user TEXT, PRIMARY KEY(comment,user)); CREATE TABLE IF NOT EXISTS mutations (user TEXT, created INTEGER); CREATE INDEX IF NOT EXISTS mutation_user ON mutations(user,created);');
  if (!db.prepare('PRAGMA table_info(comments)').all().some(column => column.name === 'reply_to')) db.exec('ALTER TABLE comments ADD COLUMN reply_to TEXT REFERENCES comments(id)');
  const get = id => db.prepare('SELECT * FROM comments WHERE id=?').get(String(id));
  const dto = (row, uid) => ({ id: row.id, userId: row.author, userName: row.name, content: row.deleted ? '' : row.content,
    parentId: row.parent, replyTo: row.reply_to, quotedUser: row.reply_to ? get(row.reply_to)?.name || '' : '',
    quotedContent: row.reply_to ? (get(row.reply_to)?.deleted ? '该评论已删除' : get(row.reply_to)?.content || '') : '', createdAt: row.created, deleted: !!row.deleted, owned: row.author === uid,
    liked: !!db.prepare('SELECT 1 FROM likes WHERE comment=? AND user=?').get(row.id, uid || ''),
    likes: db.prepare('SELECT COUNT(*) AS n FROM likes WHERE comment=?').get(row.id).n,
    replies: db.prepare('SELECT COUNT(*) AS n FROM comments WHERE parent=?').get(row.id).n });
  const transaction = fn => { db.exec('BEGIN IMMEDIATE'); try { const result = fn(); db.exec('COMMIT'); return result; } catch (error) { db.exec('ROLLBACK'); throw error; } };
  function throttle(uid) {
    const cutoff = now() - 60000;
    db.prepare('DELETE FROM mutations WHERE created<?').run(cutoff);
    if (db.prepare('SELECT COUNT(*) AS n FROM mutations WHERE user=?').get(uid).n >= 60) fail(429, '操作过于频繁，请稍后重试');
    db.prepare('INSERT INTO mutations VALUES(?,?)').run(uid, now());
  }
  return {
    list(song, { offset = 0, limit = 20, parent = null, user = null } = {}) {
      song = resource(song); offset = Math.floor(Math.max(0, Math.min(100000, Number(offset) || 0))); limit = Math.floor(Math.max(1, Math.min(50, Number(limit) || 20)));
      if (parent && get(parent)?.song !== song) fail(404, '回复主题不存在');
      const uid = user?.id ? String(user.id) : '';
      const rows = db.prepare('SELECT * FROM comments WHERE song=? AND parent IS ? ORDER BY created DESC,id DESC LIMIT ? OFFSET ?').all(song, parent, limit, offset);
      const total = db.prepare('SELECT COUNT(*) AS n FROM comments WHERE song=? AND parent IS ?').get(song, parent).n;
      return { code: 200, comments: rows.map(row => dto(row, uid)), total, more: offset + rows.length < total };
    },
    add(song, content, parent, user) {
      song = resource(song); const auth = identity(user);
      if (typeof content !== 'string' || !(content = content.trim()) || content.length > 2000) fail(400, '评论需为 1–2000 个字符');
      return transaction(() => {
        throttle(auth.id);
        if (db.prepare('SELECT COUNT(*) AS n FROM comments WHERE author=? AND created>?').get(auth.id, now()-60000).n >= 5) fail(429, '评论发送过于频繁，请稍后重试');
        const target = parent ? get(parent) : null;
        if (parent && (!target || target.song !== song || target.deleted)) fail(404, '被回复评论不存在或已删除');
        // Keep one thread root so all replies remain discoverable.
        const root = target ? (target.parent || target.id) : null;
        const id = randomUUID();
        db.prepare('INSERT INTO comments(id,song,author,name,content,parent,created,reply_to) VALUES(?,?,?,?,?,?,?,?)').run(id,song,auth.id,auth.name,content,root,now(),target?.id || null);
        return { code: 200, comment: dto(get(id), auth.id) };
      });
    },
    like(id, liked, user) {
      const auth = identity(user); if (typeof liked !== 'boolean') fail(400, '无效点赞状态');
      return transaction(() => {
        throttle(auth.id); const row = get(id); if (!row || row.deleted) fail(404, '评论不存在或已删除');
        if (liked) db.prepare('INSERT OR IGNORE INTO likes VALUES(?,?)').run(row.id, auth.id);
        else db.prepare('DELETE FROM likes WHERE comment=? AND user=?').run(row.id, auth.id);
        return { code: 200, comment: dto(row, auth.id) };
      });
    },
    remove(id, user) {
      const auth = identity(user);
      return transaction(() => {
        throttle(auth.id); const row = get(id); if (!row) fail(404, '评论不存在');
        if (row.author !== auth.id) fail(403, '只能删除本人评论');
        db.prepare("UPDATE comments SET deleted=1,content='' WHERE id=?").run(row.id);
        db.prepare('DELETE FROM likes WHERE comment=?').run(row.id);
        return { code: 200 };
      });
    },
    close() { db.close(); },
  };
}

export function installSiteComments(app, { dataRoot, resolveUser, jsonParser }) {
  const store = createCommentStore(join(dataRoot, 'comments', 'comments.sqlite'));
  const handle = action => (req, res) => {
    res.set('Cache-Control', 'no-store');
    const locale = resolveLocale(req);
    try {
      const body = action(req);
      if (Array.isArray(body?.comments)) {
        for (const comment of body.comments) {
          if (comment?.quotedContent) comment.quotedContent = translateMessage(locale, comment.quotedContent);
        }
      }
      res.json(body);
    }
    catch (error) {
      const status = error.status || 500;
      const message = status >= 500 ? '评论服务暂时不可用' : error.message;
      res.status(status).json({ code: status, message: translateMessage(locale, message) });
    }
  };
  const user = req => resolveUser(/^Bearer\s+\S+$/i.test(req.get('Authorization') || '') ? { headers: req.headers } : req)?.user;
  const authorized = req => {
    // App writes use verified bearer authentication. Session-only cross-site writes are rejected.
    if (!/^Bearer\s+\S+$/i.test(req.get('Authorization') || '')) fail(401, '请先登录本站账号');
    return resolveUser({ headers: req.headers })?.user;
  };
  app.get('/comments', handle(req => store.list(req.query.song, { offset: req.query.offset, limit: req.query.limit, parent: req.query.parent || null, user: user(req) })));
  app.post('/comments', jsonParser, handle(req => store.add(req.body?.song, req.body?.content, req.body?.parentId || null, authorized(req))));
  app.post('/comments/:id/like', jsonParser, handle(req => store.like(req.params.id, req.body?.liked, authorized(req))));
  app.delete('/comments/:id', handle(req => store.remove(req.params.id, authorized(req))));
  return store;
}
