'use strict';
// Extensão TNRX: barra lateral com quatro blocos (Montagens, Configuração Slurm, Cluster,
// Jupyter) sobre o `tnrx-connect --json`. Ela nunca autentica: login (senha/2FA), montar e
// o terminal do servidor são sempre num terminal integrado rodando o tnrx-connect.

const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');
const model = require('./model');
const { resolveConnect, runJson, runPlain, shellQuote } = require('./cli');

const VIEWS = { mounts: 'tnrx.mounts', slurm: 'tnrx.slurm', cluster: 'tnrx.cluster', jupyter: 'tnrx.jupyter' };

class Provider {
    // Árvore genérica: os nós já vêm prontos do model.js (com children).
    constructor(build) {
        this.build = build;
        this.emitter = new vscode.EventEmitter();
        this.onDidChangeTreeData = this.emitter.event;
    }

    refresh() {
        this.emitter.fire(undefined);
    }

    getChildren(node) {
        return node ? node.children || [] : this.build();
    }

    getTreeItem(n) {
        const C = vscode.TreeItemCollapsibleState;
        const state = n.children ? (n.collapsed ? C.Collapsed : C.Expanded) : C.None;
        const item = new vscode.TreeItem(n.label, state);
        item.id = n.id;
        item.description = n.description;
        item.tooltip = n.tooltip;
        item.contextValue = n.contextValue;
        if (n.icon) item.iconPath = new vscode.ThemeIcon(n.icon, n.color ? new vscode.ThemeColor(n.color) : undefined);
        if (n.contextValue === 'slurm-key') item.command = { command: 'tnrx.openSlurm', title: 'Abrir', arguments: [n] };
        return item;
    }
}

class Tnrx {
    constructor(context) {
        this.context = context;
        this.status = null;
        this.cluster = null;
        this.jupyter = null;
        this.errors = {};
        this.loading = {};
        this.lastFetch = {};
        this.terminals = new Map();
        this.timers = [];
        this.watchers = [];
        this.output = vscode.window.createOutputChannel('TNRX');
    }

    // --- Configuração ---

    config() {
        const c = vscode.workspace.getConfiguration('tnrx');
        return {
            connectPath: c.get('connectPath', ''),
            refreshInterval: Math.max(5, c.get('refreshInterval', 30)),
            clusterRefreshInterval: Math.max(0, c.get('clusterRefreshInterval', 300)),
        };
    }

    bin() {
        return resolveConnect(this.config().connectPath);
    }

    // --- Dados ---

    async fetch(key, args) {
        // Uma consulta por vez por bloco; erros ficam em this.errors[key] e viram mensagem na vista.
        if (this.loading[key]) return this.loading[key];
        const p = (async () => {
            try {
                const data = await runJson(this.bin(), args);
                this[key] = data;
                this.errors[key] = null;
            } catch (e) {
                this.errors[key] = e;
                this.output.appendLine(`[${new Date().toISOString()}] ${args.join(' ')}: ${e.code}: ${e.message}`);
            } finally {
                this.lastFetch[key] = Date.now();
                this.loading[key] = null;
            }
        })();
        this.loading[key] = p;
        return p;
    }

    async refreshStatus() {
        await this.fetch('status', ['status', '--json']);
        this.providers.mounts.refresh();
        this.providers.slurm.refresh();
        this.updateMessages();
    }

    async refreshCluster(force = false) {
        if (!force && !this.views.cluster.visible) return;
        this.views.cluster.message = this.cluster ? undefined : 'Consultando o cluster…';
        await this.fetch('cluster', ['cluster', '--json']);
        this.providers.cluster.refresh();
        this.updateMessages();
    }

    async refreshJupyter(force = false) {
        if (!force && !this.views.jupyter.visible) return;
        await this.fetch('jupyter', ['jupyter', 'list', '--json']);
        this.providers.jupyter.refresh();
        this.updateMessages();
    }

    refreshAll() {
        return Promise.all([this.refreshStatus(), this.refreshCluster(true), this.refreshJupyter(true)]);
    }

    updateMessages() {
        const notFound = Object.values(this.errors).find((e) => e && e.code === 'not_found');
        if (notFound) {
            for (const v of Object.values(this.views)) v.message = notFound.message;
            return;
        }
        const err = (k) => (this.errors[k] ? `Erro: ${this.errors[k].message}` : undefined);
        const mounted = this.status ? this.status.mounts.filter((m) => m.state === 'mounted') : [];
        this.views.mounts.message = err('status');
        this.views.slurm.message = err('status') || (this.status && !mounted.length ? 'Nenhuma pasta montada.' : undefined);
        this.views.cluster.message = err('cluster')
            || (this.cluster && !this.cluster.hosts.length ? 'Nenhuma pasta montada: monte um projeto para ver o cluster.' : undefined);
        this.views.jupyter.message = err('jupyter')
            || (this.jupyter && !this.jupyter.hosts.some((h) => h.projects.length) ? 'Nenhum projeto conhecido: monte um projeto primeiro.' : undefined);
    }

