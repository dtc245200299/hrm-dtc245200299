const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => '&#' + c.charCodeAt(0) + ';');
const api = (u, m = 'GET', b) => fetch(u, {
  method: m, headers: { 'Content-Type': 'application/json' },
  body: b ? JSON.stringify(b) : undefined }).then(r => r.json());

async function load() {
  $('dept').innerHTML = (await api('/api/departments'))
    .map(d => `<option value="${d.id}">${esc(d.name)}</option>`).join('');
  const rows = (await api('/api/employees')).map(e => `<tr>
    <td>${e.id}</td><td>${esc(e.full_name)}</td><td>${esc(e.email)}</td>
    <td>${esc(e.position)}</td><td>${esc(e.department)}</td>
    <td><button data-a="check-in" data-id="${e.id}">Vào ca</button>
        <button data-a="check-out" data-id="${e.id}">Ra ca</button>
        <button data-a="delete" data-id="${e.id}">Xóa</button></td></tr>`).join('');
  $('tbl').innerHTML = '<tr><th>ID</th><th>Họ tên</th><th>Email</th><th>Chức vụ</th><th>Phòng ban</th><th></th></tr>' + rows;
}
$('add').onclick = async () => {
  await api('/api/employees', 'POST', { full_name: $('name').value, email: $('email').value,
    position: $('pos').value, department_id: $('dept').value });
  load();
};
$('tbl').onclick = async e => {
  const { a, id } = e.target.dataset; if (!a) return;
  if (a === 'delete') await api('/api/employees/' + id, 'DELETE');
  else await api('/api/attendance/' + a, 'POST', { employee_id: id });
  load();
};
load();
