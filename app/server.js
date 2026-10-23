'use strict';
const express = require('express');
const crypto = require('crypto');
const { Pool } = require('pg');
const client = require('prom-client');

const SECRET = process.env.SESSION_SECRET || '';
const TTL = 8 * 3600; // 8 gio
const log = o => console.log(JSON.stringify({ time: new Date().toISOString(), ...o }));
if (SECRET.length < 16) {
  log({ level: 'fatal', msg: 'SESSION_SECRET phai co it nhat 16 ky tu' });
  process.exit(1);
}

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1);
app.use(express.json({ limit: '100kb' }));

const pool = new Pool({
  host: process.env.DB_HOST, database: process.env.DB_NAME,
  user: process.env.DB_USER, password: process.env.DB_PASSWORD, max: 10,
  options: '-c timezone=Asia/Ho_Chi_Minh',
});
const q = (sql, p) => pool.query(sql, p).then(r => r.rows);
const h = fn => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// ---------- Metrics + log moi request (JSON) ----------
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
    log({
      method: req.method, path: req.originalUrl, status: res.statusCode, ms: Math.round(s * 1000),
      ip: req.headers['x-real-ip'] || req.ip, user: res.locals.user ? res.locals.user.username : undefined,
    });
  });
  next();
});

// ---------- Mat khau + phien dang nhap (chi dung module crypto co san) ----------
const hashPw = pw => {
  const salt = crypto.randomBytes(16).toString('hex');
  return salt + ':' + crypto.scryptSync(pw, salt, 64).toString('hex');
};
const checkPw = (pw, stored) => {
  const [salt, hex] = String(stored).split(':');
  if (!salt || !hex) return false;
  const a = Buffer.from(hex, 'hex');
  const b = crypto.scryptSync(pw, salt, 64);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
};
const sign = p => crypto.createHmac('sha256', SECRET).update(p).digest('base64url');
const makeToken = uid => {
  const p = Buffer.from(JSON.stringify({ uid, exp: Math.floor(Date.now() / 1000) + TTL })).toString('base64url');
  return p + '.' + sign(p);
};
const readToken = t => {
  if (!t) return null;
  const [p, s] = t.split('.');
  if (!p || !s) return null;
  const e = sign(p);
  if (s.length !== e.length || !crypto.timingSafeEqual(Buffer.from(s), Buffer.from(e))) return null;
  try {
    const d = JSON.parse(Buffer.from(p, 'base64url').toString());
    return d.exp > Date.now() / 1000 ? d : null;
  } catch { return null; }
};
const cookies = req => Object.fromEntries(
  (req.headers.cookie || '').split(';').map(s => s.trim().split('=')).filter(a => a[0])
    .map(([k, ...v]) => [k, decodeURIComponent(v.join('='))]));

// ---------- Tien ich ----------
const str = (v, max = 255) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const dateOk = s => /^\d{4}-\d{2}-\d{2}$/.test(s || '') && !isNaN(Date.parse(s));
const emailOk = s => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
const idOk = v => /^\d{1,9}$/.test(String(v));
const audit = (req, event, extra) => log({ event, by: req.user && req.user.username, ...extra });

const auth = h(async (req, res, next) => {
  const d = readToken(cookies(req).hrm_session);
  if (!d) return res.status(401).json({ error: 'Chưa đăng nhập' });
  const u = (await q(
    `SELECT u.id, u.username, u.role, u.employee_id, e.full_name, e.employee_code
       FROM users u LEFT JOIN employees e ON e.id = u.employee_id WHERE u.id = $1`, [d.uid]))[0];
  if (!u) return res.status(401).json({ error: 'Chưa đăng nhập' });
  req.user = u; res.locals.user = u;
  next();
});
const admin = (req, res, next) =>
  req.user.role === 'admin' ? next() : res.status(403).json({ error: 'Bạn không có quyền thực hiện thao tác này' });

// Chan CSRF: moi thao tac ghi phai la JSON (form tu trang khac khong gui duoc) + cookie SameSite=Strict
app.use('/api', (req, res, next) => {
  if (req.method !== 'GET' && !(req.headers['content-type'] || '').startsWith('application/json'))
    return res.status(415).json({ error: 'Yêu cầu không hợp lệ' });
  next();
});

app.get('/health', (_req, res) => res.json({ status: 'ok' }));
app.get('/metrics', h(async (_req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
}));

