'use strict';
// Chama o `tnrx-connect` (no laptop). Toda a lógica fica nele; aqui só se roda e lê o JSON.

const { execFile } = require('child_process');
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

function shellQuote(s) {
    return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

module.exports = { resolveConnect, runJson, runPlain, shellQuote, CliError };
