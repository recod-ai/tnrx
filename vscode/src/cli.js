'use strict';
// Chama o `tnrx-connect` (no laptop). Toda a lógica fica nele; aqui só se roda e lê o JSON.

const { execFile, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

function isExecutable(p) {
    try {
        fs.accessSync(p, fs.constants.X_OK);
        return fs.statSync(p).isFile();
    } catch {
        return false;
    }
}

function resolveConnect(setting, env = process.env) {
    // Caminho do tnrx-connect: o configurado, ou procura no PATH e em ~/.local/bin (o VS Code
    // aberto pelo menu do sistema nem sempre herda o PATH do shell).
    const name = setting && setting.trim() ? setting.trim() : 'tnrx-connect';
    if (name.includes('/')) {
        const p = name.startsWith('~/') ? path.join(os.homedir(), name.slice(2)) : name;
        return isExecutable(p) ? p : null;
    }
    const dirs = (env.PATH || '').split(path.delimiter).filter(Boolean);
    dirs.push(path.join(env.HOME || os.homedir(), '.local', 'bin'));
    for (const d of dirs) {
        const p = path.join(d, name);
        if (isExecutable(p)) return p;
    }
    return null;
}

class CliError extends Error {
    constructor(code, message, exitCode) {
        super(message);
        this.code = code;
        this.exitCode = exitCode;
    }
}

function runJson(bin, args, { timeoutMs = 60000, env = process.env } = {}) {
    // Roda `tnrx-connect <args>` (que deve incluir --json) e devolve o objeto. Falha com
    // CliError: code = o error.code do JSON, ou 'not_found'/'timeout'/'bad_output'.
    return new Promise((resolve, reject) => {
        if (!bin) {
            reject(new CliError('not_found', 'tnrx-connect não encontrado. Configure tnrx.connectPath.'));
            return;
        }
        const child = execFile(bin, args, { timeout: timeoutMs, env, maxBuffer: 16 * 1024 * 1024 }, (err, stdout, stderr) => {
            const text = String(stdout || '').trim();
            let data = null;
            try {
                data = text ? JSON.parse(text.split('\n').pop()) : null;
            } catch {
                data = null;
            }
            if (data && data.ok === false && data.error) {
                reject(new CliError(data.error.code, data.error.message, err ? err.code : 0));
            } else if (data && data.ok) {
                resolve(data);
            } else if (err && err.killed) {
                reject(new CliError('timeout', `tnrx-connect ${args[0]} demorou demais.`));
            } else {
                const msg = String(stderr || '').trim() || (err ? err.message : 'saída inesperada');
                reject(new CliError('bad_output', `tnrx-connect ${args.join(' ')}: ${msg}`, err ? err.code : 0));
            }
        });
        child.stdin && child.stdin.end();
    });
}

function runPlain(bin, args, { timeoutMs = 180000, env = process.env } = {}) {
    // Comandos sem JSON (umount): resolve com { code, stdout, stderr }.
    return new Promise((resolve) => {
        const child = execFile(bin, args, { timeout: timeoutMs, env }, (err, stdout, stderr) => {
            resolve({ code: err ? (typeof err.code === 'number' ? err.code : 1) : 0, stdout: String(stdout), stderr: String(stderr) });
        });
        child.stdin && child.stdin.end();
    });
}

function runEvents(bin, args, onEvent, { env = process.env } = {}) {
    // Comandos de eventos (`jupyter start`/`jupyter connect` com --json): chama onEvent com cada
    // objeto, uma linha por vez, e devolve { child, done }. done resolve com o código de saída;
    // para parar, mande SIGTERM ao child (o tnrx-connect cancela/fecha e sai com 130).
    if (!bin) {
        const err = new CliError('not_found', 'tnrx-connect não encontrado. Configure tnrx.connectPath.');
        return { child: null, done: Promise.reject(err) };
    }
    const child = spawn(bin, args, { env, stdio: ['ignore', 'pipe', 'pipe'] });
    let buf = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => {
        buf += chunk;
        let nl;
        while ((nl = buf.indexOf('\n')) >= 0) {
            const line = buf.slice(0, nl).trim();
            buf = buf.slice(nl + 1);
            if (!line.startsWith('{')) continue;
            try {
                onEvent(JSON.parse(line));
            } catch {
                // linha que não é JSON (não deveria haver com --json): ignora
            }
        }
    });
    child.stderr.on('data', (chunk) => {
        stderr = (stderr + chunk).slice(-4000);
    });
    const done = new Promise((resolve) => {
        child.on('error', (e) => resolve({ code: 127, stderr: e.message }));
        child.on('close', (code, signal) => resolve({ code: code === null ? (signal ? 130 : 1) : code, stderr }));
    });
    return { child, done };
}

function shellQuote(s) {
    return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

module.exports = { resolveConnect, runJson, runPlain, runEvents, shellQuote, CliError };