// ---------- Dang nhap ----------
const fails = new Map(); // ip -> { n, until }
app.post('/api/auth/login', h(async (req, res) => {
  const ip = req.headers['x-real-ip'] || req.ip;
  const f = fails.get(ip);
  if (f && f.n >= 5 && f.until > Date.now()) {
    log({ event: 'login_blocked', ip });
    return res.status(429).json({ error: 'Thử sai quá nhiều lần, vui lòng đợi vài phút' });
  }
  const { username, password } = req.body || {};
  const ok = typeof username === 'string' && typeof password === 'string';
  const u = ok ? (await q('SELECT * FROM users WHERE username = $1', [username.trim().toLowerCase()]))[0] : null;
  if (!u || !checkPw(password, u.password_hash)) {
    const n = (f && f.until > Date.now() ? f.n : 0) + 1;
    fails.set(ip, { n, until: Date.now() + 5 * 60 * 1000 });
    log({ event: 'login_failed', username: str(username, 50), ip });
    return res.status(401).json({ error: 'Sai tài khoản hoặc mật khẩu' });
  }
  fails.delete(ip);
  res.cookie('hrm_session', makeToken(u.id), {
    httpOnly: true, sameSite: 'strict', secure: true, maxAge: TTL * 1000, path: '/',
  });
  log({ event: 'login_success', username: u.username, role: u.role, ip });
  res.json({ ok: true });
}));
app.post('/api/auth/logout', (_req, res) => { res.clearCookie('hrm_session', { path: '/' }); res.json({ ok: true }); });
app.get('/api/auth/me', auth, (req, res) => res.json(req.user));

// ---------- Tong quan ----------
app.get('/api/dashboard', auth, h(async (req, res) => {
  if (req.user.role === 'admin') {
    const s = (await q(`SELECT
      (SELECT count(*) FROM employees WHERE status = 'active')::int AS employees,
      (SELECT count(*) FROM departments)::int AS departments,
      (SELECT count(DISTINCT employee_id) FROM attendance WHERE check_in::date = CURRENT_DATE)::int AS present_today,
      (SELECT count(*) FROM leave_requests WHERE status = 'pending')::int AS pending_leaves,
      (SELECT count(*) FROM leave_requests WHERE status = 'approved' AND CURRENT_DATE BETWEEN start_date AND end_date)::int AS on_leave_today`))[0];
    const byDept = await q(`SELECT d.name, count(e.id)::int AS total FROM departments d
      LEFT JOIN employees e ON e.department_id = d.id AND e.status = 'active'
      GROUP BY d.id ORDER BY total DESC, d.name`);
    const week = await q(`SELECT to_char(g::date, 'DD/MM') AS day, count(DISTINCT a.employee_id)::int AS total
      FROM generate_series(CURRENT_DATE - 6, CURRENT_DATE, interval '1 day') g
      LEFT JOIN attendance a ON a.check_in::date = g::date GROUP BY g ORDER BY g`);
    const recent = await q(`SELECT e.employee_code, e.full_name, e.position, d.name AS department,
      to_char(e.hired_date, 'YYYY-MM-DD') AS hired_date
      FROM employees e LEFT JOIN departments d ON d.id = e.department_id
      ORDER BY e.hired_date DESC, e.id DESC LIMIT 5`);
    return res.json({ role: 'admin', stats: s, byDept, week, recent });
  }
  const eid = req.user.employee_id;
  const s = eid ? (await q(`SELECT
    (SELECT count(DISTINCT check_in::date) FROM attendance WHERE employee_id = $1
       AND date_trunc('month', check_in) = date_trunc('month', now()))::int AS days_this_month,
    (SELECT COALESCE(sum(end_date - start_date + 1), 0) FROM leave_requests WHERE employee_id = $1
       AND status = 'approved' AND extract(year FROM start_date) = extract(year FROM CURRENT_DATE))::int AS leave_days,
    (SELECT count(*) FROM leave_requests WHERE employee_id = $1 AND status = 'pending')::int AS pending_leaves`, [eid]))[0]
    : { days_this_month: 0, leave_days: 0, pending_leaves: 0 };
  res.json({ role: 'employee', stats: s });
}));

// ---------- Phong ban ----------
app.get('/api/departments', auth, h(async (_req, res) => res.json(await q(
  `SELECT d.id, d.name, d.description, count(e.id)::int AS employee_count FROM departments d
   LEFT JOIN employees e ON e.department_id = d.id AND e.status = 'active' GROUP BY d.id ORDER BY d.name`))));
