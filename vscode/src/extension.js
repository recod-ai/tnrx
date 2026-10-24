'use strict';
// Extensão tnrx: barra lateral com quatro blocos (Montagens, Configuração do projeto,
// Cluster, Jupyter) sobre o `tnrx-connect --json`, e os Jupyters dos projetos no seletor de
// kernel do VS Code (sem colar URL). Ela nunca autentica: login (senha/2FA), montar e o terminal
// do servidor são sempre num terminal integrado rodando o tnrx-connect.

const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');
const model = require('./model');
const { resolveConnect, runJson, runPlain, runEvents, shellQuote } = require('./cli');

const JUPYTER_EXTENSION = 'ms-toolsai.jupyter';
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
        if (String(n.contextValue).startsWith('slurm-key')) item.command = { command: 'tnrx.editConfigKey', title: 'Mudar valor', arguments: [n] };
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
        this.bridges = new Map(); // id do servidor -> { child, conn }: pontes abertas por esta janela
        this.serversChanged = new vscode.EventEmitter(); // a lista do seletor de kernel mudou
        this.jupyterCollection = null;
        this.timers = [];
        this.watchers = [];
        this.output = vscode.window.createOutputChannel('tnrx');
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
        this.serversChanged.fire();
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
            term = vscode.window.createTerminal({ name: `tnrx ${label}: ${path.basename(dir)}`, cwd: dir });
            this.terminals.set(key, term);
        }
        term.show();
        term.sendText(`${shellQuote(bin)} ${sub}`);
    }

    async cli(args) {
        // Comando do tnrx-connect com --json que muda algo. Devolve o JSON, ou { error }.
        try {
            return await runJson(this.bin(), args);
        } catch (e) {
            this.output.appendLine(`[${new Date().toISOString()}] ${args.join(' ')}: ${e.code}: ${e.message}`);
            return { error: e };
        }
    }

    async setConfig(m, args) {
        // tnrx-connect config --dir <pasta> set|unset ... --json, e atualiza o bloco.
        const r = await this.cli(['config', '--dir', m.local_dir, ...args, '--json']);
        if (r.error) {
            vscode.window.showErrorMessage(`Não consegui mudar o tnrx.conf de ${m.name}: ${r.error.message}`);
            return false;
        }
        await this.refreshStatus();
        return true;
    }

    askValue(m, key, current) {
        return vscode.window.showInputBox({
            title: `${key} de ${m.name}`,
            prompt: model.KEY_HELP[key],
            value: current,
            validateInput: (v) => model.validateConfigValue(key, v.trim()),
        });
    }

    async pickPartition(m, current) {
        // As partições do cluster desse servidor (com as GPUs livres), ou uma digitada.
        const host = this.cluster && this.cluster.hosts.find((h) => h.host === m.host && h.ok);
        if (!host || !host.partitions.length) return this.askValue(m, 'PARTITION', current);
        const items = host.partitions.map((p) => ({
            label: p.name,
            description: [p.name === current ? 'atual' : null, p.default ? 'padrão do Slurm' : null].filter(Boolean).join(' · '),
            detail: p.gpus ? `${p.gpus.free} de ${p.gpus.total} GPUs livres · tempo máximo ${p.time_limit}` : `sem GPUs · tempo máximo ${p.time_limit}`,
            value: p.name,
        }));
        items.push({ label: '$(edit) Outra partição…', other: true });
        const pick = await vscode.window.showQuickPick(items, { title: `PARTITION de ${m.name}`, placeHolder: `Atual: ${current}` });
        if (!pick) return undefined;
        return pick.other ? this.askValue(m, 'PARTITION', current) : pick.value;
    }

    async pickImage(m, value) {
        // Padrão do tnrx (sem IMAGE), o tnrx.def do projeto, ou outra origem digitada.
        const items = [{ label: 'Padrão do tnrx', description: 'sem IMAGE: o tnrx.def do projeto, se houver, senão a imagem padrão', unset: true }];
        if (fs.existsSync(path.join(m.local_dir, 'tnrx.def'))) {
            items.push({ label: 'tnrx.def', description: 'a imagem gerada do tnrx.def deste projeto', value: 'tnrx.def' });
        }
        if (value.from_file && value.value !== 'tnrx.def') items.push({ label: value.value, description: 'atual', value: value.value });
        items.push({ label: '$(edit) Outra origem…', description: 'docker://..., um .def ou o caminho de um .sif', other: true });
        const pick = await vscode.window.showQuickPick(items, { title: `Imagem do container de ${m.name}`, placeHolder: `Atual: ${value.value}` });
        if (!pick) return undefined;
        if (pick.unset) return { unset: true };
        if (pick.other) {
            return vscode.window.showInputBox({
                title: `IMAGE de ${m.name}`,
                prompt: 'Origem da imagem: docker://usuario/imagem:tag, um .def do projeto, ou o caminho de um .sif',
                value: value.from_file ? value.value : '',
                placeHolder: 'docker://nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04',
                validateInput: (v) => model.validateConfigValue('IMAGE', v.trim()),
            });
        }
        return pick.value;
    }

    mountForHost(host) {
        const ms = (this.status && this.status.mounts) || [];
        return ms.find((m) => m.host === host && m.state === 'mounted') || ms.find((m) => m.host === host);
    }

    // --- Jupyter no seletor de kernel ---
    //
    // A extensão Jupyter deixa outra extensão fornecer servidores ("Select Kernel → tnrx"). Cada
    // projeto com Jupyter no ar vira um servidor; ao escolher, a ponte abre (jupyter connect) e o
    // token vai junto, por baixo: nada de colar URL, nem uma entrada nova por servidor, nem senha.

    registerJupyterServers() {
        // Só com a extensão Jupyter já ativa (ou ao abrir um notebook): ativá-la à toa pesa.
        if (this.jupyterCollection) return;
        const ext = vscode.extensions.getExtension(JUPYTER_EXTENSION);
        if (!ext) return;
        const register = (api) => {
            if (this.jupyterCollection || !api || typeof api.createJupyterServerCollection !== 'function') return;
            try {
                const c = api.createJupyterServerCollection('tnrx', 'tnrx (recod jupyter kernels)', {
                    onDidChangeServers: this.serversChanged.event,
                    provideJupyterServers: () => this.provideJupyterServers(),
                    resolveJupyterServer: (server) => this.resolveJupyterServer(server),
                });
                c.commandProvider = {
                    provideCommands: () => [{ label: 'Iniciar um Jupyter num projeto…', description: 'tnrx uvslurm jupyter lab' }],
                    handleCommand: () => this.startJupyterFromPicker(),
                };
                this.jupyterCollection = c;
                this.context.subscriptions.push(c);
            } catch (e) {
                this.output.appendLine(`não consegui registrar os servidores no Jupyter: ${e.message}`);
            }
        };
        if (ext.isActive) register(ext.exports);
        else ext.activate().then(register, (e) => this.output.appendLine(`extensão Jupyter não ativou: ${e.message}`));
    }

    async freshJupyterList(maxAgeSecs = 10) {
        if (!this.jupyter || !this.lastFetch.jupyter || Date.now() - this.lastFetch.jupyter > maxAgeSecs * 1000) {
            await this.refreshJupyter(true);
        }
        return this.jupyter;
    }

    async provideJupyterServers() {
        const list = await this.freshJupyterList();
        return model.jupyterServers(list).map((e) => ({ id: e.id, label: e.label }));
    }

    connection(localPort, token) {
        return { baseUrl: vscode.Uri.parse(`http://127.0.0.1:${localPort}/`), token };
    }

    async resolveJupyterServer(server) {
        const held = this.bridges.get(server.id);
        if (held && held.conn) return { ...server, connectionInformation: held.conn };
        let entry = model.jupyterServers(this.jupyter).find((e) => e.id === server.id);
        if (!entry || !entry.server.bridge_open) {
            entry = model.jupyterServers(await this.freshJupyterList(0)).find((e) => e.id === server.id);
        }
        if (!entry) {
            throw new Error(`O Jupyter de ${server.label.split(' · ')[0]} não está mais no ar (ou o servidor está sem conexão). Inicie outro em Select Kernel → tnrx.`);
        }
        if (entry.server.bridge_open) {
            // Ponte aberta por outro tnrx-connect (um terminal, outra janela): é só usar.
            return { ...server, connectionInformation: this.connection(entry.server.local_port, entry.server.token) };
        }
        const conn = await this.openBridge(entry);
        return { ...server, connectionInformation: conn };
    }

    openBridge(entry) {
        // `jupyter connect` fica rodando enquanto a ponte existir: o processo fica com a janela.
        const { host, project } = entry;
        const args = ['jupyter', 'connect', '--host', host, '--project', project.remote_path, '--json'];
        return vscode.window.withProgress(
            { location: vscode.ProgressLocation.Notification, title: `Abrindo a ponte para o Jupyter de ${project.name}…` },
            () => new Promise((resolve, reject) => {
                let settled = false;
                const held = { child: null, conn: null };
                const { child, done } = runEvents(this.bin(), args, (ev) => {
                    if (ev.event === 'bridge' && !settled) {
                        settled = true;
                        held.conn = this.connection(ev.server.local_port, ev.server.token);
                        this.bridges.set(entry.id, held);
                        this.output.appendLine(`ponte aberta: ${project.name} -> 127.0.0.1:${ev.server.local_port}`);
                        resolve(held.conn);
                    } else if (ev.event === 'error' && !settled) {
                        settled = true;
                        reject(this.bridgeError(host, ev.code, ev.message));
                    } else if (ev.event === 'closed') {
                        this.output.appendLine(`ponte fechada (${project.name}): ${ev.reason}`);
                        if (ev.reason === 'connection_lost') this.offerReconnect(host, `A conexão com ${host} caiu e a ponte do Jupyter de ${project.name} fechou.`);
                    }
                });
                held.child = child;
                done.then(({ code, stderr }) => {
                    if (this.bridges.get(entry.id) === held) this.bridges.delete(entry.id);
                    if (!settled) {
                        settled = true;
                        reject(this.bridgeError(host, 'exit', (stderr || '').trim().split('\n').pop() || `tnrx-connect saiu com ${code}`));
                    }
                    this.refreshJupyter(true);
                }, (e) => {
                    if (!settled) {
                        settled = true;
                        reject(e);
                    }
                });
            }));
    }

    bridgeError(host, code, message) {
        if (code === 'not_connected') {
            this.offerReconnect(host, `Sem conexão com ${host}: faça o login para abrir a ponte do Jupyter.`);
        }
        return new Error(message || 'Não consegui abrir a ponte do Jupyter.');
    }

    async offerReconnect(host, text) {
        const pick = await vscode.window.showWarningMessage(text, 'Reconectar (login no terminal)');
        const m = pick && this.mountForHost(host);
        if (m) this.openTerminal(m.local_dir, 'mount', 'mount');
    }

    async startJupyterFromPicker() {
        // "Iniciar um Jupyter num projeto…" no seletor: escolhe o projeto, roda `jupyter start`
        // (pode esperar na fila do Slurm) e devolve o servidor, que o seletor então conecta.
        const list = await this.freshJupyterList();
        const items = model.jupyterStartable(list);
        if (!items.length) {
            vscode.window.showWarningMessage('Nenhum projeto com conexão: monte um projeto (ou reconecte) na barra lateral do tnrx.');
            return undefined;
        }
        const pick = await vscode.window.showQuickPick(items, { title: 'Iniciar um Jupyter em qual projeto?', placeHolder: 'Usa o tnrx.conf do projeto (partição, GPUs, tempo)' });
        if (!pick) return undefined;
        const { host, project } = pick;
        const args = ['jupyter', 'start', '--host', host, '--project', project.remote_path, '--json'];
        const PHASES = { preparing: 'preparando', queued: 'na fila do Slurm', starting: 'job alocado, Jupyter subindo' };
        const ok = await vscode.window.withProgress(
            { location: vscode.ProgressLocation.Notification, title: `Iniciando um Jupyter em ${project.name}`, cancellable: true },
            (progress, cancel) => new Promise((resolve) => {
                let failure = null;
                const { child, done } = runEvents(this.bin(), args, (ev) => {
                    if (ev.event === 'waiting') progress.report({ message: PHASES[ev.phase] || ev.phase });
                    else if (ev.event === 'error') failure = ev.message || ev.code;
                });
                if (cancel) cancel.onCancellationRequested(() => child && child.kill('SIGTERM'));
                done.then(({ code, stderr }) => {
                    if (code === 0) return resolve(true);
                    if (code !== 130) vscode.window.showErrorMessage(`Não consegui iniciar o Jupyter em ${project.name}.`, { modal: true, detail: failure || stderr });
                    resolve(false);
                }, (e) => {
                    vscode.window.showErrorMessage(e.message);
                    resolve(false);
                });
            }));
        if (!ok) return undefined;
        const entry = model.jupyterServers(await this.freshJupyterList(0)).find((e) => e.id === model.jupyterServerId(host, project.remote_path));
        return entry ? { id: entry.id, label: entry.label } : undefined;
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
            const m = n.mount;
            const s = m.slurm;
            if (!fs.existsSync(s.file)) {
                const ok = await vscode.window.showInformationMessage(
                    `${m.name} não tem tnrx.conf (usa os padrões do tnrx). Criar com os valores atuais?`, 'Criar');
                if (ok !== 'Criar') return;
                // A imagem fica de fora: sem IMAGE, o tnrx continua escolhendo (tnrx.def, senão a padrão).
                const kv = Object.entries(s.values).filter(([k]) => k !== 'IMAGE').map(([k, v]) => `${k}=${v.value}`);
                if (!(await this.setConfig(m, ['set', ...kv]))) return;
            }
            await vscode.window.showTextDocument(vscode.Uri.file(s.file));
        });

        reg('tnrx.editConfigKey', async (n) => {
            if (!n || !n.key) return;
            const m = n.mount;
            const current = n.value.value;
            let v;
            if (n.key === 'PARTITION') v = await this.pickPartition(m, current);
            else if (n.key === 'IMAGE') v = await this.pickImage(m, n.value);
            else v = await this.askValue(m, n.key, current);
            if (v === undefined) return;
            if (v && v.unset) {
                if (n.value.from_file) await this.setConfig(m, ['unset', 'IMAGE']);
                return;
            }
            v = String(v).trim();
            if (v === current && n.value.from_file) return;
            await this.setConfig(m, ['set', `${n.key}=${v}`]);
        });

        reg('tnrx.resetConfigKey', (n) => n && n.key && this.setConfig(n.mount, ['unset', n.key]));

        reg('tnrx.renameMount', async (n) => {
            if (!n) return;
            const m = n.mount;
            const name = await vscode.window.showInputBox({
                title: `Renomear ${m.name}`,
                prompt: `Nome mostrado nas listas (${m.local_dir}). Vazio volta ao nome da pasta.`,
                value: m.name,
                validateInput: (v) => (v.length > 60 ? 'Máximo de 60 caracteres.' : null),
            });
            if (name === undefined || name === m.name) return;
            const r = await this.cli(['rename', '--id', m.id, name.trim(), '--json']);
            if (r.error) vscode.window.showErrorMessage(`Não consegui renomear ${m.name}: ${r.error.message}`);
            await Promise.all([this.refreshStatus(), this.refreshJupyter(true)]);
        });

        reg('tnrx.forgetMount', async (n) => {
            if (!n) return;
            const m = n.mount;
            const ok = await vscode.window.showWarningMessage(
                `Apagar a montagem ${m.name}?`,
                { modal: true, detail: `${m.local_dir}  →  ${m.host}:${m.remote_path}\n\nApaga deste computador a configuração, o cache e os snapshots (o histórico para desfazer edições). Os arquivos no servidor e a pasta local não são tocados.` },
                'Apagar');
            if (ok !== 'Apagar') return;
            await this.forget(m, false);
        });

        reg('tnrx.jupyterTerminal', (n) => n && n.project.local_dir && this.openTerminal(n.project.local_dir, 'jupyter', 'jupyter'));

        reg('tnrx.copyJupyterUrl', async (n) => {
            if (!n) return;
            await vscode.env.clipboard.writeText(n.server.url);
            vscode.window.showInformationMessage(`URL copiada: ${n.server.url.replace(/token=.*/, 'token=…')}`);
        });
    }

    async forget(m, force) {
        const r = await this.cli(['forget', '--id', m.id, ...(force ? ['--force'] : []), '--json']);
        if (!r.error) {
            await this.refreshStatus();
            vscode.window.showInformationMessage(`Montagem ${m.name} apagada.`);
            return;
        }
        if (r.error.code === 'pending_writes') {
            const pick = await vscode.window.showWarningMessage(
                `${m.name} tem arquivos salvos que ainda não chegaram ao servidor.`,
                { modal: true, detail: 'Monte a pasta de novo para enviá-los e depois apague. Apagar agora perde essas mudanças.' },
                'Montar para enviar', 'Apagar mesmo assim');
            if (pick === 'Montar para enviar') this.openTerminal(m.local_dir, 'mount', 'mount');
            else if (pick === 'Apagar mesmo assim') await this.forget(m, true);
            return;
        }
        vscode.window.showErrorMessage(`Não consegui apagar ${m.name}: ${r.error.message}`);
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
            vscode.workspace.onDidOpenNotebookDocument(() => this.registerJupyterServers()),
            { dispose: () => this.dispose() },
        );
        this.registerCommands();
        const jupyterExt = vscode.extensions.getExtension(JUPYTER_EXTENSION);
        if ((jupyterExt && jupyterExt.isActive) || vscode.workspace.notebookDocuments.length) this.registerJupyterServers();
        this.watchState();
        this.startTimers();
        this.refreshStatus().then(() => {
            this.refreshCluster();
            this.refreshJupyter();
        });
    }

    dispose() {
        for (const b of this.bridges.values()) b.child && b.child.kill('SIGTERM'); // fecha as pontes desta janela
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