    // --- Atualização automática ---

    startTimers() {
        for (const t of this.timers) clearInterval(t);
        this.timers = [];
        const { refreshInterval, clusterRefreshInterval } = this.config();
        this.timers.push(setInterval(() => this.refreshStatus(), refreshInterval * 1000));
        this.timers.push(setInterval(() => this.refreshJupyter(), refreshInterval * 1000));
        if (clusterRefreshInterval > 0) this.timers.push(setInterval(() => this.refreshCluster(), clusterRefreshInterval * 1000));
    }

    watchState() {
        // Montar/desmontar (locks), pastas novas e porta fixa (.conf), pontes do Jupyter (bridges)
        // mudam arquivos locais: atualiza na hora. O cache do rclone não é observado.
        const cfg = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'tnrx-connect');
        const data = path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share'), 'tnrx-connect');
        let timer = null;
        const kick = () => {
            clearTimeout(timer);
            timer = setTimeout(() => {
                this.refreshStatus();
                this.refreshJupyter();
            }, 700);
        };
        for (const dir of [cfg, path.join(data, 'locks'), path.join(data, 'bridges')]) {
            try {
                fs.mkdirSync(dir, { recursive: true });
                this.watchers.push(fs.watch(dir, kick));
            } catch (e) {
                this.output.appendLine(`não consegui observar ${dir}: ${e.message}`);
            }
        }
    }

    // --- Terminais ---

    openTerminal(dir, sub, label) {
        // Um terminal integrado por (ação, pasta), reaproveitado enquanto estiver aberto.
        const bin = this.bin();
        if (!bin) {
            vscode.window.showErrorMessage('tnrx-connect não encontrado. Configure tnrx.connectPath.');
            return;
        }
        if (!fs.existsSync(dir)) {
            vscode.window.showErrorMessage(`A pasta ${dir} não existe mais neste computador.`);
            return;
        }
        const key = `${sub}:${dir}`;
        let term = this.terminals.get(key);
        if (!term || term.exitStatus !== undefined) {
            term = vscode.window.createTerminal({ name: `TNRX ${label}: ${path.basename(dir)}`, cwd: dir });
            this.terminals.set(key, term);
        }
        term.show();
        term.sendText(`${shellQuote(bin)} ${sub}`);
    }

    mountForHost(host) {
        const ms = (this.status && this.status.mounts) || [];
        return ms.find((m) => m.host === host && m.state === 'mounted') || ms.find((m) => m.host === host);
    }

    // --- Comandos ---

    registerCommands() {
        const reg = (id, fn) => this.context.subscriptions.push(vscode.commands.registerCommand(id, fn));

        reg('tnrx.refresh', () => this.refreshAll());

        reg('tnrx.mountNew', async () => {
            const pick = await vscode.window.showOpenDialog({
                canSelectFolders: true, canSelectFiles: false, canSelectMany: false,
                openLabel: 'Montar aqui', title: 'Pasta local (vazia) onde montar o projeto do servidor',
            });
            if (pick && pick[0]) this.openTerminal(pick[0].fsPath, 'mount', 'mount');
        });

        reg('tnrx.mount', (n) => n && this.openTerminal(n.mount.local_dir, 'mount', 'mount'));
        reg('tnrx.reconnect', (n) => n && this.openTerminal(n.mount.local_dir, 'mount', 'mount'));
        reg('tnrx.ssh', (n) => n && this.openTerminal(n.mount.local_dir, 'ssh', 'ssh'));

        reg('tnrx.reconnectHost', (n) => {
            const m = n && this.mountForHost(n.host);
            if (m) this.openTerminal(m.local_dir, 'mount', 'mount');
            else vscode.window.showWarningMessage(`Nenhuma pasta configurada para ${n && n.host}.`);
        });

        reg('tnrx.unmount', async (n) => {
            if (!n) return;
            const m = n.mount;
            const ok = await vscode.window.showWarningMessage(
                `Desmontar ${m.name}?`,
                { modal: true, detail: `${m.local_dir}\nTira um último snapshot, desmonta e espera os envios pendentes. Feche antes o que estiver usando a pasta (inclusive este VS Code, se ela estiver aberta aqui).` },
                'Desmontar');
            if (ok !== 'Desmontar') return;
            await this.unmount(m, false);
        });

        reg('tnrx.openFolder', (n) => n && vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(n.mount.local_dir), { forceNewWindow: true }));

        reg('tnrx.openLog', async (n) => {
            if (!n) return;
            try {
                await vscode.window.showTextDocument(vscode.Uri.file(n.mount.log), { preview: true });
            } catch {
                vscode.window.showInformationMessage('Ainda não há log desta pasta.');
            }
        });

        reg('tnrx.openSlurm', async (n) => {
            if (!n || !n.mount || !n.mount.slurm) return;
            const s = n.mount.slurm;
            if (!fs.existsSync(s.file)) {
                const ok = await vscode.window.showInformationMessage(
                    `${n.mount.name} não tem tnrx_slurm.conf (usa os padrões do tnrx). Criar com os valores atuais?`, 'Criar');
                if (ok !== 'Criar') return;
                const body = Object.entries(s.values).map(([k, v]) => `${k}=${v.value}`).join('\n');
                fs.writeFileSync(s.file, `# Recursos dos jobs do tnrx (tnrx slurm / tnrx uvslurm)\n${body}\n`);
            }
            await vscode.window.showTextDocument(vscode.Uri.file(s.file));
        });

        reg('tnrx.jupyterTerminal', (n) => n && n.project.local_dir && this.openTerminal(n.project.local_dir, 'jupyter', 'jupyter'));

        reg('tnrx.copyJupyterUrl', async (n) => {
            if (!n) return;
            await vscode.env.clipboard.writeText(n.server.url);
            vscode.window.showInformationMessage(`URL copiada: ${n.server.url.replace(/token=.*/, 'token=…')}`);
        });
    }

    async unmount(m, force) {
        const bin = this.bin();
        const args = ['umount', ...(force ? ['-f'] : []), m.local_dir];
        const res = await vscode.window.withProgress(
            { location: vscode.ProgressLocation.Notification, title: `Desmontando ${m.name}…` },
            () => runPlain(bin, args));
        this.output.appendLine(`tnrx-connect ${args.join(' ')} -> ${res.code}\n${res.stdout}${res.stderr}`);
        await this.refreshStatus();
        if (res.code === 0) {
            vscode.window.showInformationMessage(`${m.name} desmontada.`);
            return;
        }
        const detail = (res.stderr || res.stdout).trim().split('\n').slice(-6).join('\n');
        const pick = await vscode.window.showErrorMessage(
            `Não consegui desmontar ${m.name}.`, { modal: true, detail },
            ...(force ? [] : ['Forçar (-f)']), 'Ver log');
        if (pick === 'Forçar (-f)') await this.unmount(m, true);
        else if (pick === 'Ver log') this.output.show();
    }

    // --- Ciclo de vida ---

    activate() {
        const s = this;
        this.providers = {
            mounts: new Provider(() => model.mountsTree(s.status)),
            slurm: new Provider(() => model.slurmTree(s.status)),
            cluster: new Provider(() => model.clusterTree(s.cluster, s.status)),
            jupyter: new Provider(() => model.jupyterTree(s.jupyter, Date.now() / 1000)),
        };
        this.views = {};
        for (const [k, id] of Object.entries(VIEWS)) {
            this.views[k] = vscode.window.createTreeView(id, { treeDataProvider: this.providers[k], showCollapseAll: k !== 'mounts' });
            this.context.subscriptions.push(this.views[k]);
        }
        // Cluster e Jupyter consultam o servidor: só quando visíveis (e ao aparecer, se o dado estiver velho).
        const stale = (k, secs) => !this.lastFetch[k] || Date.now() - this.lastFetch[k] > secs * 1000;
        this.context.subscriptions.push(
            this.views.cluster.onDidChangeVisibility((e) => e.visible && stale('cluster', 60) && this.refreshCluster()),
            this.views.jupyter.onDidChangeVisibility((e) => e.visible && stale('jupyter', 15) && this.refreshJupyter()),
            vscode.window.onDidChangeWindowState((e) => e.focused && this.refreshStatus()),
            vscode.window.onDidCloseTerminal((t) => {
                for (const [k, v] of this.terminals) if (v === t) this.terminals.delete(k);
                setTimeout(() => this.refreshAll(), 500);
            }),
            vscode.workspace.onDidChangeConfiguration((e) => e.affectsConfiguration('tnrx') && (this.startTimers(), this.refreshAll())),
            { dispose: () => this.dispose() },
        );
        this.registerCommands();
        this.watchState();
        this.startTimers();
        this.refreshStatus().then(() => {
            this.refreshCluster();
            this.refreshJupyter();
        });
    }

    dispose() {
        for (const t of this.timers) clearInterval(t);
        for (const w of this.watchers) w.close();
        this.output.dispose();
    }
}

function activate(context) {
    const tnrx = new Tnrx(context);
    tnrx.activate();
    return tnrx;
}

function deactivate() {}

module.exports = { activate, deactivate, Tnrx, Provider };
