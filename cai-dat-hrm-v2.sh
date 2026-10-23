#!/bin/bash
# Nang cap HRM v2: ung dung co 2 tac nhan (Quan tri vien / Nhan vien)
# Chay trong thu muc du an:  cd ~/hrm-dtc245200299  roi dan/chay file nay.
set +H
hrm_v2() (
  set -e
  if [ ! -f docker-compose.yml ] || [ ! -d app ]; then
    echo "LOI: hay cd vao thu muc du an (vi du: cd ~/hrm-dtc245200299) roi chay lai"; exit 1
  fi

  echo "[1/5] Ghi file co so du lieu va ung dung..."
  mkdir -p db/init app/public
  cat > db/init/03-hrm-v2.sql <<'HRM_EOF_SQL'
-- HRM v2: nang cap schema + du lieu mau (idempotent: chay lai nhieu lan van an toan)

ALTER TABLE departments ADD COLUMN IF NOT EXISTS description TEXT;

ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS employee_code VARCHAR(20),
  ADD COLUMN IF NOT EXISTS phone VARCHAR(20),
  ADD COLUMN IF NOT EXISTS gender VARCHAR(10),
  ADD COLUMN IF NOT EXISTS birth_date DATE,
  ADD COLUMN IF NOT EXISTS address VARCHAR(255),
  ADD COLUMN IF NOT EXISTS base_salary NUMERIC(12,0) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'active';

UPDATE employees SET employee_code = 'NV' || lpad(id::text, 4, '0') WHERE employee_code IS NULL;
ALTER TABLE employees ALTER COLUMN employee_code SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS employees_code_uq ON employees(employee_code);
ALTER TABLE employees DROP CONSTRAINT IF EXISTS employees_status_chk;
ALTER TABLE employees ADD CONSTRAINT employees_status_chk CHECK (status IN ('active', 'inactive'));

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'employee' CHECK (role IN ('admin', 'employee')),
  employee_id INT REFERENCES employees(id) ON DELETE CASCADE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS leave_requests (
  id SERIAL PRIMARY KEY,
  employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  leave_type VARCHAR(30) NOT NULL DEFAULT 'annual',
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  reason VARCHAR(500),
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by INT REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS attendance_checkin_idx ON attendance(check_in);

-- Phan quyen toi thieu cho tai khoan ung dung (chi thao tac du lieu, khong DDL)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO hrm_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO hrm_app;

-- ===== Du lieu mau =====
INSERT INTO departments (name) VALUES ('Kinh doanh'), ('Marketing'), ('Hành chính')
ON CONFLICT DO NOTHING;

UPDATE departments SET description = v.d
FROM (VALUES
  ('Nhân sự', 'Tuyển dụng, đào tạo, chế độ chính sách'),
  ('Kỹ thuật', 'Phát triển và vận hành hệ thống phần mềm'),
  ('Kế toán', 'Kế toán, tài chính, tiền lương'),
  ('Kinh doanh', 'Bán hàng và chăm sóc khách hàng'),
  ('Marketing', 'Truyền thông và thương hiệu'),
  ('Hành chính', 'Văn phòng, mua sắm, hậu cần')
) AS v(n, d)
WHERE departments.name = v.n AND departments.description IS NULL;

INSERT INTO employees (employee_code, full_name, email, phone, gender, birth_date, position, department_id, hired_date, base_salary)
SELECT v.code, v.name, v.email, v.phone, v.gender, v.birth::date, v.pos, d.id, v.hired::date, v.salary
FROM (VALUES
  ('NV0101', 'Nguyễn Thị Lan',    'lan.nguyen@hrm.vn',   '0912345601', 'Nữ',  '1990-03-15', 'Trưởng phòng Nhân sự',    'Nhân sự',    '2019-02-01', 25000000),
  ('NV0102', 'Trần Văn Hùng',     'hung.tran@hrm.vn',    '0912345602', 'Nam', '1994-07-22', 'Chuyên viên tuyển dụng',  'Nhân sự',    '2021-06-15', 14000000),
  ('NV0103', 'Lê Minh Quân',      'quan.le@hrm.vn',      '0912345603', 'Nam', '1988-11-05', 'Trưởng phòng Kỹ thuật',   'Kỹ thuật',   '2018-09-10', 35000000),
  ('NV0104', 'Phạm Thu Hà',       'ha.pham@hrm.vn',      '0912345604', 'Nữ',  '1996-01-30', 'Lập trình viên Backend',  'Kỹ thuật',   '2021-03-01', 22000000),
  ('NV0105', 'Hoàng Đức Anh',     'anh.hoang@hrm.vn',    '0912345605', 'Nam', '1998-09-12', 'Lập trình viên Frontend', 'Kỹ thuật',   '2022-07-11', 20000000),
  ('NV0106', 'Vũ Ngọc Mai',       'mai.vu@hrm.vn',       '0912345606', 'Nữ',  '1993-05-18', 'Kỹ sư DevOps',            'Kỹ thuật',   '2020-11-02', 28000000),
  ('NV0107', 'Đặng Thanh Tùng',   'tung.dang@hrm.vn',    '0912345607', 'Nam', '1985-12-02', 'Kế toán trưởng',          'Kế toán',    '2017-05-20', 30000000),
  ('NV0108', 'Bùi Thị Hương',     'huong.bui@hrm.vn',    '0912345608', 'Nữ',  '1997-04-09', 'Kế toán viên',            'Kế toán',    '2022-01-17', 13000000),
  ('NV0109', 'Ngô Quốc Bảo',      'bao.ngo@hrm.vn',      '0912345609', 'Nam', '1987-08-25', 'Trưởng phòng Kinh doanh', 'Kinh doanh', '2019-08-05', 32000000),
  ('NV0110', 'Đỗ Khánh Linh',     'linh.do@hrm.vn',      '0912345610', 'Nữ',  '2000-02-14', 'Nhân viên kinh doanh',    'Kinh doanh', '2023-02-13', 12000000),
  ('NV0111', 'Phan Văn Khoa',     'khoa.phan@hrm.vn',    '0912345611', 'Nam', '1995-10-03', 'Chuyên viên Marketing',   'Marketing',  '2022-10-03', 16000000),
  ('NV0112', 'Trịnh Mỹ Duyên',    'duyen.trinh@hrm.vn',  '0912345612', 'Nữ',  '1999-06-27', 'Nhân viên hành chính',    'Hành chính', '2023-09-18', 11000000)
) AS v(code, name, email, phone, gender, birth, pos, dept, hired, salary)
JOIN departments d ON d.name = v.dept
ON CONFLICT DO NOTHING;

-- Cham cong 3 tuan gan nhat (chi sinh khi bang con it du lieu, xoa du lieu thu nghiem cu)
DO $$
BEGIN
  IF (SELECT count(*) FROM attendance) < 20 THEN
    DELETE FROM attendance;
    INSERT INTO attendance (employee_id, check_in, check_out)
    SELECT e.id,
           d::date + time '07:55' + (random() * 22) * interval '1 minute',
           d::date + time '17:00' + (random() * 70 - 15) * interval '1 minute'
    FROM employees e
    CROSS JOIN generate_series(current_date - 20, current_date - 1, interval '1 day') AS d
    WHERE e.employee_code LIKE 'NV01%'
      AND extract(isodow FROM d) < 6
      AND random() > 0.08;
  END IF;
END $$;

-- Don nghi phep mau
INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, reason, status)
SELECT e.id, v.t, current_date + v.s, current_date + v.f, v.r, v.st
FROM employees e
JOIN (VALUES
  ('NV0104', 'annual', 3, 5,  'Nghỉ phép năm, đi du lịch cùng gia đình', 'pending'),
  ('NV0108', 'sick',   1, 2,  'Nghỉ ốm có giấy của bác sĩ',              'pending'),
  ('NV0110', 'unpaid', 10, 12, 'Việc riêng của gia đình',                'pending'),
  ('NV0105', 'annual', -9, -8, 'Nghỉ phép năm',                          'approved'),
  ('NV0111', 'other',  -4, -4, 'Đi khám sức khỏe định kỳ',               'approved'),
  ('NV0112', 'annual', -15, -14, 'Về quê',                               'rejected')
) AS v(code, t, s, f, r, st) ON e.employee_code = v.code
WHERE NOT EXISTS (SELECT 1 FROM leave_requests);
HRM_EOF_SQL
  cat > app/package.json <<'HRM_EOF_PKG'
{
  "name": "hrm-app",
  "version": "2.0.0",
  "main": "server.js",
  "dependencies": { "express": "^4.19.2", "pg": "^8.12.0", "prom-client": "^15.1.3" }
}
HRM_EOF_PKG
  cat > app/server.js <<'HRM_EOF_SERVER'
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
HRM_EOF_SERVER
  cat > app/public/index.html <<'HRM_EOF_HTML'
<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>HRM - Quản lý nhân sự</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div id="root"></div>
  <div id="toast"></div>
  <script src="app.js"></script>
</body>
</html>
HRM_EOF_HTML
  cat > app/public/style.css <<'HRM_EOF_CSS'
:root {
  --primary: #2563eb; --primary-d: #1d4ed8; --bg: #f1f5f9; --card: #fff; --ink: #0f172a;
  --muted: #64748b; --line: #e2e8f0; --side: #0f172a; --ok: #16a34a; --warn: #d97706; --bad: #dc2626;
}
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; }
body { font-family: -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background: var(--bg); color: var(--ink); font-size: 14px; }
button, input, select, textarea { font: inherit; }
a { color: var(--primary); }

