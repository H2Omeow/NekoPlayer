import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createEventHub,
  createSocialStore,
  renderShareHtml,
} from './social.mjs';

const A = 'user-aaaaaa';
const B = 'user-bbbbbb';
const C = 'user-cccccc';

const PROFILES = {
  [A]: { id: A, username: 'alice', nickname: 'Alice', avatar: 'https://img.test/a.png', bio: 'A' },
  [B]: { id: B, username: 'bob', nickname: 'Bob', avatar: '', bio: 'B' },
  [C]: { id: C, username: 'carol', nickname: 'Carol', avatar: '', bio: 'C' },
};

function setup(options = {}) {
  const calls = [];
  const clock = { value: 1_700_000_000_000 };
  const store = createSocialStore(':memory:', {
    now: () => clock.value,
    publicBaseUrl: 'https://player.test',
    fetchUsers: async (ids) => {
      calls.push([...ids]);
      return ids.map((id) => PROFILES[id]).filter(Boolean);
    },
    ...options,
  });
  return { store, clock, calls };
}

const song = (overrides = {}) => ({
  id: 123,
  nm: '夜曲',
  ar: '周杰伦',
  al: '十一月的萧邦',
  pc: 'https://img.test/cover.jpg',
  source: 'netease',
  ...overrides,
});

test('share stores full data but filters hidden fields on public read', async () => {
  const { store } = setup();
  const share = await store.createShare(A, {
    song: song(),
    platform: '网易云音乐',
    message: '听听这首',
    options: { showSharer: false, cover: false, album: true, lyric: true, progress: true },
    lyricSnippet: '一群嗜血的蚂蚁',
    progress: { positionMs: 42000, durationMs: 240000 },
  });
  assert.match(share.token, /^[A-Za-z0-9_-]{22}$/);
  assert.equal(share.url, `https://player.test/s/${share.token}`);
  assert.equal(share.song.pc, undefined);
  assert.equal(share.song.al, '十一月的萧邦');
  assert.equal(share.sharer, null);
  assert.equal(share.lyricSnippet, '一群嗜血的蚂蚁');
  assert.equal(share.progress.positionMs, 42000);

  const publicShare = await store.getShare(share.token);
  assert.equal(publicShare.token, share.token);
  assert.equal(publicShare.song.pc, undefined);
  assert.equal(publicShare.sharer, null);
  assert.equal(publicShare.owned, false);

  const asOwner = await store.getShare(share.token, { viewerId: A });
  assert.equal(asOwner.owned, true);
  assert.equal(asOwner.sharer, null);
  await assert.rejects(() => store.revokeShare(share.token, B), (error) => error.status === 403);
  await store.revokeShare(share.token, A);
  await assert.rejects(() => store.getShare(share.token), (error) => error.status === 410);
});

test('messages, unread cursor, idempotent retry and participant checks', async () => {
  const { store } = setup();
  const sent = await store.sendMessage(A, { to: B, kind: 'text', body: 'hello', clientId: 'c1' });
  assert.equal(sent.message.text, 'hello');
  assert.equal(sent.message.owned, true);
  const conversation = sent.conversation.id;

  const retry = await store.sendMessage(A, { to: B, kind: 'text', body: 'hello', clientId: 'c1' });
  assert.equal(retry.duplicate, true);
  assert.equal(retry.message.id, sent.message.id);

  const bobView = await store.listConversations(B);
  assert.equal(bobView.length, 1);
  assert.equal(bobView[0].unread, 1);
  assert.equal(bobView[0].peer.nickname, 'Alice');

  const messages = await store.listMessages(B, conversation);
  assert.equal(messages.messages.length, 1);
  assert.equal(messages.messages[0].owned, false);

  await assert.rejects(
    () => store.listMessages(C, conversation),
    (error) => error.status === 403,
  );

  const read = await store.markRead(B, conversation, sent.message.seq);
  assert.equal(read.unread, 0);
  const after = await store.listMessages(B, conversation, { afterSeq: sent.message.seq });
  assert.equal(after.messages.length, 0);

  const deleted = await store.deleteMessage(A, sent.message.id);
  assert.equal(deleted.message.deleted, true);
  const afterDelete = await store.listMessages(B, conversation);
  assert.equal(afterDelete.messages[0].text, '');
  assert.equal(afterDelete.messages[0].deleted, true);
});

test('song messages create a share card and revoke it on withdraw', async () => {
  const { store } = setup();
  const sent = await store.sendMessage(A, {
    to: B,
    kind: 'song',
    body: '分享给你',
    song: song(),
    platform: '网易云音乐',
  });
  assert.equal(sent.message.kind, 'song');
  assert.equal(sent.message.song.nm, '夜曲');
  assert.match(sent.message.shareToken, /^[A-Za-z0-9_-]{22}$/);
  const card = await store.getShare(sent.message.shareToken);
  assert.equal(card.sharer, null);
  assert.equal(card.song.al, '十一月的萧邦');

  await store.deleteMessage(A, sent.message.id);
  await assert.rejects(
    () => store.getShare(sent.message.shareToken),
    (error) => error.status === 410,
  );
});

