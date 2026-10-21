CREATE TABLE departments (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL
);
CREATE TABLE employees (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(150) NOT NULL,
  email VARCHAR(150) UNIQUE NOT NULL,
  position VARCHAR(100),
  department_id INT REFERENCES departments(id),
  hired_date DATE DEFAULT CURRENT_DATE
);
CREATE TABLE attendance (
  id SERIAL PRIMARY KEY,
  employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  check_in TIMESTAMP NOT NULL DEFAULT NOW(),
  check_out TIMESTAMP
);
INSERT INTO departments(name) VALUES ('Nhân sự'),('Kỹ thuật'),('Kế toán');
INSERT INTO employees(full_name,email,position,department_id) VALUES
 ('Nguyễn Văn A','a@corp.vn','Trưởng phòng',1),
 ('Trần Thị B','b@corp.vn','Lập trình viên',2);