/* Dang nhap */
.login-wrap { min-height: 100%; display: flex; align-items: center; justify-content: center; background: linear-gradient(135deg, #0f172a 0%, #1e3a8a 100%); padding: 16px; }
.login-card { background: #fff; width: 380px; max-width: 100%; border-radius: 14px; padding: 32px; box-shadow: 0 20px 50px rgba(0,0,0,.35); }
.login-card h1 { margin: 0 0 4px; font-size: 24px; }
.login-card p { margin: 0 0 22px; color: var(--muted); }
.logo { display: inline-flex; width: 44px; height: 44px; border-radius: 12px; background: var(--primary); color: #fff; align-items: center; justify-content: center; font-weight: 700; font-size: 18px; margin-bottom: 14px; }

/* Bo cuc */
.layout { display: flex; min-height: 100%; }
.sidebar { width: 230px; background: var(--side); color: #cbd5e1; display: flex; flex-direction: column; position: fixed; top: 0; bottom: 0; left: 0; }
.brand { display: flex; align-items: center; gap: 10px; padding: 18px 18px 14px; color: #fff; font-weight: 700; font-size: 16px; }
.brand .logo { margin: 0; width: 34px; height: 34px; font-size: 14px; }
.nav { padding: 8px; flex: 1; }
.nav a { display: flex; align-items: center; gap: 10px; padding: 10px 12px; color: #cbd5e1; text-decoration: none; border-radius: 8px; margin-bottom: 2px; }
.nav a:hover { background: #1e293b; color: #fff; }
.nav a.active { background: var(--primary); color: #fff; }
.side-foot { padding: 14px 18px; font-size: 12px; color: #64748b; border-top: 1px solid #1e293b; }
.main { margin-left: 230px; flex: 1; min-width: 0; }
.topbar { background: #fff; border-bottom: 1px solid var(--line); padding: 12px 24px; display: flex; align-items: center; justify-content: space-between; position: sticky; top: 0; z-index: 5; }
.topbar h2 { margin: 0; font-size: 18px; }
.user-box { display: flex; align-items: center; gap: 12px; }
.avatar { width: 34px; height: 34px; border-radius: 50%; background: #dbeafe; color: var(--primary-d); display: flex; align-items: center; justify-content: center; font-weight: 700; }
.user-box small { display: block; color: var(--muted); }
.content { padding: 24px; }

/* The, bang, thanh phan */
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 16px; margin-bottom: 20px; }
.card, .panel { background: var(--card); border: 1px solid var(--line); border-radius: 12px; }
.card { padding: 18px; display: flex; gap: 14px; align-items: center; }
.card .ico { width: 46px; height: 46px; border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 22px; }
.card .num { font-size: 26px; font-weight: 700; line-height: 1.1; }
.card .lbl { color: var(--muted); font-size: 13px; }
.panel { padding: 18px; margin-bottom: 20px; }
.panel h3 { margin: 0 0 14px; font-size: 15px; }
.grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
@media (max-width: 960px) { .grid2 { grid-template-columns: 1fr; } .sidebar { width: 70px; } .sidebar .txt, .brand span, .side-foot { display: none; } .main { margin-left: 70px; } }

.toolbar { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 14px; align-items: center; }
.toolbar .grow { flex: 1; }
input, select, textarea { border: 1px solid #cbd5e1; border-radius: 8px; padding: 8px 10px; background: #fff; color: var(--ink); }
input:focus, select:focus, textarea:focus { outline: 2px solid #bfdbfe; border-color: var(--primary); }
.toolbar input[type=search] { min-width: 240px; }
.btn { border: 1px solid transparent; background: var(--primary); color: #fff; padding: 8px 14px; border-radius: 8px; cursor: pointer; font-weight: 600; }
.btn:hover { background: var(--primary-d); }
.btn.sec { background: #fff; color: var(--ink); border-color: #cbd5e1; }
.btn.sec:hover { background: #f8fafc; }
.btn.ok { background: var(--ok); } .btn.bad { background: var(--bad); }
.btn.sm { padding: 4px 10px; font-size: 12px; }
.btn:disabled { opacity: .5; cursor: not-allowed; }

.table-wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; background: #fff; }
th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--line); white-space: nowrap; }
th { background: #f8fafc; font-size: 12px; text-transform: uppercase; letter-spacing: .03em; color: var(--muted); }
tr:hover td { background: #fafcff; }
td .sub { color: var(--muted); font-size: 12px; }
td.wrap { white-space: normal; min-width: 160px; }
td.act { text-align: right; }
td.act .btn { margin-left: 4px; }
.empty { text-align: center; color: var(--muted); padding: 30px; }

.badge { display: inline-block; padding: 2px 10px; border-radius: 999px; font-size: 12px; font-weight: 600; }
.b-ok { background: #dcfce7; color: #166534; } .b-warn { background: #fef3c7; color: #92400e; }
.b-bad { background: #fee2e2; color: #991b1b; } .b-gray { background: #e2e8f0; color: #334155; } .b-blue { background: #dbeafe; color: #1e40af; }

.pager { display: flex; justify-content: space-between; align-items: center; padding: 12px 4px 0; color: var(--muted); }
.bars .row { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
.bars .name { width: 110px; color: var(--muted); }
.bars .track { flex: 1; background: #e2e8f0; border-radius: 6px; height: 14px; overflow: hidden; }
.bars .fill { height: 100%; background: var(--primary); border-radius: 6px; }
.bars .val { width: 28px; text-align: right; font-weight: 600; }
.cols { display: flex; align-items: flex-end; gap: 10px; height: 160px; padding-top: 10px; }
.cols .col { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: flex-end; height: 100%; }
.cols .bar { width: 100%; max-width: 36px; background: #60a5fa; border-radius: 6px 6px 0 0; min-height: 2px; }
.cols .col b { font-size: 12px; margin-bottom: 4px; } .cols .col span { font-size: 11px; color: var(--muted); margin-top: 6px; }

.today { display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
.today .clock { font-size: 34px; font-weight: 700; }
.chips { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 14px; }
.chip { background: #fff; border: 1px solid var(--line); border-radius: 10px; padding: 8px 14px; }
.chip b { font-size: 18px; margin-right: 6px; }

/* Hop thoai + thong bao */
.overlay { position: fixed; inset: 0; background: rgba(15,23,42,.55); display: flex; align-items: flex-start; justify-content: center; padding: 40px 16px; overflow-y: auto; z-index: 50; }
.modal { background: #fff; border-radius: 14px; width: 640px; max-width: 100%; box-shadow: 0 20px 50px rgba(0,0,0,.3); }
.modal header { display: flex; justify-content: space-between; align-items: center; padding: 16px 20px; border-bottom: 1px solid var(--line); }
.modal header h3 { margin: 0; font-size: 16px; }
.modal .body { padding: 20px; }
.modal footer { padding: 14px 20px; border-top: 1px solid var(--line); display: flex; justify-content: flex-end; gap: 10px; }
.x { background: none; border: 0; font-size: 22px; cursor: pointer; color: var(--muted); }
.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
.form-grid .full { grid-column: 1 / -1; }
label { display: block; font-size: 12px; font-weight: 600; color: var(--muted); margin-bottom: 4px; }
label input, label select, label textarea { width: 100%; margin-top: 4px; font-weight: 400; }
.form-err { color: var(--bad); margin-top: 10px; min-height: 18px; }
#toast { position: fixed; right: 20px; bottom: 20px; z-index: 99; display: flex; flex-direction: column; gap: 8px; }
.toast { background: #0f172a; color: #fff; padding: 10px 16px; border-radius: 10px; box-shadow: 0 6px 20px rgba(0,0,0,.25); }
.toast.err { background: var(--bad); }
.hint { color: var(--muted); font-size: 12px; }
HRM_EOF_CSS
  cat > app/public/app.js <<'HRM_EOF_JS'
'use strict';
const $ = (s, el = document) => el.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => '&#' + c.charCodeAt(0) + ';');
const money = n => new Intl.NumberFormat('vi-VN').format(n || 0) + ' ₫';
const dmy = s => (s ? s.split('-').reverse().join('/') : '');
const localDate = () => new Date().toLocaleDateString('sv-SE');
const LEAVE = { annual: 'Phép năm', sick: 'Nghỉ ốm', unpaid: 'Không lương', other: 'Khác' };
const LSTATUS = { pending: ['Chờ duyệt', 'b-warn'], approved: ['Đã duyệt', 'b-ok'], rejected: ['Từ chối', 'b-bad'] };
const NAV = {
  admin: [['dashboard', '🏠', 'Tổng quan'], ['employees', '👥', 'Nhân viên'], ['departments', '🏢', 'Phòng ban'],
    ['attendance', '🕒', 'Chấm công'], ['leaves', '🌴', 'Nghỉ phép']],
  employee: [['dashboard', '🏠', 'Tổng quan'], ['attendance', '🕒', 'Chấm công'], ['leaves', '🌴', 'Nghỉ phép']],
};
let me = null; let clockTimer = null; let routeToken = 0;
const st = { page: 1, q: '', dept: '', status: '', month: '', emp: '', leaveStatus: '' };

async function api(url, method = 'GET', body) {
  const r = await fetch(url, {
    method, credentials: 'same-origin', headers: { 'Content-Type': 'application/json' },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await r.json(); } catch { /* khong co noi dung */ }
  if (r.status === 401 && !url.startsWith('/api/auth/')) { me = null; renderLogin(); throw new Error('Phiên đăng nhập đã hết hạn'); }
  if (!r.ok) throw new Error((data && data.error) || 'Có lỗi xảy ra');
  return data;
}
function toast(msg, err) {
  const t = document.createElement('div');
  t.className = 'toast' + (err ? ' err' : ''); t.textContent = msg;
  $('#toast').appendChild(t); setTimeout(() => t.remove(), 3200);
}
const run = async (fn, okMsg) => { try { await fn(); if (okMsg) toast(okMsg); } catch (e) { toast(e.message, true); } };

function modal(title, body, okText, onSubmit) {
  const ov = document.createElement('div'); ov.className = 'overlay';
  ov.innerHTML = `<form class="modal"><header><h3>${esc(title)}</h3><button type="button" class="x" data-close>×</button></header>
    <div class="body">${body}<div class="form-err"></div></div>
    <footer><button type="button" class="btn sec" data-close>Hủy</button><button class="btn">${esc(okText)}</button></footer></form>`;
  document.body.appendChild(ov);
  ov.addEventListener('click', e => { if (e.target.hasAttribute('data-close')) ov.remove(); });
  $('form', ov).addEventListener('submit', async e => {
    e.preventDefault();
    try { await onSubmit(Object.fromEntries(new FormData(e.target))); ov.remove(); } catch (err) { $('.form-err', ov).textContent = err.message; }
  });
  const f = $('input:not([disabled]),select,textarea', ov); if (f) f.focus();
}
const confirmBox = (msg, okText, fn) => modal('Xác nhận', `<p>${msg}</p>`, okText, fn);
document.addEventListener('keydown', e => { if (e.key === 'Escape') { const o = document.querySelectorAll('.overlay'); if (o.length) o[o.length - 1].remove(); } });

// ---------- Dang nhap + khung giao dien ----------
function renderLogin() {
  clearInterval(clockTimer);
  $('#root').innerHTML = `<div class="login-wrap"><form class="login-card" id="login-form">
    <div class="logo">HR</div><h1>Quản lý nhân sự</h1><p>Đăng nhập để tiếp tục</p>
    <label>Tài khoản<input name="username" autocomplete="username" required></label>
    <label style="margin-top:12px">Mật khẩu<input name="password" type="password" autocomplete="current-password" required></label>
    <div class="form-err" id="login-err"></div><button class="btn" style="width:100%;margin-top:8px">Đăng nhập</button></form></div>`;
  $('#login-form input').focus();
  $('#login-form').addEventListener('submit', async e => {
    e.preventDefault();
    try { await api('/api/auth/login', 'POST', Object.fromEntries(new FormData(e.target))); await start(); }
    catch (err) { $('#login-err').textContent = err.message; }
  });
}
function renderShell() {
  const name = me.full_name || me.username;
  $('#root').innerHTML = `<div class="layout"><aside class="sidebar"><div class="brand"><div class="logo">HR</div><span>HRM System</span></div>
    <nav class="nav">${NAV[me.role].map(n => `<a href="#/${n[0]}" data-page="${n[0]}"><span>${n[1]}</span><span class="txt">${n[2]}</span></a>`).join('')}</nav>
    <div class="side-foot">Phiên bản 2.0</div></aside>
    <div class="main"><div class="topbar"><h2 id="title"></h2><div class="user-box">
    <div style="text-align:right"><b>${esc(name)}</b><small>${me.role === 'admin' ? 'Quản trị viên' : 'Nhân viên · ' + esc(me.employee_code || '')}</small></div>
    <div class="avatar">${esc(name[0].toUpperCase())}</div><button class="btn sec sm" id="logout">Đăng xuất</button></div></div>
    <div class="content" id="content"></div></div></div>`;
  $('#logout').onclick = async () => { await api('/api/auth/logout', 'POST', {}); me = null; renderLogin(); };
}

// ---------- Thanh phan dung chung ----------
const card = (ico, bg, num, lbl) => `<div class="card"><div class="ico" style="background:${bg}">${ico}</div><div><div class="num">${esc(num)}</div><div class="lbl">${esc(lbl)}</div></div></div>`;
const badge = (txt, cls) => `<span class="badge ${cls}">${esc(txt)}</span>`;
const lbadge = s => badge(LSTATUS[s][0], LSTATUS[s][1]);
const table = (heads, rows, empty) => `<div class="table-wrap"><table><thead><tr>${heads.map(h => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.length ? rows.join('') : `<tr><td class="empty" colspan="${heads.length}">${empty}</td></tr>`}</tbody></table></div>`;
function todayWidget(t) {
  const inn = t && t.check_in; const out = t && t.check_out;
  const text = !inn ? 'Bạn chưa vào ca hôm nay' : out ? `Đã hoàn thành ca: ${t.check_in} – ${t.check_out}` : `Đã vào ca lúc ${t.check_in}`;
  return `<div class="panel today"><div><div class="hint">Chấm công hôm nay · ${dmy(localDate())}</div><div class="clock" id="clock">--:--:--</div><div>${text}</div></div>
    <div><button class="btn ok" data-act="checkin" ${inn ? 'disabled' : ''}>Vào ca</button> <button class="btn bad" data-act="checkout" ${!inn || out ? 'disabled' : ''}>Ra ca</button></div></div>`;
}
function startClock() {
  clearInterval(clockTimer);
  const tick = () => { const c = $('#clock'); if (c) c.textContent = new Date().toLocaleTimeString('vi-VN'); };
  tick(); clockTimer = setInterval(tick, 1000);
}

// ---------- Tong quan ----------
async function pgDashboard(box) {
  const d = await api('/api/dashboard');
  if (d.role === 'admin') {
    const s = d.stats; const max = Math.max(1, ...d.byDept.map(x => x.total)); const wmax = Math.max(1, ...d.week.map(x => x.total));
    box.innerHTML = `<div class="cards">${card('👥', '#dbeafe', s.employees, 'Nhân viên đang làm việc')}${card('🏢', '#dcfce7', s.departments, 'Phòng ban')}
      ${card('✅', '#fef3c7', s.present_today + ' / ' + s.employees, 'Có mặt hôm nay')}${card('📝', '#fee2e2', s.pending_leaves, 'Đơn nghỉ chờ duyệt')}
      ${card('🌴', '#ede9fe', s.on_leave_today, 'Đang nghỉ phép hôm nay')}</div>
      <div class="grid2"><div class="panel"><h3>Nhân viên theo phòng ban</h3><div class="bars">${d.byDept.map(x => `<div class="row"><div class="name">${esc(x.name)}</div><div class="track"><div class="fill" style="width:${Math.round(x.total / max * 100)}%"></div></div><div class="val">${x.total}</div></div>`).join('')}</div></div>
      <div class="panel"><h3>Số người chấm công 7 ngày gần nhất</h3><div class="cols">${d.week.map(x => `<div class="col"><b>${x.total}</b><div class="bar" style="height:${Math.round(x.total / wmax * 110)}px"></div><span>${esc(x.day)}</span></div>`).join('')}</div></div></div>
      <div class="panel"><h3>Nhân viên mới</h3>${table(['Mã NV', 'Họ tên', 'Chức vụ', 'Phòng ban', 'Ngày vào làm'],
        d.recent.map(r => `<tr><td><b>${esc(r.employee_code)}</b></td><td>${esc(r.full_name)}</td><td>${esc(r.position || '—')}</td><td>${esc(r.department || '—')}</td><td>${dmy(r.hired_date)}</td></tr>`), 'Chưa có dữ liệu')}</div>`;
    box.onclick = null; return;
  }
  const t = await api('/api/attendance/today'); const s = d.stats;
  box.innerHTML = `${todayWidget(t)}<div class="cards">${card('📅', '#dbeafe', s.days_this_month, 'Ngày công tháng này')}
    ${card('🌴', '#dcfce7', s.leave_days, 'Ngày phép đã duyệt trong năm')}${card('📝', '#fef3c7', s.pending_leaves, 'Đơn nghỉ chờ duyệt')}</div>`;
  startClock(); bindClock(box);
}
function bindClock(box) {
  box.onclick = e => {
    const a = e.target.dataset.act; if (!a) return;
    run(async () => { await api('/api/attendance/' + (a === 'checkin' ? 'check-in' : 'check-out'), 'POST', {}); route(); }, a === 'checkin' ? 'Đã vào ca' : 'Đã ra ca');
  };
}

// ---------- Nhan vien ----------
const empForm = (e, depts, isNew) => `<div class="form-grid">
  <label>Họ tên *<input name="full_name" value="${esc(e.full_name)}" required></label>
  <label>Email *<input name="email" type="email" value="${esc(e.email)}" required></label>
  <label>Số điện thoại<input name="phone" value="${esc(e.phone)}"></label>
  <label>Giới tính<select name="gender"><option value=""></option>${['Nam', 'Nữ', 'Khác'].map(g => `<option ${e.gender === g ? 'selected' : ''}>${g}</option>`).join('')}</select></label>
  <label>Ngày sinh<input name="birth_date" type="date" value="${esc(e.birth_date)}"></label>
  <label>Ngày vào làm<input name="hired_date" type="date" value="${esc(e.hired_date)}"></label>
  <label>Phòng ban<select name="department_id"><option value=""></option>${depts.map(d => `<option value="${d.id}" ${e.department_id === d.id ? 'selected' : ''}>${esc(d.name)}</option>`).join('')}</select></label>
  <label>Chức vụ<input name="position" value="${esc(e.position)}"></label>
  <label>Lương cơ bản (₫)<input name="base_salary" type="number" min="0" step="100000" value="${esc(e.base_salary || 0)}"></label>
  ${isNew ? '<label>Mật khẩu tài khoản<input name="account_password" type="password" minlength="8" placeholder="Từ 8 ký tự, để trống nếu chưa cấp"></label>'
    : `<label>Trạng thái<select name="status"><option value="active" ${e.status === 'active' ? 'selected' : ''}>Đang làm việc</option><option value="inactive" ${e.status === 'inactive' ? 'selected' : ''}>Đã nghỉ việc</option></select></label>`}
  <label class="full">Địa chỉ<input name="address" value="${esc(e.address)}"></label>
  ${isNew ? '<div class="full hint">Tài khoản đăng nhập của nhân viên chính là mã nhân viên (viết thường).</div>' : ''}</div>`;

async function pgEmployees(box) {
  const depts = await api('/api/departments'); let rows = [];
  const opt = (v, t, cur) => `<option value="${v}" ${String(cur) === String(v) ? 'selected' : ''}>${t}</option>`;
  box.innerHTML = `<div class="toolbar"><input type="search" id="f-q" placeholder="Tìm theo tên, email, mã NV…" value="${esc(st.q)}">
    <select id="f-dept">${opt('', 'Tất cả phòng ban', st.dept)}${depts.map(d => opt(d.id, esc(d.name), st.dept)).join('')}</select>
    <select id="f-status">${opt('', 'Mọi trạng thái', st.status)}${opt('active', 'Đang làm việc', st.status)}${opt('inactive', 'Đã nghỉ việc', st.status)}</select>
    <span class="grow"></span><button class="btn" data-act="add">+ Thêm nhân viên</button></div><div class="panel" style="padding:0" id="emp-list"></div>`;
  const load = async () => {
    const p = new URLSearchParams({ page: st.page, q: st.q, department_id: st.dept, status: st.status });
    const d = await api('/api/employees?' + p); rows = d.rows;
    const pages = Math.max(1, Math.ceil(d.total / d.limit));
    $('#emp-list').innerHTML = table(['Mã NV', 'Nhân viên', 'Phòng ban', 'Chức vụ', 'Ngày vào làm', 'Lương CB', 'Trạng thái', ''], rows.map(e => `<tr>
      <td><b>${esc(e.employee_code)}</b></td><td><div>${esc(e.full_name)}</div><div class="sub">${esc(e.email)}</div></td>
      <td>${esc(e.department || '—')}</td><td>${esc(e.position || '—')}</td><td>${dmy(e.hired_date)}</td><td>${money(e.base_salary)}</td>
      <td>${e.status === 'active' ? badge('Đang làm việc', 'b-ok') : badge('Đã nghỉ việc', 'b-gray')}</td>
      <td class="act"><button class="btn sm sec" data-act="edit" data-id="${e.id}">Sửa</button><button class="btn sm sec" data-act="account" data-id="${e.id}">${e.has_account ? 'Đặt lại MK' : 'Cấp TK'}</button><button class="btn sm bad" data-act="del" data-id="${e.id}">Xóa</button></td></tr>`), 'Không tìm thấy nhân viên nào')
      + `<div class="pager" style="padding:12px 16px"><span>${d.total} nhân viên · Trang ${d.page}/${pages}</span><span><button class="btn sm sec" data-act="prev" ${d.page <= 1 ? 'disabled' : ''}>‹ Trước</button> <button class="btn sm sec" data-act="next" ${d.page >= pages ? 'disabled' : ''}>Sau ›</button></span></div>`;
  };
  let timer;
  $('#f-q').oninput = e => { clearTimeout(timer); timer = setTimeout(() => { st.q = e.target.value; st.page = 1; run(load); }, 300); };
  $('#f-dept').onchange = e => { st.dept = e.target.value; st.page = 1; run(load); };
  $('#f-status').onchange = e => { st.status = e.target.value; st.page = 1; run(load); };
  box.onclick = e => {
    const b = e.target.closest('[data-act]'); if (!b) return;
    const a = b.dataset.act; const emp = rows.find(r => String(r.id) === b.dataset.id);
    if (a === 'prev') { st.page--; run(load); } else if (a === 'next') { st.page++; run(load); }
    else if (a === 'add') modal('Thêm nhân viên', empForm({}, depts, true), 'Lưu', async d => { await api('/api/employees', 'POST', d); toast('Đã thêm nhân viên'); await load(); });
    else if (a === 'edit') modal('Sửa nhân viên ' + emp.employee_code, empForm(emp, depts, false), 'Cập nhật', async d => { await api('/api/employees/' + emp.id, 'PUT', d); toast('Đã cập nhật'); await load(); });
    else if (a === 'del') confirmBox(`Xóa nhân viên <b>${esc(emp.full_name)}</b>? Dữ liệu chấm công và nghỉ phép của người này cũng bị xóa.`, 'Xóa', async () => { await api('/api/employees/' + emp.id, 'DELETE'); toast('Đã xóa'); await load(); });
    else if (a === 'account') modal(`Tài khoản của ${emp.employee_code}`, `<label>Mật khẩu mới<input name="password" type="password" minlength="8" required></label><p class="hint">Tên đăng nhập: <b>${esc(emp.employee_code.toLowerCase())}</b>. Mật khẩu tối thiểu 8 ký tự.</p>`, 'Lưu', async d => { await api(`/api/employees/${emp.id}/account`, 'POST', d); toast('Đã lưu tài khoản'); await load(); });
  };
  await load();
}

// ---------- Phong ban ----------
async function pgDepartments(box) {
  let rows = [];
  const form = d => `<label>Tên phòng ban *<input name="name" value="${esc(d.name)}" required></label><label style="margin-top:12px">Mô tả<textarea name="description" rows="3">${esc(d.description)}</textarea></label>`;
  const load = async () => {
    rows = await api('/api/departments');
    $('#dept-list').innerHTML = table(['Phòng ban', 'Mô tả', 'Số nhân viên', ''], rows.map(d => `<tr><td><b>${esc(d.name)}</b></td><td class="wrap">${esc(d.description || '—')}</td><td>${d.employee_count}</td>
      <td class="act"><button class="btn sm sec" data-act="edit" data-id="${d.id}">Sửa</button><button class="btn sm bad" data-act="del" data-id="${d.id}">Xóa</button></td></tr>`), 'Chưa có phòng ban');
  };
  box.innerHTML = `<div class="toolbar"><span class="grow"></span><button class="btn" data-act="add">+ Thêm phòng ban</button></div><div class="panel" style="padding:0" id="dept-list"></div>`;
  box.onclick = e => {
    const b = e.target.closest('[data-act]'); if (!b) return;
    const d = rows.find(r => String(r.id) === b.dataset.id);
    if (b.dataset.act === 'add') modal('Thêm phòng ban', form({}), 'Lưu', async v => { await api('/api/departments', 'POST', v); toast('Đã thêm phòng ban'); await load(); });
    else if (b.dataset.act === 'edit') modal('Sửa phòng ban', form(d), 'Cập nhật', async v => { await api('/api/departments/' + d.id, 'PUT', v); toast('Đã cập nhật'); await load(); });
    else if (b.dataset.act === 'del') confirmBox(`Xóa phòng ban <b>${esc(d.name)}</b>?`, 'Xóa', async () => { await api('/api/departments/' + d.id, 'DELETE'); toast('Đã xóa'); await load(); });
  };
  await load();
}

// ---------- Cham cong ----------
async function pgAttendance(box) {
  const isAdmin = me.role === 'admin'; let top = ''; let opts = [];
  if (isAdmin) opts = await api('/api/employees/options'); else top = todayWidget(await api('/api/attendance/today'));
  const eo = (cur, blank) => `<option value="">${blank}</option>` + opts.map(o => `<option value="${o.id}" ${String(o.id) === String(cur) ? 'selected' : ''}>${esc(o.employee_code)} · ${esc(o.full_name)}</option>`).join('');
  box.innerHTML = `${top}<div class="toolbar"><label style="margin:0">Tháng <input type="month" id="f-month" value="${esc(st.month)}"></label>
    ${isAdmin ? `<select id="f-emp">${eo(st.emp, 'Tất cả nhân viên')}</select><span class="grow"></span>
    <select id="proxy">${eo('', 'Chấm công hộ…')}</select><button class="btn ok sm" data-act="pin">Vào ca</button><button class="btn bad sm" data-act="pout">Ra ca</button>` : ''}</div>
    <div class="chips" id="chips"></div><div class="panel" style="padding:0" id="att-list"></div>`;
  const load = async () => {
    const p = new URLSearchParams({ month: st.month, employee_id: isAdmin ? st.emp : '' });
    const d = await api('/api/attendance?' + p); st.month = d.month; $('#f-month').value = d.month;
    const late = d.rows.filter(r => r.late).length; const hours = d.rows.reduce((s, r) => s + (r.hours || 0), 0);
    $('#chips').innerHTML = `<div class="chip"><b>${d.rows.length}</b>lượt chấm công</div><div class="chip"><b>${late}</b>lần đi muộn (sau 08:15)</div><div class="chip"><b>${hours.toFixed(1)}</b>giờ làm</div>`;
    $('#att-list').innerHTML = table(['Ngày', 'Mã NV', 'Họ tên', 'Giờ vào', 'Giờ ra', 'Số giờ', 'Trạng thái'], d.rows.map(r => `<tr><td>${dmy(r.work_date)}</td><td><b>${esc(r.employee_code)}</b></td><td>${esc(r.full_name)}</td>
      <td>${esc(r.check_in)}</td><td>${esc(r.check_out || '—')}</td><td>${r.hours == null ? '—' : r.hours.toFixed(2)}</td>
      <td>${!r.check_out ? (r.work_date === localDate() ? badge('Đang làm', 'b-blue') : badge('Chưa ra ca', 'b-warn')) : r.late ? badge('Đi muộn', 'b-warn') : badge('Đúng giờ', 'b-ok')}</td></tr>`), 'Chưa có dữ liệu chấm công trong tháng này');
  };
  $('#f-month').onchange = e => { st.month = e.target.value; run(load); };
  if (isAdmin) $('#f-emp').onchange = e => { st.emp = e.target.value; run(load); };
  box.onclick = e => {
    const a = e.target.dataset.act; if (!a) return;
    if (a === 'checkin' || a === 'checkout') return run(async () => { await api('/api/attendance/' + (a === 'checkin' ? 'check-in' : 'check-out'), 'POST', {}); route(); }, a === 'checkin' ? 'Đã vào ca' : 'Đã ra ca');
    const id = $('#proxy').value; if (!id) return toast('Hãy chọn nhân viên cần chấm công hộ', true);
    run(async () => { await api('/api/attendance/' + (a === 'pin' ? 'check-in' : 'check-out'), 'POST', { employee_id: id }); await load(); }, a === 'pin' ? 'Đã vào ca' : 'Đã ra ca');
  };
  if (!isAdmin) startClock();
  await load();
}

// ---------- Nghi phep ----------
async function pgLeaves(box) {
  const isAdmin = me.role === 'admin'; let rows = [];
  const form = () => `<div class="form-grid"><label class="full">Loại nghỉ<select name="leave_type">${Object.entries(LEAVE).map(([k, v]) => `<option value="${k}">${v}</option>`).join('')}</select></label>
    <label>Từ ngày<input type="date" name="start_date" required></label><label>Đến ngày<input type="date" name="end_date" required></label>
    <label class="full">Lý do<textarea name="reason" rows="3" maxlength="500"></textarea></label></div>`;
  box.innerHTML = `<div class="toolbar">${isAdmin ? `<select id="f-ls"><option value="">Tất cả đơn</option>${Object.entries(LSTATUS).map(([k, v]) => `<option value="${k}" ${st.leaveStatus === k ? 'selected' : ''}>${v[0]}</option>`).join('')}</select>` : ''}
    <span class="grow"></span>${isAdmin ? '' : '<button class="btn" data-act="new">+ Tạo đơn xin nghỉ</button>'}</div><div class="panel" style="padding:0" id="leave-list"></div>`;
  const load = async () => {
    rows = await api('/api/leaves?status=' + (isAdmin ? st.leaveStatus : ''));
    $('#leave-list').innerHTML = table(isAdmin ? ['Nhân viên', 'Loại nghỉ', 'Từ ngày', 'Đến ngày', 'Số ngày', 'Lý do', 'Trạng thái', ''] : ['Loại nghỉ', 'Từ ngày', 'Đến ngày', 'Số ngày', 'Lý do', 'Trạng thái', ''],
      rows.map(r => `<tr>${isAdmin ? `<td><div>${esc(r.full_name)}</div><div class="sub">${esc(r.employee_code)}</div></td>` : ''}<td>${esc(LEAVE[r.leave_type] || r.leave_type)}</td><td>${dmy(r.start_date)}</td><td>${dmy(r.end_date)}</td><td>${r.days}</td>
      <td class="wrap">${esc(r.reason || '—')}</td><td>${lbadge(r.status)}</td><td class="act">${r.status === 'pending' ? (isAdmin ? `<button class="btn sm ok" data-act="ok" data-id="${r.id}">Duyệt</button><button class="btn sm bad" data-act="no" data-id="${r.id}">Từ chối</button>` : `<button class="btn sm sec" data-act="cancel" data-id="${r.id}">Hủy đơn</button>`) : ''}</td></tr>`), 'Chưa có đơn nghỉ phép nào');
  };
  if (isAdmin) $('#f-ls').onchange = e => { st.leaveStatus = e.target.value; run(load); };
  box.onclick = e => {
    const b = e.target.closest('[data-act]'); if (!b) return; const id = b.dataset.id;
    if (b.dataset.act === 'new') modal('Tạo đơn xin nghỉ', form(), 'Gửi đơn', async d => { await api('/api/leaves', 'POST', d); toast('Đã gửi đơn'); await load(); });
    else if (b.dataset.act === 'ok' || b.dataset.act === 'no') run(async () => { await api(`/api/leaves/${id}/review`, 'PUT', { status: b.dataset.act === 'ok' ? 'approved' : 'rejected' }); await load(); }, b.dataset.act === 'ok' ? 'Đã duyệt đơn' : 'Đã từ chối đơn');
    else if (b.dataset.act === 'cancel') confirmBox('Hủy đơn xin nghỉ này?', 'Hủy đơn', async () => { await api('/api/leaves/' + id, 'DELETE'); toast('Đã hủy đơn'); await load(); });
  };
  await load();
}

// ---------- Dinh tuyen ----------
const PAGES = { dashboard: pgDashboard, employees: pgEmployees, departments: pgDepartments, attendance: pgAttendance, leaves: pgLeaves };
async function route() {
  if (!me) return;
  let page = (location.hash || '#/dashboard').replace('#/', '');
  if (!NAV[me.role].some(n => n[0] === page)) page = 'dashboard';
  document.querySelectorAll('.nav a').forEach(a => a.classList.toggle('active', a.dataset.page === page));
  $('#title').textContent = NAV[me.role].find(n => n[0] === page)[2];
  const box = $('#content'); const token = ++routeToken;
  clearInterval(clockTimer); box.onclick = null; box.innerHTML = '<p class="hint">Đang tải…</p>';
  try { await PAGES[page](box); } catch (e) { if (me && token === routeToken) box.innerHTML = `<div class="panel">${esc(e.message)}</div>`; }
}
async function start() {
  try { me = await api('/api/auth/me'); } catch { me = null; renderLogin(); return; }
  renderShell(); route();
}
window.addEventListener('hashchange', route);
start();
HRM_EOF_JS

  echo "[2/5] Cap nhat docker-compose.yml va .env..."
  python3 - <<'HRM_EOF_PATCH'
p = 'docker-compose.yml'
s = open(p).read()
if 'SESSION_SECRET' not in s:
    old = "      DB_PASSWORD: ${APP_DB_PASSWORD}\n"
    assert s.count(old) == 1, "khong tim thay khoi environment cua app trong docker-compose.yml"
    s = s.replace(old, old + "      SESSION_SECRET: ${SESSION_SECRET}\n      ADMIN_PASSWORD: ${ADMIN_PASSWORD}\n")
    open(p, 'w').write(s)
    print("   da them SESSION_SECRET, ADMIN_PASSWORD vao service app")
else:
    print("   docker-compose.yml da co san, bo qua")
HRM_EOF_PATCH
  touch .env .env.example
  [ -n "$(tail -c1 .env)" ] && echo >> .env
  grep -q '^SESSION_SECRET=' .env || echo "SESSION_SECRET=$(openssl rand -hex 32)" >> .env
  grep -q '^ADMIN_PASSWORD=' .env || echo "ADMIN_PASSWORD=$(openssl rand -hex 10)" >> .env
  [ -n "$(tail -c1 .env.example)" ] && echo >> .env.example
  grep -q '^SESSION_SECRET=' .env.example || echo "SESSION_SECRET=" >> .env.example
  grep -q '^ADMIN_PASSWORD=' .env.example || echo "ADMIN_PASSWORD=" >> .env.example
  chmod 600 .env

  if [ -z "$HRM_SKIP_DOCKER" ]; then
    echo "[3/5] Nang cap co so du lieu (them bang users, leave_requests, du lieu mau)..."
    docker compose up -d db
    for i in $(seq 1 30); do docker compose exec -T db pg_isready -q && break; sleep 2; done
    docker compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < db/init/03-hrm-v2.sql 2> /dev/null

    echo "[4/5] Build lai ung dung..."
    docker compose up -d --build app

    echo "[5/5] Kiem tra..."
    code=000
    for i in $(seq 1 30); do
      code=$(curl -sk -o /dev/null -w '%{http_code}' https://localhost/api/auth/me || true)
      [ "$code" = "401" ] && break; sleep 2
    done
    if [ "$code" = "401" ]; then echo "   OK: ung dung HRM v2 dang chay (API tra 401 khi chua dang nhap)";
    else echo "   CANH BAO: chua thay ung dung san sang (ma $code). Xem: docker compose logs app | tail -20"; fi
  fi

  if ! grep -q "HRM v2" README.md 2>/dev/null; then
    cat >> README.md <<'HRM_EOF_README'

## HRM v2 - Hai tac nhan

He thong co hai vai tro dang nhap:

| Tac nhan | Tai khoan | Chuc nang |
|---|---|---|
| Quan tri vien | `admin` (mat khau: bien ADMIN_PASSWORD trong .env) | Tong quan, quan ly nhan vien, phong ban, cham cong, duyet nghi phep, cap tai khoan |
| Nhan vien | ma nhan vien viet thuong (vd `nv0104`), do quan tri vien cap | Tong quan ca nhan, vao/ra ca, xem lich su cham cong, gui/huy don nghi phep |

Bao mat bo sung: mat khau bam scrypt, cookie phien HttpOnly + Secure + SameSite=Strict, phan quyen theo vai tro o phia may chu,
gioi han dang nhap sai 5 lan/5 phut, nhat ky su kien (login_failed, employee_created...) dang JSON de truy van bang LogQL.
HRM_EOF_README
  fi

  echo
  echo "XONG. Mo trinh duyet: https://localhost"
  echo " - Quan tri vien: tai khoan admin, mat khau xem bang lenh:  grep '^ADMIN_PASSWORD=' .env"
  echo " - Nhan vien: dang nhap admin > Nhan vien > bam 'Cap TK' o mot nhan vien, roi dang nhap bang ma NV (viet thuong)"
)
hrm_v2
