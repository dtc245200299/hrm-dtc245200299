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