const deptInput = b => ({ name: str(b.name, 100), description: str(b.description, 500) });
app.post('/api/departments', auth, admin, h(async (req, res) => {
  const d = deptInput(req.body || {});
  if (!d.name) return res.status(400).json({ error: 'Tên phòng ban là bắt buộc' });
  const r = (await q('INSERT INTO departments (name, description) VALUES ($1, $2) RETURNING id', [d.name, d.description || null]))[0];
  audit(req, 'department_created', { id: r.id, name: d.name });
  res.status(201).json(r);
}));
app.put('/api/departments/:id', auth, admin, h(async (req, res) => {
  if (!idOk(req.params.id)) return res.status(400).json({ error: 'Mã không hợp lệ' });
  const d = deptInput(req.body || {});
  if (!d.name) return res.status(400).json({ error: 'Tên phòng ban là bắt buộc' });
  const r = await q('UPDATE departments SET name = $1, description = $2 WHERE id = $3 RETURNING id', [d.name, d.description || null, req.params.id]);
  if (!r.length) return res.status(404).json({ error: 'Không tìm thấy phòng ban' });
  audit(req, 'department_updated', { id: r[0].id });
  res.json({ ok: true });
}));
app.delete('/api/departments/:id', auth, admin, h(async (req, res) => {
  if (!idOk(req.params.id)) return res.status(400).json({ error: 'Mã không hợp lệ' });
  const n = await q('SELECT count(*)::int AS n FROM employees WHERE department_id = $1', [req.params.id]);
  if (n[0].n > 0) return res.status(409).json({ error: 'Phòng ban đang có nhân viên, hãy chuyển nhân viên trước khi xóa' });
  await q('DELETE FROM departments WHERE id = $1', [req.params.id]);
  audit(req, 'department_deleted', { id: Number(req.params.id) });
  res.json({ ok: true });
}));

// ---------- Nhan vien ----------
const EMP_COLS = `e.id, e.employee_code, e.full_name, e.email, e.phone, e.gender,
  to_char(e.birth_date, 'YYYY-MM-DD') AS birth_date, e.address, e.position, e.department_id,
  d.name AS department, to_char(e.hired_date, 'YYYY-MM-DD') AS hired_date,
  e.base_salary::float8 AS base_salary, e.status,
  EXISTS (SELECT 1 FROM users u WHERE u.employee_id = e.id) AS has_account`;
const empInput = b => {
  const e = {
    full_name: str(b.full_name, 150), email: str(b.email, 150).toLowerCase(), phone: str(b.phone, 20),
    gender: ['Nam', 'Nữ', 'Khác'].includes(b.gender) ? b.gender : null,
    birth_date: dateOk(b.birth_date) ? b.birth_date : null, address: str(b.address, 255),
    position: str(b.position, 100), department_id: idOk(b.department_id) ? Number(b.department_id) : null,
    hired_date: dateOk(b.hired_date) ? b.hired_date : null,
    base_salary: Math.max(0, Math.min(Math.round(Number(b.base_salary)) || 0, 1e10)),
    status: b.status === 'inactive' ? 'inactive' : 'active',
  };
  if (!e.full_name) return { err: 'Họ tên là bắt buộc' };
  if (!emailOk(e.email)) return { err: 'Email không hợp lệ' };
  return { e };
};
const passOk = p => typeof p === 'string' && p.length >= 8 && p.length <= 100;

app.get('/api/employees/options', auth, admin, h(async (_req, res) => res.json(await q(
  `SELECT id, employee_code, full_name FROM employees WHERE status = 'active' ORDER BY employee_code`))));

app.get('/api/employees', auth, admin, h(async (req, res) => {
  const { q: search = '', department_id = '', status = '' } = req.query;
  const limit = 10;
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const where = []; const p = [];
  if (search) {
    p.push('%' + str(String(search), 50).toLowerCase() + '%');
    where.push(`(lower(e.full_name) LIKE $${p.length} OR lower(e.email) LIKE $${p.length} OR lower(e.employee_code) LIKE $${p.length})`);
  }
  if (idOk(department_id)) { p.push(department_id); where.push(`e.department_id = $${p.length}`); }
  if (['active', 'inactive'].includes(status)) { p.push(status); where.push(`e.status = $${p.length}`); }
  const w = where.length ? 'WHERE ' + where.join(' AND ') : '';
  const total = (await q(`SELECT count(*)::int AS n FROM employees e ${w}`, p))[0].n;
  const rows = await q(`SELECT ${EMP_COLS} FROM employees e LEFT JOIN departments d ON d.id = e.department_id
    ${w} ORDER BY e.employee_code LIMIT ${limit} OFFSET ${(page - 1) * limit}`, p);
  res.json({ rows, total, page, limit });
}));

