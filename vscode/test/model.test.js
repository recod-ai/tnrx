'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const model = require('../src/model');
const fx = require('./fixtures');

test('montagens: ordem (montadas primeiro), estado e botões por contexto', () => {
    const items = model.mountsTree(fx.status);
    assert.deepEqual(items.map((i) => [i.label, i.contextValue]), [
        ['proj', 'mount-ok'],
        ['caiu', 'mount-disconnected'],
        ['parado', 'mount-stale'],
        ['velho', 'mount-unmounted'],
    ]);
    assert.equal(items[0].description, 'recod-headnode:/home/u/proj');
    assert.equal(items[0].icon, 'pass-filled');
    assert.match(items[1].tooltip, /Reconectar/);
    assert.match(items[2].tooltip, /rclone parou/);
});

test('montagens: sem dados, vazio', () => {
    assert.deepEqual(model.mountsTree(null), []);
    assert.deepEqual(model.mountsTree({ v: 1, ok: true, mounts: [], hosts: [] }), []);
});

test('slurm: só pastas montadas; padrões marcados; sem conexão avisa', () => {
    const items = model.slurmTree(fx.status);
    assert.deepEqual(items.map((i) => i.label), ['proj', 'caiu']);
    const keys = items[0].children.map((c) => [c.label, c.description]);
    assert.deepEqual(keys, [
        ['PARTITION', 'a100'],
        ['GPUS', '2'],
        ['CPUS', '2 (padrão)'],
        ['MEM', '4G (padrão)'],
        ['TIME', '04:00:00'],
    ]);
    assert.equal(items[0].children[0].contextValue, 'slurm-key');
    assert.equal(items[1].children.length, 1);
    assert.match(items[1].children[0].label, /Sem conexão/);
});

test('slurm: projeto sem tnrx_slurm.conf diz que usa os padrões', () => {
    const st = JSON.parse(JSON.stringify(fx.status));
    st.mounts.find((m) => m.name === 'proj').slurm.exists = false;
    assert.match(model.slurmTree(st)[0].description, /sem tnrx_slurm.conf/);
});

test('cluster: GPUs livres por partição, meus jobs com o projeto, host sem conexão', () => {
    const items = model.clusterTree(fx.cluster, fx.status);
    assert.equal(items.length, 2);
    const h = items[0];
    assert.equal(h.label, 'recod-headnode');
    assert.equal(h.description, '3 GPUs livres');
    assert.deepEqual(h.children.slice(0, 2).map((p) => [p.label, p.description]), [
        ['l40s (padrão)', 'GPUs 3/8 livres · nós 1/4 livres · 7-00:00:00'],
        ['a100', 'GPUs 0/8 livres · nós 0/2 livres · 2-00:00:00'],
    ]);
    const jobs = h.children[2];
    assert.equal(jobs.label, 'Meus jobs');
    assert.equal(jobs.description, '2');
    assert.equal(jobs.children[0].label, '95272  jupyter');
    assert.match(jobs.children[0].description, /^rodando · l40s · 3:01 · dl-05 · proj$/);
    assert.match(jobs.children[1].description, /^na fila/);
    assert.equal(items[1].contextValue, 'cluster-host-disconnected');
    assert.equal(items[1].host, 'recod');
});

test('cluster: job em subpasta do projeto é atribuído ao projeto mais específico', () => {
    const mounts = [{ name: 'a', remote_path: '/x' }, { name: 'b', remote_path: '/x/b' }];
    assert.equal(model.projectOfJob({ work_dir: '/x/b/sub' }, mounts).name, 'b');
    assert.equal(model.projectOfJob({ work_dir: '/x' }, mounts).name, 'a');
    assert.equal(model.projectOfJob({ work_dir: '/xy' }, mounts), null);
});

test('cluster: sem jobs mostra "nenhum" e recolhe', () => {
    const c = JSON.parse(JSON.stringify(fx.cluster));
    c.hosts[0].jobs = [];
    const jobs = model.clusterTree(c, fx.status)[0].children[2];
    assert.equal(jobs.collapsed, true);
    assert.match(jobs.children[0].label, /Nenhum job/);
});

test('jupyter: por projeto, com ponte aberta marcada; projetos sem Jupyter e sem conexão', () => {
    const items = model.jupyterTree(fx.jupyter, 1759600000);
    assert.deepEqual(items.map((i) => [i.label, i.description]), [
        ['proj', 'recod-headnode · 2 no ar'],
        ['outro', 'recod-headnode'],
        ['remoto', 'recod · sem conexão'],
    ]);
    const s = items[0].children;
    assert.equal(s[0].label, 'dl-05:8888');
    assert.equal(s[0].description, 'job 104472 · há 3 min · ponte aberta');
    assert.equal(s[0].contextValue, 'jupyter-server-bridged');
    assert.equal(s[1].contextValue, 'jupyter-server');
    assert.match(s[1].tooltip, /vale só para este Jupyter/);
    assert.match(items[1].children[0].label, /Nenhum Jupyter/);
    assert.match(items[2].children[0].label, /Sem conexão/);
    assert.equal(items[2].contextValue, 'jupyter-project-off');
    assert.equal(items[1].contextValue, 'jupyter-project-nolocal');
});

test('fmtAge', () => {
    assert.equal(model.fmtAge(100, 150), '50s');
    assert.equal(model.fmtAge(0, 600), '10 min');
    assert.equal(model.fmtAge(0, 7200 * 3), '6 h');
    assert.equal(model.fmtAge(200, 100), '0s');
});
