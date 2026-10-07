'use strict';
// Módulo `vscode` falso, só com o que a extensão usa, pra rodar o extension.js de verdade
// no Node (sem o VS Code). Registra o que a extensão faz: comandos, vistas, terminais,
// mensagens; e deixa o teste escolher as respostas dos diálogos.

const Module = require('module');

function makeFake() {
    const calls = { terminals: [], messages: [], executed: [], clipboard: null, opened: [] };
    const answers = { warning: undefined, error: undefined, info: undefined, openDialog: undefined };
    const commands = new Map();
    const views = new Map();
    const settings = {};
    const listeners = { windowState: [], closeTerminal: [], config: [] };

    class EventEmitter {
        constructor() {
            this.handlers = [];
            this.event = (h) => {
                this.handlers.push(h);
                return { dispose() {} };
            };
        }
        fire(v) {
            for (const h of this.handlers) h(v);
        }
    }

    class TreeItem {
        constructor(label, collapsibleState) {
            this.label = label;
            this.collapsibleState = collapsibleState;
        }
    }

    const vscode = {
        EventEmitter,
        TreeItem,
        TreeItemCollapsibleState: { None: 0, Collapsed: 1, Expanded: 2 },
        ThemeIcon: class { constructor(id, color) { this.id = id; this.color = color; } },
        ThemeColor: class { constructor(id) { this.id = id; } },
        ProgressLocation: { Notification: 15 },
        Uri: { file: (p) => ({ fsPath: p, scheme: 'file' }) },
        window: {
            createTreeView(id, opts) {
                const vis = new EventEmitter();
                const view = { id, provider: opts.treeDataProvider, visible: true, message: undefined, onDidChangeVisibility: vis.event, setVisible(v) { this.visible = v; vis.fire({ visible: v }); }, dispose() {} };
                views.set(id, view);
                return view;
            },
            createOutputChannel: () => ({ lines: [], appendLine(l) { this.lines.push(l); }, show() {}, dispose() {} }),
            createTerminal(opts) {
                const t = { ...opts, sent: [], shown: 0, exitStatus: undefined, show() { this.shown++; }, sendText(s) { this.sent.push(s); } };
                calls.terminals.push(t);
                return t;
            },
            showInformationMessage: async (msg) => { calls.messages.push(['info', msg]); return answers.info; },
            showWarningMessage: async (msg) => { calls.messages.push(['warning', msg]); return answers.warning; },
            showErrorMessage: async (msg, opts) => { calls.messages.push(['error', msg, opts && opts.detail]); return answers.error; },
            showOpenDialog: async () => answers.openDialog,
            showTextDocument: async (uri) => { calls.opened.push(uri.fsPath); },
            withProgress: async (_opts, fn) => fn(),
            onDidChangeWindowState: (h) => { listeners.windowState.push(h); return { dispose() {} }; },
            onDidCloseTerminal: (h) => { listeners.closeTerminal.push(h); return { dispose() {} }; },
        },
        commands: {
            registerCommand(id, fn) {
                commands.set(id, fn);
                return { dispose() { commands.delete(id); } };
            },
            async executeCommand(id, ...args) {
                calls.executed.push([id, ...args]);
                if (commands.has(id)) return commands.get(id)(...args);
                return undefined;
            },
        },
        workspace: {
            getConfiguration: () => ({ get: (k, d) => (k in settings ? settings[k] : d) }),
            onDidChangeConfiguration: (h) => { listeners.config.push(h); return { dispose() {} }; },
        },
        env: { clipboard: { writeText: async (t) => { calls.clipboard = t; } } },
    };

    return { vscode, calls, answers, commands, views, settings, listeners };
}

function install() {
    // Faz `require('vscode')` devolver o falso. Devolve o estado pra inspeção.
    const fake = makeFake();
    const orig = Module._load;
    Module._load = function (request, ...rest) {
        if (request === 'vscode') return fake.vscode;
        return orig.call(this, request, ...rest);
    };
    fake.uninstall = () => { Module._load = orig; };
    return fake;
}

module.exports = { install };