app.post('/api/employees', auth, admin, h(async (req, res) => {
  const b = req.body || {};
  const { e, err } = empInput(b);
  if (err) return res.status(400).json({ error: err });
  if (b.account_password && !passOk(b.account_password))
    return res.status(400).json({ error: 'Mật khẩu tài khoản phải từ 8 ký tự' });
  const code = str(b.employee_code, 20).toUpperCase();
  const r = (await q(
    `INSERT INTO employees (employee_code, full_name, email, phone, gender, birth_date, address, position,
       department_id, hired_date, base_salary, status)
     VALUES (COALESCE(NULLIF($1, ''), 'NV' || lpad((SELECT COALESCE(max(CAST(substring(employee_code FROM '[0-9]+') AS int)), 0) + 1 FROM employees)::text, 4, '0')),
       $2, $3, $4, $5, $6, $7, $8, $9, COALESCE($10::date, CURRENT_DATE), $11, $12)
     RETURNING id, employee_code`,
    [code, e.full_name, e.email, e.phone || null, e.gender, e.birth_date, e.address || null, e.position || null,
      e.department_id, e.hired_date, e.base_salary, e.status]))[0];
  if (b.account_password) {
    await q(`INSERT INTO users (username, password_hash, role, employee_id) VALUES ($1, $2, 'employee', $3)`,
      [r.employee_code.toLowerCase(), hashPw(b.account_password), r.id]);
  }
  audit(req, 'employee_created', { id: r.id, code: r.employee_code });
  res.status(201).json(r);
}));

app.put('/api/employees/:id', auth, admin, h(async (req, res) => {
  if (!idOk(req.params.id)) return res.status(400).json({ error: 'Mã không hợp lệ' });
  const { e, err } = empInput(req.body || {});
  if (err) return res.status(400).json({ error: err });
  const r = await q(
    `UPDATE employees SET full_name = $1, email = $2, phone = $3, gender = $4, birth_date = $5, address = $6,
       position = $7, department_id = $8, hired_date = COALESCE($9::date, hired_date), base_salary = $10, status = $11
     WHERE id = $12 RETURNING id, employee_code`,
    [e.full_name, e.email, e.phone || null, e.gender, e.birth_date, e.address || null, e.position || null,
      e.department_id, e.hired_date, e.base_salary, e.status, req.params.id]);
  if (!r.length) return res.status(404).json({ error: 'Không tìm thấy nhân viên' });
  audit(req, 'employee_updated', { id: r[0].id, code: r[0].employee_code });
  res.json({ ok: true });
}));

app.delete('/api/employees/:id', auth, admin, h(async (req, res) => {
  if (!idOk(req.params.id)) return res.status(400).json({ error: 'Mã không hợp lệ' });
  const r = await q('DELETE FROM employees WHERE id = $1 RETURNING employee_code', [req.params.id]);
  if (!r.length) return res.status(404).json({ error: 'Không tìm thấy nhân viên' });
  audit(req, 'employee_deleted', { id: Number(req.params.id), code: r[0].employee_code });
  res.json({ ok: true });
}));

app.post('/api/employees/:id/account', auth, admin, h(async (req, res) => {
  if (!idOk(req.params.id)) return res.status(400).json({ error: 'Mã không hợp lệ' });
  if (!passOk((req.body || {}).password)) return res.status(400).json({ error: 'Mật khẩu phải từ 8 ký tự' });
  const e = (await q('SELECT id, employee_code FROM employees WHERE id = $1', [req.params.id]))[0];
  if (!e) return res.status(404).json({ error: 'Không tìm thấy nhân viên' });
  await q(`INSERT INTO users (username, password_hash, role, employee_id) VALUES ($1, $2, 'employee', $3)
    ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash`,
    [e.employee_code.toLowerCase(), hashPw(req.body.password), e.id]);
  audit(req, 'account_set', { code: e.employee_code });
  res.json({ ok: true, username: e.employee_code.toLowerCase() });
}));

// ---------- Cham cong ----------
const targetEmp = req => (req.user.role === 'admin' && idOk((req.body || {}).employee_id))
  ? Number((req.body || {}).employee_id) : req.user.employee_id;

