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
