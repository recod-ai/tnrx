#!/usr/bin/env node
'use strict';
// Desenha no terminal os quatro blocos da barra lateral com os dados reais do tnrx-connect
// deste computador (o mesmo model.js que a extensão usa). Para conferir sem abrir o VS Code:
//   node vscode/tools/print-tree.js [--no-cluster]

const model = require('../src/model');
const { resolveConnect, runJson } = require('../src/cli');

function print(nodes, depth = 0) {
    for (const n of nodes) {
        const pad = '  '.repeat(depth);
        const arrow = n.children ? (n.collapsed ? '▸ ' : '▾ ') : '  ';
        console.log(`${pad}${arrow}[${n.icon}] ${n.label}${n.description ? `   ${n.description}` : ''}   {${n.contextValue}}`);
        if (n.children && !n.collapsed) print(n.children, depth + 1);
    }
}

async function section(title, fn) {
    console.log(`\n${title.toUpperCase()}`);
    try {
        const nodes = await fn();
        if (!nodes.length) console.log('  (vazio)');
        print(nodes, 1);
    } catch (e) {
        console.log(`  erro: ${e.code}: ${e.message}`);
    }
}

(async () => {
    const bin = resolveConnect(process.env.TNRX_CONNECT || '');
    console.log(`tnrx-connect: ${bin || 'não encontrado'}`);
    const status = await runJson(bin, ['status', '--json']).catch(() => null);
    await section('Montagens', async () => model.mountsTree(status));
    await section('Configuração Slurm', async () => model.slurmTree(status));
    if (!process.argv.includes('--no-cluster')) {
        await section('Cluster', async () => model.clusterTree(await runJson(bin, ['cluster', '--json']), status));
    }
    await section('Jupyter', async () => model.jupyterTree(await runJson(bin, ['jupyter', 'list', '--json']), Date.now() / 1000));
})();
