'use strict';
// Saídas de exemplo do `tnrx-connect --json`, no formato de docs/tnrx-connect-json.md.

const slurm = (file, exists = true) => ({
    file,
    exists,
    values: {
        PARTITION: { value: 'a100', from_file: true },
        GPUS: { value: '2', from_file: true },
        CPUS: { value: '2', from_file: false },
        MEM: { value: '4G', from_file: false },
        TIME: { value: '04:00:00', from_file: true },
    },
});

const status = {
    v: 1,
    ok: true,
    mounts: [
        { id: 'recod-headnode_velho', name: 'velho', local_dir: '/tmp/tnrx-x/velho', host: 'recod-headnode', remote_path: '/home/u/velho', state: 'unmounted', connected: true, rclone_pid: null, since: null, last_used: 50, jupyter_port: null, log: '/tmp/tnrx-x/velho.log', slurm: null },
        { id: 'recod_caiu', name: 'caiu', local_dir: '/tmp/tnrx-x/caiu', host: 'recod', remote_path: '/home/u/caiu', state: 'mounted', connected: false, rclone_pid: 11, since: 1759590000, last_used: 90, jupyter_port: null, log: '/tmp/tnrx-x/caiu.log', slurm: null },
        { id: 'recod-headnode_proj', name: 'proj', local_dir: '/tmp/tnrx-x/proj', host: 'recod-headnode', remote_path: '/home/u/proj', state: 'mounted', connected: true, rclone_pid: 10, since: 1759590000, last_used: 100, jupyter_port: 18342, log: '/tmp/tnrx-x/proj.log', slurm: slurm('/tmp/tnrx-x/proj/tnrx_slurm.conf') },
        { id: 'recod-headnode_parado', name: 'parado', local_dir: '/tmp/tnrx-x/parado', host: 'recod-headnode', remote_path: '/home/u/parado', state: 'stale', connected: true, rclone_pid: null, since: null, last_used: 80, jupyter_port: null, log: '/tmp/tnrx-x/parado.log', slurm: null },
    ],
    hosts: [{ host: 'recod-headnode', connected: true }, { host: 'recod', connected: false }],
};

const cluster = {
    v: 1,
    ok: true,
    hosts: [
        {
            host: 'recod-headnode', connected: true, ok: true,
            partitions: [
                { name: 'l40s', default: true, available: 'up', time_limit: '7-00:00:00', nodes: { allocated: 2, idle: 1, other: 1, total: 4 }, gres: 'gpu:l40s:2', gpus: { total: 8, used: 3, unavailable: 2, free: 3 } },
                { name: 'a100', default: false, available: 'up', time_limit: '2-00:00:00', nodes: { allocated: 0, idle: 0, other: 2, total: 2 }, gres: 'gpu:a100:4', gpus: { total: 8, used: 0, unavailable: 8, free: 0 } },
            ],
            jobs: [
                { id: '95272', partition: 'l40s', name: 'jupyter', state: 'RUNNING', elapsed: '3:01', time_limit: '2:00:00', reason: 'dl-05', work_dir: '/home/u/proj' },
                { id: '95300', partition: 'a100', name: 'train', state: 'PENDING', elapsed: '0:00', time_limit: '1-00:00:00', reason: '(Resources)', work_dir: '/data/outro' },
            ],
        },
        { host: 'recod', connected: false, ok: false, error: { code: 'not_connected', message: 'Sem conexão com recod.' }, partitions: [], jobs: [] },
    ],
};

const jupyter = {
    v: 1,
    ok: true,
    hosts: [
        {
            host: 'recod-headnode', connected: true,
            projects: [
                { name: 'outro', remote_path: '/home/u/outro', local_dir: null, servers: [] },
                {
                    name: 'proj', remote_path: '/home/u/proj', local_dir: '/tmp/tnrx-x/proj',
                    servers: [
                        { node: 'dl-05', port: 8888, job: '104472', started: 1759599820, token: 'aa', token_fixed: true, bridge_open: true, local_port: 18342, url: 'http://127.0.0.1:18342/lab?token=aa' },
                        { node: 'dl-02', port: 8889, job: '104400', started: 1759590000, token: 'bb', token_fixed: false, bridge_open: false, local_port: 18342, url: 'http://127.0.0.1:18342/lab?token=bb' },
                    ],
                },
            ],
        },
        { host: 'recod', connected: false, projects: [{ name: 'remoto', remote_path: '/r', local_dir: null, servers: [] }] },
    ],
};

module.exports = { status, cluster, jupyter };
