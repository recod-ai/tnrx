'use strict';
// Transforma o JSON do `tnrx-connect --json` (docs/tnrx-connect-json.md) nos itens dos
// quatro blocos da barra lateral. Funções puras, sem depender do VS Code: cada item é um
// objeto simples ({ id, label, description, tooltip, icon, color, contextValue, children,
// collapsed }) que o extension.js converte em TreeItem. Assim dá pra testar com `node --test`.

function fmtAge(started, now) {
    let s = Math.max(0, Math.floor(now - started));
    if (s < 120) return `${s}s`;
    if (s < 7200) return `${Math.floor(s / 60)} min`;
    return `${Math.floor(s / 3600)} h`;
}

function fmtDate(epoch) {
    if (!epoch) return '';
    const d = new Date(epoch * 1000);
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

function info(id, label, icon = 'info') {
    return { id, label, icon, contextValue: 'info' };
}

// --- Bloco 1: Montagens ---

const STATE_ORDER = { mounted: 0, mounting: 1, stale: 2, unmounted: 3 };

function mountStatus(m) {
    // Rótulo, ícone, cor e contexto (que decide os botões da linha) de uma pasta.
    if (m.state === 'mounted' && m.connected) {
        return { text: 'montada', icon: 'pass-filled', color: 'testing.iconPassed', ctx: 'mount-ok' };
    }
    if (m.state === 'mounted') {
        return { text: 'montada, sem conexão', icon: 'warning', color: 'list.warningForeground', ctx: 'mount-disconnected' };
    }
    if (m.state === 'mounting') return { text: 'montando…', icon: 'sync~spin', ctx: 'mount-mounting' };
    if (m.state === 'stale') {
        return { text: 'montagem caiu (rclone parado)', icon: 'error', color: 'list.errorForeground', ctx: 'mount-stale' };
    }
    return { text: 'desmontada', icon: 'circle-outline', ctx: 'mount-unmounted' };
}

function sortMounts(mounts) {
    return [...mounts].sort((a, b) =>
        (STATE_ORDER[a.state] ?? 9) - (STATE_ORDER[b.state] ?? 9) || (b.last_used || 0) - (a.last_used || 0));
}

function mountsTree(status) {
    if (!status || !status.mounts) return [];
    return sortMounts(status.mounts).map((m) => {
        const st = mountStatus(m);
        const tooltip = [
            `${m.name} — ${st.text}`,
            `Pasta local: ${m.local_dir}`,
            `Servidor: ${m.host}:${m.remote_path}`,
            m.since ? `Montada desde: ${fmtDate(m.since)}` : null,
            m.state === 'mounted' && !m.connected ? 'A conexão caiu: use Reconectar (pede senha/2FA no terminal).' : null,
            m.state === 'stale' ? 'O rclone parou: use Montar para recuperar.' : null,
        ].filter(Boolean).join('\n');
        return {
            id: `mount:${m.id}`,
            label: m.name,
            // Contexto: mount-<estado>; o menu usa isso para Renomear (sempre) e Apagar (só desmontada).
            description: `${m.host}:${m.remote_path}`,
            tooltip,
            icon: st.icon,
            color: st.color,
            contextValue: st.ctx,
            mount: m,
        };
    });
}

// --- Bloco 2: Configuração do projeto (tnrx.conf de cada pasta montada) ---

const SLURM_ORDER = ['PARTITION', 'GPUS', 'CPUS', 'MEM', 'TIME', 'IMAGE'];

const KEY_HELP = {
    PARTITION: 'Partição do Slurm',
    GPUS: 'GPUs por job',
    CPUS: 'CPUs por job',
    MEM: 'Memória por job',
    TIME: 'Tempo máximo do job',
    IMAGE: 'Imagem do container',
};

function validateConfigValue(key, value) {
    // O mesmo que o `tnrx-connect config` confere (ele é quem decide; isto só avisa antes).
    const v = String(value ?? '');
    const rules = {
        PARTITION: [/^[A-Za-z0-9_.-]+$/, "Use só letras, números, '.', '_' e '-'."],
        GPUS: [/^[0-9]+$/, 'Use um número inteiro.'],
        CPUS: [/^[0-9]+$/, 'Use um número inteiro.'],
        MEM: [/^[0-9]+[KMGTkmgt]?$/, 'Use um número com unidade, ex.: 16G ou 500M.'],
        TIME: [/^([0-9]+-)?[0-9]+(:[0-9]{2}){0,2}$/, 'Use o formato do Slurm, ex.: 02:00:00 ou 1-00:00:00.'],
        IMAGE: [/^\S+$/, 'Use uma origem (docker://...), um .def ou o caminho de um .sif, sem espaços.'],
    };
    const r = rules[key];
    if (!r) return `Chave desconhecida: ${key}`;
    return r[0].test(v) ? null : r[1];
}

function confName(m) {
    // Nome do arquivo de configuração (tnrx.conf, ou o tnrx_slurm.conf antigo).
    return m.slurm && m.slurm.file ? m.slurm.file.split('/').pop() : 'tnrx.conf';
}

function slurmTree(status) {
    if (!status || !status.mounts) return [];
    return sortMounts(status.mounts.filter((m) => m.state === 'mounted')).map((m) => {
        const file = confName(m);
        let children;
        if (!m.slurm) {
            children = [info(`slurm:${m.id}:off`, 'Sem conexão: reconecte para ler o tnrx.conf', 'warning')];
        } else {
            children = SLURM_ORDER.filter((k) => m.slurm.values[k]).map((k) => {
                const v = m.slurm.values[k];
                return {
                    id: `slurm:${m.id}:${k}`,
                    label: k,
                    description: v.from_file ? v.value : `${v.value} (padrão)`,
                    tooltip: `${KEY_HELP[k]}: ${v.value}\n${v.from_file ? `Definido no ${file}.` : `Padrão do tnrx (não está no ${file}).`}\nClique para mudar.`,
                    icon: v.from_file ? 'symbol-field' : 'symbol-constant',
                    // O contexto decide se a linha oferece "voltar ao padrão".
                    contextValue: v.from_file ? 'slurm-key-file' : 'slurm-key-default',
                    mount: m,
                    key: k,
                    value: v,
                };
            });
        }
        return {
            id: `slurm:${m.id}`,
            label: m.name,
            description: m.slurm && !m.slurm.exists ? `${m.host} · sem tnrx.conf (padrões)`
                : file !== 'tnrx.conf' && m.slurm ? `${m.host} · ${file} (nome antigo)` : m.host,
            tooltip: m.slurm ? m.slurm.file : m.local_dir,
            icon: 'settings-gear',
            contextValue: 'slurm-mount',
            mount: m,
            children,
        };
    });
}

// --- Bloco 3: Cluster (sinfo + meus jobs, por host montado) ---

function projectOfJob(job, mounts) {
    // Projeto (pasta montada) em que o job foi submetido, pela pasta remota.
    const wd = job.work_dir || '';
    let best = null;
    for (const m of mounts || []) {
        const rp = m.remote_path;
        if (rp && (wd === rp || wd.startsWith(rp.endsWith('/') ? rp : `${rp}/`))) {
            if (!best || rp.length > best.remote_path.length) best = m;
        }
    }
    return best;
}

function clusterTree(cluster, status) {
    if (!cluster || !cluster.hosts) return [];
    const mounts = (status && status.mounts) || [];
    return cluster.hosts.map((h) => {
        if (!h.ok) {
            return {
                id: `cluster:${h.host}`,
                label: h.host,
                description: h.error ? h.error.message : 'erro',
                tooltip: h.error ? `${h.error.code}: ${h.error.message}` : '',
                icon: 'warning',
                color: 'list.warningForeground',
                contextValue: h.connected ? 'cluster-host-error' : 'cluster-host-disconnected',
                host: h.host,
                children: [],
            };
        }
        const free = h.partitions.reduce((s, p) => s + (p.gpus ? p.gpus.free : 0), 0);
        const parts = h.partitions.map((p) => {
            const g = p.gpus;
            const desc = [
                g ? `GPUs ${g.free}/${g.total} livres` : 'sem GPUs',
                `nós ${p.nodes.idle}/${p.nodes.total} livres`,
                p.time_limit,
                p.available !== 'up' ? p.available : null,
            ].filter(Boolean).join(' · ');
            return {
                id: `cluster:${h.host}:p:${p.name}`,
                label: p.default ? `${p.name} (padrão)` : p.name,
                description: desc,
                tooltip: [
                    `Partição ${p.name}${p.default ? ' (padrão do Slurm)' : ''}: ${p.available}`,
                    g ? `GPUs: ${g.free} livres de ${g.total} (${g.used} em uso, ${g.unavailable} em nós fora do ar)` : null,
                    `Nós: ${p.nodes.idle} livres, ${p.nodes.allocated} cheios, ${p.nodes.other} parciais/fora do ar, ${p.nodes.total} no total`,
                    p.gres ? `GRES: ${p.gres}` : null,
                    `Tempo máximo: ${p.time_limit}`,
                ].filter(Boolean).join('\n'),
                icon: g && g.free > 0 ? 'server' : 'server-process',
                color: g && g.free === 0 ? 'disabledForeground' : undefined,
                contextValue: 'cluster-partition',
            };
        });
        const jobs = h.jobs.map((j) => {
            const proj = projectOfJob(j, mounts.filter((m) => m.host === h.host));
            return {
                id: `cluster:${h.host}:j:${j.id}`,
                label: `${j.id}  ${j.name}`,
                description: [j.state === 'RUNNING' ? 'rodando' : j.state === 'PENDING' ? 'na fila' : j.state,
                    j.partition, j.elapsed, j.reason, proj ? proj.name : null].filter(Boolean).join(' · '),
                tooltip: [`Job ${j.id} (${j.name})`, `Estado: ${j.state}`, `Partição: ${j.partition}`,
                    `Tempo: ${j.elapsed} de ${j.time_limit}`, `Nó/motivo: ${j.reason}`, `Pasta: ${j.work_dir}`].join('\n'),
                icon: j.state === 'RUNNING' ? 'play-circle' : j.state === 'PENDING' ? 'watch' : 'circle-outline',
                contextValue: 'cluster-job',
                host: h.host,
                job: j,
            };
        });
        const jobsNode = {
            id: `cluster:${h.host}:jobs`,
            label: 'Meus jobs',
            description: String(jobs.length),
            icon: 'list-unordered',
            contextValue: 'cluster-jobs',
            children: jobs.length ? jobs : [info(`cluster:${h.host}:jobs:none`, 'Nenhum job seu no Slurm', 'check')],
            collapsed: jobs.length === 0,
        };
        return {
            id: `cluster:${h.host}`,
            label: h.host,
            description: `${free} GPUs livres`,
            tooltip: `${h.host}: ${h.partitions.length} partições, ${free} GPUs livres, ${jobs.length} jobs seus`,
            icon: 'cloud',
            contextValue: 'cluster-host',
            host: h.host,
            children: [...parts, jobsNode],
        };
    });
}

// --- Bloco 4: Jupyter (por projeto) ---

function jupyterTree(list, now) {
    if (!list || !list.hosts) return [];
    const out = [];
    for (const h of list.hosts) {
        for (const p of h.projects) {
            const servers = (p.servers || []).map((s) => ({
                id: `jupyter:${h.host}:${p.remote_path}:${s.job}`,
                label: `${s.node}:${s.port}`,
                description: [`job ${s.job}`, `há ${fmtAge(s.started, now)}`, s.bridge_open ? 'ponte aberta' : null]
                    .filter(Boolean).join(' · '),
                tooltip: [
                    `Jupyter em ${s.node}:${s.port} (job ${s.job})`,
                    s.bridge_open ? `Ponte aberta: ${s.url}` : `URL local (ao conectar): http://127.0.0.1:${s.local_port}/lab`,
                    s.token_fixed ? 'Senha fixa do projeto: a URL é sempre a mesma.' : 'Não usa a senha fixa do projeto: a URL vale só para este Jupyter.',
                ].join('\n'),
                icon: s.bridge_open ? 'link' : 'notebook',
                color: s.bridge_open ? 'testing.iconPassed' : undefined,
                contextValue: s.bridge_open ? 'jupyter-server-bridged' : 'jupyter-server',
                host: h.host,
                project: p,
                server: s,
            }));
            let children = servers;
            if (!h.connected) children = [info(`jupyter:${h.host}:${p.remote_path}:off`, 'Sem conexão com o servidor', 'warning')];
            else if (!servers.length) children = [info(`jupyter:${h.host}:${p.remote_path}:none`, 'Nenhum Jupyter no ar', 'circle-slash')];
            out.push({
                id: `jupyter:${h.host}:${p.remote_path}`,
                label: p.name,
                description: h.connected ? `${h.host}${servers.length ? ` · ${servers.length} no ar` : ''}` : `${h.host} · sem conexão`,
                tooltip: `${h.host}:${p.remote_path}${p.local_dir ? `\nPasta local: ${p.local_dir}` : ''}`,
                icon: 'project',
                // O botão de terminal só para projeto com pasta local e host conectado.
                contextValue: !h.connected ? 'jupyter-project-off' : p.local_dir ? 'jupyter-project' : 'jupyter-project-nolocal',
                host: h.host,
                project: p,
                children,
                collapsed: !servers.length,
            });
        }
    }
    // Projetos com Jupyter no ar primeiro; depois por nome.
    return out.sort((a, b) => (b.children[0].server ? 1 : 0) - (a.children[0].server ? 1 : 0) || a.label.localeCompare(b.label));
}

// --- Jupyter no seletor de kernel do VS Code ---

function jupyterServers(list) {
    // Um servidor por projeto com Jupyter no ar: o mais recente (o mesmo que o `jupyter connect`
    // sem --job abre). O id é host+projeto, não o job: a porta local e o token são fixos por
    // projeto, então o notebook continua ligado ao "mesmo" servidor quando o job muda.
    const out = [];
    if (!list || !list.hosts) return out;
    for (const h of list.hosts) {
        if (!h.connected) continue;
        for (const p of h.projects) {
            const servers = [...(p.servers || [])].sort((a, b) => (b.started || 0) - (a.started || 0));
            if (!servers.length) continue;
            const s = servers[0];
            out.push({
                id: jupyterServerId(h.host, p.remote_path),
                label: `${p.name} · ${s.node} (job ${s.job})`,
                host: h.host,
                project: p,
                server: s,
            });
        }
    }
    return out.sort((a, b) => a.label.localeCompare(b.label));
}

function jupyterServerId(host, remotePath) {
    return `${host}|${remotePath}`;
}

function jupyterStartable(list) {
    // Projetos onde dá para iniciar um Jupyter: host conectado (o login é no terminal, não aqui).
    const out = [];
    if (!list || !list.hosts) return out;
    for (const h of list.hosts) {
        if (!h.connected) continue;
        for (const p of h.projects) {
            const running = (p.servers || []).length;
            out.push({ host: h.host, project: p, label: p.name, description: `${h.host}${running ? ` · ${running} no ar` : ''}`, detail: p.remote_path });
        }
    }
    return out.sort((a, b) => a.label.localeCompare(b.label));
}

module.exports = { fmtAge, fmtDate, mountsTree, slurmTree, clusterTree, jupyterTree, jupyterServers, jupyterServerId, jupyterStartable, projectOfJob, mountStatus, SLURM_ORDER, KEY_HELP, validateConfigValue };