app.get('/api/attendance/today', auth, h(async (req, res) => {
  if (!req.user.employee_id) return res.json(null);
  res.json((await q(`SELECT id, to_char(check_in, 'HH24:MI') AS check_in, to_char(check_out, 'HH24:MI') AS check_out
    FROM attendance WHERE employee_id = $1 AND check_in::date = CURRENT_DATE ORDER BY check_in DESC LIMIT 1`,
    [req.user.employee_id]))[0] || null);
}));

app.get('/api/attendance', auth, h(async (req, res) => {
  const month = /^\d{4}-\d{2}$/.test(req.query.month || '') ? req.query.month
    : (await q(`SELECT to_char(CURRENT_DATE, 'YYYY-MM') AS m`))[0].m;
  const p = [month];
  let w = `to_char(a.check_in, 'YYYY-MM') = $1`;
  if (req.user.role !== 'admin') { p.push(req.user.employee_id || 0); w += ` AND a.employee_id = $2`; }
  else if (idOk(req.query.employee_id)) { p.push(req.query.employee_id); w += ` AND a.employee_id = $2`; }
  res.json({ month, rows: await q(`SELECT a.id, a.employee_id, e.employee_code, e.full_name,
      to_char(a.check_in, 'YYYY-MM-DD') AS work_date, to_char(a.check_in, 'HH24:MI') AS check_in,
      to_char(a.check_out, 'HH24:MI') AS check_out,
      round((EXTRACT(EPOCH FROM (a.check_out - a.check_in)) / 3600)::numeric, 2)::float8 AS hours,
      (a.check_in::time > time '08:15') AS late
    FROM attendance a JOIN employees e ON e.id = a.employee_id
    WHERE ${w} ORDER BY a.check_in DESC LIMIT 500`, p) });
}));

app.post('/api/attendance/check-in', auth, h(async (req, res) => {
  const eid = targetEmp(req);
  if (!eid) return res.status(400).json({ error: 'Tài khoản chưa gắn với nhân viên nào' });
  const emp = (await q('SELECT status FROM employees WHERE id = $1', [eid]))[0];
  if (!emp || emp.status !== 'active') return res.status(400).json({ error: 'Nhân viên không tồn tại hoặc đã nghỉ việc' });
  const today = await q('SELECT id FROM attendance WHERE employee_id = $1 AND check_in::date = CURRENT_DATE', [eid]);
  if (today.length) return res.status(409).json({ error: 'Hôm nay đã chấm công vào ca rồi' });
  const r = (await q('INSERT INTO attendance (employee_id) VALUES ($1) RETURNING id', [eid]))[0];
  audit(req, 'check_in', { employee_id: eid });
  res.status(201).json(r);
}));

app.post('/api/attendance/check-out', auth, h(async (req, res) => {
  const eid = targetEmp(req);
  if (!eid) return res.status(400).json({ error: 'Tài khoản chưa gắn với nhân viên nào' });
  const r = await q(`UPDATE attendance SET check_out = NOW() WHERE id = (
      SELECT id FROM attendance WHERE employee_id = $1 AND check_out IS NULL AND check_in::date = CURRENT_DATE
      ORDER BY check_in DESC LIMIT 1) RETURNING id`, [eid]);
  if (!r.length) return res.status(409).json({ error: 'Chưa vào ca hôm nay hoặc đã ra ca rồi' });
  audit(req, 'check_out', { employee_id: eid });
  res.json({ ok: true });
}));

// ---------- Nghi phep ----------
const LEAVE_TYPES = ['annual', 'sick', 'unpaid', 'other'];
app.get('/api/leaves', auth, h(async (req, res) => {
  const p = []; let w = '';
  if (req.user.role !== 'admin') { p.push(req.user.employee_id || 0); w = 'WHERE l.employee_id = $1'; }
  else if (['pending', 'approved', 'rejected'].includes(req.query.status)) { p.push(req.query.status); w = 'WHERE l.status = $1'; }
  res.json(await q(`SELECT l.id, l.employee_id, e.employee_code, e.full_name, l.leave_type,
      to_char(l.start_date, 'YYYY-MM-DD') AS start_date, to_char(l.end_date, 'YYYY-MM-DD') AS end_date,
      (l.end_date - l.start_date + 1)::int AS days, l.reason, l.status,
      to_char(l.created_at, 'YYYY-MM-DD HH24:MI') AS created_at
    FROM leave_requests l JOIN employees e ON e.id = l.employee_id ${w}
    ORDER BY (l.status = 'pending') DESC, l.created_at DESC LIMIT 200`, p));
}));

