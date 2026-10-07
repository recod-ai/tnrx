'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { resolveConnect, runJson, shellQuote } = require('../src/cli');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tnrx-cli-'));
test.after(() => fs.rmSync(tmp, { recursive: true, force: true }));

function script(name, body) {
    const p = path.join(tmp, name);
    fs.writeFileSync(p, `#!/bin/bash\n${body}\n`, { mode: 0o755 });
    return p;
}

test('resolveConnect: caminho configurado, PATH e ~/.local/bin', () => {
    const p = script('tnrx-connect', 'exit 0');
    assert.equal(resolveConnect(p), p);
    assert.equal(resolveConnect(path.join(tmp, 'nada')), null);
    assert.equal(resolveConnect('', { PATH: tmp, HOME: '/nonexistent' }), p);
    const home = path.join(tmp, 'home');
    fs.mkdirSync(path.join(home, '.local', 'bin'), { recursive: true });
    const lb = path.join(home, '.local', 'bin', 'tnrx-connect');
    fs.writeFileSync(lb, '#!/bin/bash\n', { mode: 0o755 });
    assert.equal(resolveConnect('', { PATH: '/nonexistent', HOME: home }), lb, 'acha em ~/.local/bin mesmo fora do PATH');
});

test('runJson: sucesso, erro do JSON (code/exitCode), saída inválida, binário ausente', async () => {
    const ok = script('ok', 'echo \'{"v":1,"ok":true,"x":1}\'');
    assert.deepEqual(await runJson(ok, ['status', '--json']), { v: 1, ok: true, x: 1 });

    const err = script('err', 'echo \'{"v":1,"ok":false,"error":{"code":"not_connected","message":"sem conexão"}}\'; echo msg >&2; exit 3');
    await assert.rejects(runJson(err, ['x']), (e) => e.code === 'not_connected' && e.message === 'sem conexão' && e.exitCode === 3);

    const bad = script('bad', 'echo "não é json"; echo problema >&2; exit 1');
    await assert.rejects(runJson(bad, ['x']), (e) => e.code === 'bad_output' && /problema/.test(e.message));

    await assert.rejects(runJson(null, ['x']), (e) => e.code === 'not_found');
});

test('runJson: não espera para sempre, e não deixa o comando ler do stdin', async () => {
    const slow = script('slow', 'sleep 5');
    await assert.rejects(runJson(slow, ['x'], { timeoutMs: 300 }), (e) => e.code === 'timeout');
    const reads = script('reads', 'read -r x; echo "{\\"v\\":1,\\"ok\\":true,\\"got\\":\\"$x\\"}"');
    assert.deepEqual(await runJson(reads, ['x']), { v: 1, ok: true, got: '' });
});

test('shellQuote', () => {
    assert.equal(shellQuote("/a b/it's"), `'/a b/it'\\''s'`);
});
