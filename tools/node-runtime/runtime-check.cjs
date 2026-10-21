'use strict';
const tls = require('node:tls');
const dns = require('node:dns');
const zlib = require('node:zlib');
const results = [];
const check = (name, ok, detail) => results.push({ name, ok, ...(detail ? { detail } : {}) });
const minimum = { 22: [22, 23, 4], 24: [24, 22, 1], 26: [26, 12, 1] };
const version = process.versions.node.split('.').map(Number);
const target = minimum[version[0]];
check('fixed supported Node release', !process.versions.bun && !!target && version.reduce((r, n, i) => r || Math.sign(n - target[i]), 0) >= 0);
for (const [host, normalized] of [
  ['0127.0.0.1', '87.0.0.1'], ['0177.0.0.1', '127.0.0.1'],
  ['0x7f.0.0.1', '127.0.0.1'], ['2130706433', '127.0.0.1'],
  ['127.1', '127.0.0.1'], ['１２７.0.0.1', '127.0.0.1'],
  ['127。0.0.1', '127.0.0.1'],
]) {
  const error = tls.checkServerIdentity(host, { subject: {}, subjectaltname: `DNS:${normalized}` });
  check('TLS rejects noncanonical host ' + host, error?.code === 'ERR_TLS_CERT_ALTNAME_INVALID');
}
check('TLS accepts normal DNS SAN', tls.checkServerIdentity('safe.invalid', { subject: {}, subjectaltname: 'DNS:safe.invalid' }) === undefined);
check('TLS accepts IPv4 SAN', tls.checkServerIdentity('127.0.0.1', { subject: {}, subjectaltname: 'IP Address:127.0.0.1' }) === undefined);
check('TLS accepts IPv6 SAN', tls.checkServerIdentity('::1', { subject: {}, subjectaltname: 'IP Address:0:0:0:0:0:0:0:1' }) === undefined);
const resolver = new dns.Resolver({ timeout: 100, tries: 1 });
resolver.setServers(['127.0.0.1:9']);
for (const method of ['resolve4', 'resolve6', 'resolveTxt']) {
  let code;
  try { resolver[method]('example.invalid\0.trusted.invalid', () => {}); }
  catch (error) { code = error.code; }
  check('DNS rejects NUL in ' + method, code === 'ERR_INVALID_ARG_VALUE');
}
resolver.cancel();
check('Brotli fixed error constant exposed', typeof zlib.constants.BROTLI_DECODER_ERROR_FORMAT_BLOCK_SWITCH === 'number');
const original = Buffer.from('normal Brotli round trip');
check('Brotli normal round trip', zlib.brotliDecompressSync(zlib.brotliCompressSync(original)).equals(original));
console.log(JSON.stringify({ version: process.version, bun: process.versions.bun, versions: process.versions, passed: results.filter(r => r.ok).length, total: results.length, results }));
process.exitCode = results.every(r => r.ok) ? 0 : 1;