test('blocks and dm policy are enforced', async () => {
  const { store } = setup();
  await store.setBlock(A, B, true);
  await assert.rejects(
    () => store.sendMessage(A, { to: B, body: 'hi' }),
    (error) => error.status === 403,
  );
  await assert.rejects(
    () => store.sendMessage(B, { to: A, body: 'hi' }),
    (error) => error.status === 403,
  );
  await assert.rejects(
    () => store.follow(B, A, true),
    (error) => error.status === 403,
  );
  await store.setBlock(A, B, false);

  await store.setPreferences(B, { dmPolicy: 'following' });
  await assert.rejects(
    () => store.sendMessage(C, { to: B, body: 'new chat' }),
    (error) => error.status === 403,
  );
  await store.follow(B, C, true);
  const allowed = await store.sendMessage(C, { to: B, body: 'now allowed' });
  assert.equal(allowed.message.text, 'now allowed');
});

test('follow, followers and feed', async () => {
  const { store } = setup();
  const result = await store.follow(A, B, true);
  assert.equal(result.following, true);
  assert.equal(result.followers, 1);
  assert.equal(result.followingCount, 0);
  const profile = await store.getProfile(B, A);
  assert.equal(profile.isFollowing, true);
  assert.equal(profile.followers, 1);

  const followers = await store.listFollows(B, 'followers');
  assert.deepEqual(followers.map((user) => user.id), [A]);

  await store.createShare(B, { song: song(), platform: '酷狗音乐' });
  const feed = await store.feed(A);
  assert.equal(feed.length, 1);
  assert.equal(feed[0].sharer.nickname, 'Bob');

  await assert.rejects(
    () => store.follow(A, A, true),
    (error) => error.status === 400,
  );
});

test('profile cache batches and expires', async () => {
  const { store, clock, calls } = setup();
  await store.getProfile(A, B);
  await store.getProfile(B);
  assert.equal(calls.length, 1);
  clock.value += 6 * 60 * 1000;
  await store.getProfile(A);
  assert.equal(calls.length, 2);
});

test('message rate limit is persisted in sqlite', async () => {
  const { store } = setup();
  for (let index = 0; index < 20; index += 1) {
    await store.sendMessage(A, { to: B, body: `message ${index}`, clientId: `c${index}` });
  }
  await assert.rejects(
    () => store.sendMessage(A, { to: B, body: 'too many', clientId: 'c21' }),
    (error) => error.status === 429,
  );
});

test('event hub sends frames, limits connections and cleans up', () => {
  const hub = createEventHub({ maxPerUser: 1, heartbeatMs: 1000, lifetimeMs: 10000 });
  const writes = [];
  const first = {
    write: (frame) => { writes.push(frame); return true; },
    end: () => { first.ended = true; },
  };
  const second = {
    write: (frame) => { writes.push(frame); return true; },
    end: () => { second.ended = true; },
  };
  const one = hub.subscribe('user-aaaaaa', first);
  const two = hub.subscribe('user-aaaaaa', second);
  assert.equal(first.ended, true);
  assert.equal(hub.connectionCount('user-aaaaaa'), 1);
  assert.equal(hub.publish('user-aaaaaa', 'message', { text: 'hi' }), 1);
  assert.ok(writes.some((frame) => frame.includes('event: message')));
  one.close();
  two.close();
  assert.equal(hub.connectionCount('user-aaaaaa'), 0);
  hub.closeAll();
});

test('share HTML escapes user content and hides options', async () => {
  const { store } = setup();
  const share = await store.createShare(A, {
    song: song({ nm: '</script><script>alert(1)</script>', pc: 'https://img.test/a.jpg' }),
    platform: '网易云音乐',
    message: '<img src=x onerror=alert(1)>',
    options: { showSharer: true },
  });
  const template = '<title><!--SHARE_TITLE--></title><!--SHARE_META--><script id="share-data"><!--SHARE_DATA--></script>';
  const html = renderShareHtml(template, share);
  assert.ok(html.includes('&lt;/script&gt;'));
  assert.ok(html.includes('&lt;img src=x onerror=alert(1)&gt;'));
  assert.ok(html.includes('\\u003c/script\\u003e'));
  assert.ok(!html.includes('</script><script>alert(1)'));
  assert.ok(html.includes('al:android:package'));
  assert.ok(html.includes('og:image'));

  const hidden = await store.createShare(A, {
    song: song(),
    platform: '网易云音乐',
    options: { cover: false, showSharer: false },
  });
  const hiddenHtml = renderShareHtml(template, hidden);
  assert.ok(!hiddenHtml.includes('og:image'));
  assert.ok(!hiddenHtml.includes('Alice'));

  const revoked = renderShareHtml(template, { ...share, revoked: true });
  assert.ok(revoked.includes('noindex'));
  assert.ok(revoked.includes('revoked'));
});
