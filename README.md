# HRM - He thong Quan ly Nhan su (DTC245200299)

Do an mon Trien khai va Quan tri He thong Phan mem - De 10.
Ung dung quan ly nhan vien, phong ban, cham cong co ban, trien khai bang Docker Compose.

## Kien truc

Nginx (reverse proxy, HTTPS tu ky) -> App Node.js/Express -> PostgreSQL 16. pgAdmin 4 dung de quan ly DB.
Mang `frontend` (nginx, app, pgadmin) va `backend` (internal: app, db, pgadmin).

## Yeu cau

Ubuntu, Docker Engine, Docker Compose plugin, openssl.

## Cach chay

1. Tao file moi truong va dien mat khau manh:
   `cp .env.example .env` (sinh mat khau: `openssl rand -hex 16`)
2. Sinh chung chi HTTPS tu ky:

mkdir -p nginx/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048
-keyout nginx/certs/server.key -out nginx/certs/server.crt
-subj “/CN=hrm.local” -addext “subjectAltName=DNS:localhost,IP:127.0.0.1”
chmod 644 nginx/certs/server.*

3. Khoi dong: `docker compose up -d --build`
4. Kiem tra: `docker compose ps`

## Truy cap

| Dich vu | URL |
|---|---|
| Website HRM | https://localhost |
| pgAdmin | http://localhost:5050 (dang nhap bang PGADMIN_EMAIL / PGADMIN_PASSWORD) |

Ket noi pgAdmin toi DB: host `db`, port `5432`, database `hrm`, user `hrm_admin`.

## API

`GET/POST /api/employees`, `PUT/DELETE /api/employees/:id`, `GET/POST /api/departments`,
`GET /api/attendance`, `POST /api/attendance/check-in`, `POST /api/attendance/check-out`.

## Bao mat da ap dung (commit 1)

Container app va nginx chay non-root, mang backend internal, DB khong publish cong,
user DB rieng quyen toi thieu (hrm_app), security headers tren Nginx, an /metrics, mat khau nam trong .env (khong commit).

## Giam sat (Prometheus + Grafana)

Dich vu: prometheus, grafana, cadvisor (container), nginx-exporter (web), postgres-exporter (DB).

| Dich vu | URL |
|---|---|
| Grafana | http://localhost:3001 (user admin, mat khau GRAFANA_PASSWORD) |
| Prometheus | http://localhost:9090 |

Dashboard Grafana import theo ID: 14282 (container), 12708 (Nginx), 9628 (PostgreSQL).

### Luu y ve Docker (Docker 29 tren Ubuntu 26.04)

cAdvisor khong nhan ten container khi Docker dung containerd image store. Can tat tinh nang nay:

    echo '{"features":{"containerd-snapshotter":false}}' | sudo tee /etc/docker/daemon.json
    sudo systemctl restart docker

Kiem tra: `docker info -f '{{.DriverStatus}}'` phai co `Backing Filesystem` (overlay2), khong con `io.containerd.snapshotter.v1`.

## Log tap trung (Loki + Promtail)

Promtail doc log cac container qua Docker socket va day vao Loki. Xem log tren Grafana (Explore, datasource Loki).

Truy van LogQL mau:

    {service="app"}
    {service="app"} | json | status >= 400
    {service="nginx"} |= "404"
    sum by (service) (count_over_time({service=~".+"}[5m]))

## Hardening

- Container non-root: app (uid node), nginx-unprivileged (uid 101), grafana/prometheus/loki chay user thuong
- Network isolation: mang backend internal, mang monitoring rieng, DB khong publish cong
- Mat khau manh trong .env (khong commit), .env.example la file mau
- Security headers Nginx: HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy; an X-Powered-By va /metrics
- Phan quyen DB: hrm_app chi SELECT/INSERT/UPDATE/DELETE, exporter chi pg_monitor
- app va nginx: no-new-privileges, cap_drop ALL; app chay read_only filesystem
- Admin tool (pgAdmin, Grafana, Prometheus) chi bind 127.0.0.1

## HRM v2 - Hai tac nhan

He thong co hai vai tro dang nhap:

| Tac nhan | Tai khoan | Chuc nang |
|---|---|---|
| Quan tri vien | `admin` (mat khau: bien ADMIN_PASSWORD trong .env) | Tong quan, quan ly nhan vien, phong ban, cham cong, duyet nghi phep, cap tai khoan |
| Nhan vien | ma nhan vien viet thuong (vd `nv0104`), do quan tri vien cap | Tong quan ca nhan, vao/ra ca, xem lich su cham cong, gui/huy don nghi phep |

Bao mat bo sung: mat khau bam scrypt, cookie phien HttpOnly + Secure + SameSite=Strict, phan quyen theo vai tro o phia may chu,
gioi han dang nhap sai 5 lan/5 phut, nhat ky su kien (login_failed, employee_created...) dang JSON de truy van bang LogQL.
