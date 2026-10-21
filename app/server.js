const express = require('express');
const { Pool } = require('pg');
const client = require('prom-client');

const app = express();
app.disable('x-powered-by');
app.use(express.json());
const pool = new Pool({
  host: process.env.DB_HOST, database: process.env.DB_NAME,
  user: process.env.DB_USER, password: process.env.DB_PASSWORD,
});

client.collectDefaultMetrics();
const dur = new client.Histogram({
  name: 'http_request_duration_seconds', help: 'HTTP duration',
  labelNames: ['method', 'route', 'status'],
});

app.use((req, res, next) => {
  const t = process.hrtime.bigint();
  res.on('finish', () => {
    const s = Number(process.hrtime.bigint() - t) / 1e9;
    dur.labels(req.method, req.route ? req.route.path : 'other', res.statusCode).observe(s);
    console.log(JSON.stringify({
      time: new Date().toISOString(), method: req.method, path: req.originalUrl,
      status: res.statusCode, ms: Math.round(s * 1000), ip: req.headers['x-real-ip'] || req.ip,
    }));
  });
  next();
});

const h = fn => (req, res, next) => fn(req, res).catch(next);
const q = (sql, p) => pool.query(sql, p).then(r => r.rows);

app.get('/health', (_q, r) => r.json({ status: 'ok' }));
app.get('/metrics', h(async (_q, r) => {
  r.set('Content-Type', client.register.contentType);
  r.end(await client.register.metrics());
}));

app.get('/api/departments', h(async (_q, r) => r.json(await q('SELECT * FROM departments ORDER BY id'))));
app.post('/api/departments', h(async (req, r) =>
  r.status(201).json((await q('INSERT INTO departments(name) VALUES($1) RETURNING *', [req.body.name]))[0])));

app.get('/api/employees', h(async (_q, r) => r.json(await q(
  `SELECT e.id,e.full_name,e.email,e.position,d.name AS department
   FROM employees e LEFT JOIN departments d ON d.id=e.department_id ORDER BY e.id`))));
app.post('/api/employees', h(async (req, r) => {
  const { full_name, email, position, department_id } = req.body;
  if (!full_name || !full_name.trim() || !email || !email.trim()) return r.status(400).json({ error: 'full_name and email are required' });
  r.status(201).json((await q(
    'INSERT INTO employees(full_name,email,position,department_id) VALUES($1,$2,$3,$4) RETURNING *',
    [full_name, email, position, department_id]))[0]);
}));
app.put('/api/employees/:id', h(async (req, r) => {
  const { full_name, email, position, department_id } = req.body;
  if (!full_name || !full_name.trim() || !email || !email.trim()) return r.status(400).json({ error: 'full_name and email are required' });
  r.json((await q(
    'UPDATE employees SET full_name=$1,email=$2,position=$3,department_id=$4 WHERE id=$5 RETURNING *',
    [full_name, email, position, department_id, req.params.id]))[0]);
}));
app.delete('/api/employees/:id', h(async (req, r) => {
  await q('DELETE FROM employees WHERE id=$1', [req.params.id]);
  r.json({ ok: true });
}));

app.get('/api/attendance', h(async (_q, r) => r.json(await q(
  `SELECT a.id,e.full_name,a.check_in,a.check_out FROM attendance a
   JOIN employees e ON e.id=a.employee_id ORDER BY a.check_in DESC LIMIT 100`))));
app.post('/api/attendance/check-in', h(async (req, r) =>
  r.status(201).json((await q('INSERT INTO attendance(employee_id) VALUES($1) RETURNING *', [req.body.employee_id]))[0])));
app.post('/api/attendance/check-out', h(async (req, r) => r.json((await q(
  `UPDATE attendance SET check_out=NOW() WHERE id=(
     SELECT id FROM attendance WHERE employee_id=$1 AND check_out IS NULL
     ORDER BY check_in DESC LIMIT 1) RETURNING *`, [req.body.employee_id]))[0] || {})));

app.use(express.static('public'));
app.use((err, _req, res, _next) => {
  console.error(JSON.stringify({ level: 'error', msg: err.message }));
  res.status(500).json({ error: 'Internal error' });
});
app.listen(3000, () => console.log(JSON.stringify({ msg: 'HRM listening on 3000' })));
