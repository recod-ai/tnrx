'use strict';
// Carrega o extension.js de verdade com um `vscode` falso e um `tnrx-connect` falso
// (script que devolve os JSON de fixtures.js e registra as chamadas).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { install } = require('./fake-vscode');
const fx = require('./fixtures');

const fake = install();
const ext = require('../src/extension');
const pkg = require('../package.json');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tnrx-vscode-'));
process.env.XDG_CONFIG_HOME = path.join(tmp, 'config');
process.env.XDG_DATA_HOME = path.join(tmp, 'data');
const bin = path.join(tmp, 'tnrx-connect');
const callsLog = path.join(tmp, 'calls.log');

function writeFakeCli() {
    // status/cluster/jupyter list devolvem as fixtures; umount sai com $tmp/umount_rc.
    fs.writeFileSync(path.join(tmp, 'status.json'), JSON.stringify(fx.status));
    fs.writeFileSync(path.join(tmp, 'cluster.json'), JSON.stringify(fx.cluster));
    fs.writeFileSync(path.join(tmp, 'jupyter.json'), JSON.stringify(fx.jupyter));
    fs.writeFileSync(bin, `#!/bin/bash
echo "$*" >> '${callsLog}'
case "$1" in
  status) cat '${tmp}/status.json' ;;
  cluster) cat '${tmp}/cluster.json' ;;
  jupyter) cat '${tmp}/jupyter.json' ;;
  umount) rc=$(cat '${tmp}/umount_rc' 2>/dev/null || echo 0); [ "$rc" != 0 ] && echo "❌ Ainda em uso." >&2; exit "$rc" ;;
esac
`, { mode: 0o755 });
}

writeFakeCli();
for (const d of ['proj', 'caiu', 'parado', 'velho']) fs.mkdirSync(path.join('/tmp/tnrx-x', d), { recursive: true });
fake.settings.connectPath = bin;
fake.settings.refreshInterval = 3600;
fake.settings.clusterRefreshInterval = 0;

const context = { subscriptions: [] };
let tnrx;

const roots = (id) => fake.views.get(id).provider.getChildren();
const item = (id, label) => roots(id).find((n) => n.label === label);
const calls = () => (fs.existsSync(callsLog) ? fs.readFileSync(callsLog, 'utf8').split('\n').filter(Boolean) : []);

test.before(async () => {
    tnrx = ext.activate(context);
    await tnrx.refreshAll();
});

test.after(() => {
    for (const s of context.subscriptions) s.dispose();
    fake.uninstall();
    fs.rmSync(tmp, { recursive: true, force: true });
});

test('ativa e cria as quatro vistas declaradas no package.json', () => {
    const declared = pkg.contributes.views.tnrx.map((v) => v.id).sort();
    assert.deepEqual([...fake.views.keys()].sort(), declared);
});

test('todo comando do package.json foi registrado, e todo registrado está declarado', () => {
    const declared = pkg.contributes.commands.map((c) => c.command).sort();
    assert.deepEqual([...fake.commands.keys()].sort(), declared);
});

test('todo comando citado nos menus está declarado; todo contexto dos menus existe no modelo', () => {
    const declared = new Set(pkg.contributes.commands.map((c) => c.command));
    const menus = Object.values(pkg.contributes.menus).flat();
    for (const m of menus) assert.ok(declared.has(m.command), `menu cita comando inexistente: ${m.command}`);
    // Os contextos (viewItem) que os menus esperam aparecem nas árvores das fixtures.
    const contexts = new Set();
    const walk = (ns) => ns.forEach((n) => { contexts.add(n.contextValue); if (n.children) walk(n.children); });
    for (const id of fake.views.keys()) walk(roots(id));
    for (const m of menus) {
        const exact = /viewItem == ([\w-]+)/.exec(m.when || '');
        if (exact) assert.ok(contexts.has(exact[1]), `nenhum item com contexto ${exact[1]}`);
    }
});

test('consulta o tnrx-connect só com --json', () => {
    const c = calls();
    assert.ok(c.includes('status --json'));
    assert.ok(c.includes('cluster --json'));
    assert.ok(c.includes('jupyter list --json'));
});

test('as quatro vistas mostram os dados', () => {
    assert.deepEqual(roots('tnrx.mounts').map((n) => n.label), ['proj', 'caiu', 'parado', 'velho']);
    assert.deepEqual(roots('tnrx.slurm').map((n) => n.label), ['proj', 'caiu']);
    assert.deepEqual(roots('tnrx.cluster').map((n) => n.label), ['recod-headnode', 'recod']);
    assert.equal(roots('tnrx.jupyter')[0].label, 'proj');
    const ti = fake.views.get('tnrx.mounts').provider.getTreeItem(item('tnrx.mounts', 'proj'));
    assert.equal(ti.contextValue, 'mount-ok');
    assert.equal(ti.iconPath.id, 'pass-filled');
    const key = roots('tnrx.slurm')[0].children[0];
    assert.equal(fake.views.get('tnrx.slurm').provider.getTreeItem(key).command.command, 'tnrx.openSlurm');
});

test('terminal do servidor: tnrx-connect ssh na pasta; reaproveita o terminal aberto', async () => {
    const n = item('tnrx.mounts', 'proj');
    await fake.vscode.commands.executeCommand('tnrx.ssh', n);
    const t = fake.calls.terminals.at(-1);
    assert.equal(t.cwd, '/tmp/tnrx-x/proj');
    assert.deepEqual(t.sent, [`'${bin}' ssh`]);
    const count = fake.calls.terminals.length;
    await fake.vscode.commands.executeCommand('tnrx.ssh', n);
    assert.equal(fake.calls.terminals.length, count, 'não abriu outro terminal');
    assert.equal(t.sent.length, 2);
});

