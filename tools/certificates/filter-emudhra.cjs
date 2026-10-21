// Interim eMudhra root distrust; https://emudhra.we-have-a-problem.com/roots.json
// Preserve each application's own OS and runtime roots, removing exact fingerprints only.
const fs = require('node:fs');
const { X509Certificate } = require('node:crypto');
const blocked = new Set([
  '7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D',
  'F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5',
  'D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4',
  '86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B',
]);
function filter(text) {
  return text.replace(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g, pem => {
    const certificate = new X509Certificate(pem);
    return blocked.has(certificate.fingerprint256.replace(/:/g, '')) ? '' : pem;
  });
}
const output = process.argv[2] || '/patched-trust/system';
fs.mkdirSync(output, { recursive: true });
let bundle = '';
for (const name of (fs.existsSync('/etc/ssl/certs') ? fs.readdirSync('/etc/ssl/certs') : [])) {
  const path = '/etc/ssl/certs/' + name;
  if (fs.statSync(path).isDirectory()) throw new Error('Unexpected CA directory: ' + path);
  const text = fs.readFileSync(path, 'utf8');
  const filtered = filter(text);
  if (text.includes('-----BEGIN CERTIFICATE-----') && !filtered.includes('-----BEGIN CERTIFICATE-----')) continue;
  fs.writeFileSync(output + '/' + name, filtered, { mode: 0o644 });
  if (name === 'ca-certificates.crt') bundle = filtered;
}
// OpenSSL mode replaces the bundled CA set; retain every unaffected runtime root.
bundle += '\n' + filter(require('node:tls').rootCertificates.join('\n')) + '\n';
if (!bundle.includes('-----BEGIN CERTIFICATE-----')) throw new Error('Empty trust bundle');
fs.writeFileSync(output + '/ca-certificates.crt', bundle, { mode: 0o644 });
console.log('Prepared filtered OS and runtime CA roots');