app.post('/api/leaves', auth, h(async (req, res) => {
  const b = req.body || {};
  const eid = targetEmp(req);
  if (!eid) return res.status(400).json({ error: 'Tài khoản chưa gắn với nhân viên nào' });
  if (!LEAVE_TYPES.includes(b.leave_type)) return res.status(400).json({ error: 'Loại nghỉ không hợp lệ' });
  if (!dateOk(b.start_date) || !dateOk(b.end_date)) return res.status(400).json({ error: 'Ngày không hợp lệ' });
  if (b.end_date < b.start_date) return res.status(400).json({ error: 'Ngày kết thúc phải sau ngày bắt đầu' });
  const r = (await q(`INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, reason)
    VALUES ($1, $2, $3, $4, $5) RETURNING id`, [eid, b.leave_type, b.start_date, b.end_date, str(b.reason, 500) || null]))[0];
  audit(req, 'leave_created', { id: r.id, employee_id: eid });
  res.status(201).json(r);
}));

app.put('/api/leaves/:id/review', auth, admin, h(async (req, res) => {
  if (!idOk(req.params.id)) return res.status(400).json({ error: 'Mã không hợp lệ' });
  const st = (req.body || {}).status;
  if (!['approved', 'rejected'].includes(st)) return res.status(400).json({ error: 'Trạng thái không hợp lệ' });
  const r = await q(`UPDATE leave_requests SET status = $1, reviewed_by = $2, reviewed_at = NOW()
    WHERE id = $3 AND status = 'pending' RETURNING id`, [st, req.user.id, req.params.id]);
  if (!r.length) return res.status(409).json({ error: 'Đơn không còn ở trạng thái chờ duyệt' });
  audit(req, 'leave_' + st, { id: r[0].id });
  res.json({ ok: true });
}));

app.delete('/api/leaves/:id', auth, h(async (req, res) => {
  if (!idOk(req.params.id)) return res.status(400).json({ error: 'Mã không hợp lệ' });
  const own = req.user.role === 'admin' ? '' : ' AND employee_id = ' + Number(req.user.employee_id || 0);
  const r = await q(`DELETE FROM leave_requests WHERE id = $1 AND status = 'pending'${own} RETURNING id`, [req.params.id]);
  if (!r.length) return res.status(409).json({ error: 'Chỉ hủy được đơn của bạn đang chờ duyệt' });
  audit(req, 'leave_cancelled', { id: r[0].id });
  res.json({ ok: true });
}));

// ---------- Tinh / loi ----------
app.use('/api', (_req, res) => res.status(404).json({ error: 'Không tìm thấy' }));
app.use(express.static('public'));
app.use((err, req, res, _next) => {
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'JSON không hợp lệ' });
  if (err.code === '23505') return res.status(409).json({ error: 'Dữ liệu bị trùng (mã nhân viên, email hoặc tên đã tồn tại)' });
  if (err.code === '23503') return res.status(409).json({ error: 'Dữ liệu đang được sử dụng ở nơi khác' });
  if (err.code === '23514') return res.status(400).json({ error: 'Dữ liệu không hợp lệ' });
  log({ level: 'error', msg: err.message, path: req.originalUrl });
  res.status(500).json({ error: 'Lỗi máy chủ' });
});

// ---------- Tao tai khoan admin lan dau ----------
(async () => {
  for (let i = 0; i < 30; i++) {
    try {
      const n = (await q('SELECT count(*)::int AS n FROM users'))[0].n;
      if (n === 0) {
        const pw = process.env.ADMIN_PASSWORD || '';
        if (pw.length < 8) { log({ level: 'warn', msg: 'ADMIN_PASSWORD chua dat (>= 8 ky tu), chua tao tai khoan admin' }); return; }
        await q(`INSERT INTO users (username, password_hash, role) VALUES ('admin', $1, 'admin')`, [hashPw(pw)]);
        log({ event: 'admin_created', username: 'admin' });
      }
      return;
    } catch (e) {
      log({ level: 'warn', msg: 'Cho CSDL / bang users: ' + e.message });
      await new Promise(r => setTimeout(r, 3000));
    }
  }
})();

app.listen(3000, () => log({ msg: 'HRM listening on 3000' }));
