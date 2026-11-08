import test from 'node:test';
import assert from 'node:assert/strict';

import { parseAcceptLanguage, resolveLocale, t, normalizeLocale } from './server-i18n.mjs';

const req = (url, headers = {}) => ({ url, headers });

test('locale precedence is query, cookie, Accept-Language, then Chinese', () => {
  assert.equal(resolveLocale(req('/s/x?lang=ja', {
    cookie: 'neko_lang=en',
    'accept-language': 'zh-TW',
  })), 'ja');
  assert.equal(resolveLocale(req('/s/x', {
    cookie: 'neko_lang=zh-TW',
    'accept-language': 'en',
  })), 'zh-TW');
  assert.equal(resolveLocale(req('/s/x', { 'accept-language': 'ja,en;q=0.8' })), 'ja');
  assert.equal(resolveLocale(req('/s/x')), 'zh-CN');
});

test('language tags are normalized and unknown values are not reflected', () => {
  assert.equal(normalizeLocale('zh-Hant-HK'), 'zh-TW');
  assert.equal(normalizeLocale('en_US'), 'en');
  assert.equal(normalizeLocale('javascript:alert(1)'), '');
  assert.equal(resolveLocale(req('/s/x?lang=%3Cscript%3E')), 'zh-CN');
});

test('Accept-Language honors quality values and ignores zero', () => {
  assert.equal(parseAcceptLanguage('zh-CN;q=0.1, ja;q=0.9, en;q=0'), 'ja');
  assert.equal(parseAcceptLanguage('*'), '');
});

test('translations replace placeholders and leave unknown sources intact', () => {
  assert.equal(t('en', '社区服务未启用'), 'Community service is not enabled');
  assert.equal(t('zh-TW', '欢迎 {name}', { name: 'Neko' }), '欢迎 Neko');
  assert.equal(t('en', '未收录的消息'), '未收录的消息');
});