test('reconectar e montar abrem o terminal com tnrx-connect mount (login fica no terminal)', async () => {
    await fake.vscode.commands.executeCommand('tnrx.reconnect', item('tnrx.mounts', 'caiu'));
    assert.deepEqual(fake.calls.terminals.at(-1).sent, [`'${bin}' mount`]);
    assert.equal(fake.calls.terminals.at(-1).cwd, '/tmp/tnrx-x/caiu');
    await fake.vscode.commands.executeCommand('tnrx.reconnectHost', roots('tnrx.cluster')[1]);
    assert.equal(fake.calls.terminals.at(-1).cwd, '/tmp/tnrx-x/caiu', 'host sem conexão: usa uma pasta desse host');
    fake.answers.openDialog = [{ fsPath: '/tmp/tnrx-x/velho' }];
    await fake.vscode.commands.executeCommand('tnrx.mountNew');
    assert.equal(fake.calls.terminals.at(-1).cwd, '/tmp/tnrx-x/velho');
});

test('desmontar: pede confirmação, roda umount; se falhar, oferece -f', async () => {
    const n = item('tnrx.mounts', 'proj');
    fake.answers.warning = undefined;
    await fake.vscode.commands.executeCommand('tnrx.unmount', n);
    assert.ok(!calls().some((c) => c.startsWith('umount')), 'cancelado: nada roda');

    fake.answers.warning = 'Desmontar';
    await fake.vscode.commands.executeCommand('tnrx.unmount', n);
    assert.ok(calls().includes('umount /tmp/tnrx-x/proj'));

    fs.writeFileSync(path.join(tmp, 'umount_rc'), '1');
    fake.answers.error = 'Forçar (-f)';
    let first = true;
    const orig = fake.vscode.window.showErrorMessage;
    fake.vscode.window.showErrorMessage = async (...a) => { const r = first ? 'Forçar (-f)' : undefined; first = false; await orig(...a); return r; };
    await fake.vscode.commands.executeCommand('tnrx.unmount', n);
    fake.vscode.window.showErrorMessage = orig;
    assert.ok(calls().includes('umount -f /tmp/tnrx-x/proj'), 'tentou com -f');
    const err = fake.calls.messages.filter((m) => m[0] === 'error').at(-1);
    assert.match(err[2], /Ainda em uso/, 'mostra o motivo');
    fs.rmSync(path.join(tmp, 'umount_rc'));
});

test('slurm: editar cria o tnrx_slurm.conf com os valores atuais se não existir', async () => {
    const st = JSON.parse(JSON.stringify(fx.status));
    const m = st.mounts.find((x) => x.name === 'proj');
    const file = path.join(tmp, 'tnrx_slurm.conf');
    m.slurm.file = file;
    fake.answers.info = 'Criar';
    await fake.vscode.commands.executeCommand('tnrx.openSlurm', { mount: m });
    assert.match(fs.readFileSync(file, 'utf8'), /PARTITION=a100\nGPUS=2\nCPUS=2\nMEM=4G\nTIME=04:00:00/);
    assert.equal(fake.calls.opened.at(-1), file);
});

test('jupyter: copiar URL de uma ponte aberta; terminal do jupyter na pasta do projeto', async () => {
    const p = roots('tnrx.jupyter')[0];
    await fake.vscode.commands.executeCommand('tnrx.copyJupyterUrl', p.children[0]);
    assert.equal(fake.calls.clipboard, 'http://127.0.0.1:18342/lab?token=aa');
    assert.ok(!fake.calls.messages.at(-1)[1].includes('token=aa'), 'a mensagem não mostra a senha');
    await fake.vscode.commands.executeCommand('tnrx.jupyterTerminal', p);
    assert.deepEqual(fake.calls.terminals.at(-1).sent, [`'${bin}' jupyter`]);
});

test('cluster e jupyter só consultam o servidor com a vista visível', async () => {
    fs.writeFileSync(callsLog, '');
    fake.views.get('tnrx.cluster').visible = false;
    fake.views.get('tnrx.jupyter').visible = false;
    await tnrx.refreshCluster();
    await tnrx.refreshJupyter();
    assert.deepEqual(calls(), []);
    fake.views.get('tnrx.cluster').setVisible(true);
    await new Promise((r) => setTimeout(r, 300));
    assert.ok(!calls().includes('cluster --json'), 'dado recente: não consulta de novo ao aparecer');
    fake.views.get('tnrx.cluster').visible = true;
    fake.views.get('tnrx.jupyter').visible = true;
});

test('tnrx-connect inexistente: mensagem nas vistas', async () => {
    fake.settings.connectPath = path.join(tmp, 'nao-existe');
    await tnrx.refreshStatus();
    assert.match(fake.views.get('tnrx.mounts').message, /tnrx-connect não encontrado/);
    fake.settings.connectPath = bin;
    await tnrx.refreshAll();
    assert.equal(fake.views.get('tnrx.mounts').message, undefined);
});

test('erro do tnrx-connect vira mensagem na vista, sem derrubar as outras', async () => {
    fs.writeFileSync(path.join(tmp, 'cluster.json'), '{"v":1,"ok":false,"error":{"code":"x","message":"falhou feio"}}');
    await tnrx.refreshCluster(true);
    assert.match(fake.views.get('tnrx.cluster').message, /falhou feio/);
    assert.equal(fake.views.get('tnrx.mounts').message, undefined);
    writeFakeCli();
    await tnrx.refreshCluster(true);
    assert.equal(fake.views.get('tnrx.cluster').message, undefined);
});
