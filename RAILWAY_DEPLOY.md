# Deploy lên Railway (không cần thẻ, không cần AWS)

## Cần gì?
- Tài khoản GitHub (free)
- Tài khoản Railway (đăng nhập bằng GitHub)

---

## Bước 1: Push code lên GitHub

Mở Git Bash (hoặc terminal), vào folder project:

```bash
cd aws-demo
git init
git add .
git commit -m "first commit"
```

Lên GitHub.com → New repository → đặt tên `aws-demo` → Create

```bash
git remote add origin https://github.com/YOUR_USERNAME/aws-demo.git
git branch -M main
git push -u origin main
```

---

## Bước 2: Tạo project trên Railway

1. Vào https://railway.app → **Login with GitHub**
2. Click **"New Project"**
3. Chọn **"Deploy from GitHub repo"**
4. Chọn repo `aws-demo` vừa tạo
5. Railway tự detect Dockerfile → click **Deploy**

---

## Bước 3: Thêm MySQL database

Trong project Railway:
1. Click **"+ New"** → **"Database"** → **"Add MySQL"**
2. Railway tự tạo MySQL và tạo biến `MYSQL_URL`, `MYSQLUSER`, `MYSQLPASSWORD`, `MYSQLDATABASE`

---

## Bước 4: Set Environment Variables cho App

Click vào service app (không phải MySQL) → tab **"Variables"** → **"+ New Variable"**:

| Key | Value |
|-----|-------|
| `DB_URL` | `jdbc:mysql://${{MySQL.MYSQL_HOST}}:${{MySQL.MYSQL_PORT}}/${{MySQL.MYSQL_DATABASE}}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC` |
| `DB_USERNAME` | `${{MySQL.MYSQLUSER}}` |
| `DB_PASSWORD` | `${{MySQL.MYSQLPASSWORD}}` |
| `JWT_SECRET` | `myRailwayJwtSecret1234567890123456789012345` |

> Railway tự inject biến từ MySQL service vào app qua cú pháp `${{MySQL.VARIABLE_NAME}}`

Click **Deploy** lại sau khi set biến.

---

## Bước 5: Lấy public URL

Trong service app → tab **"Settings"** → **"Networking"** → click **"Generate Domain"**

Railway cấp URL dạng: `https://aws-demo-production-xxxx.up.railway.app`

---

## Test API

```bash
# Thay YOUR_URL bằng URL Railway vừa lấy
URL="https://aws-demo-production-xxxx.up.railway.app"

# Health check
curl $URL/actuator/health

# Đăng ký
curl -X POST $URL/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@test.com","password":"123456","fullName":"Alice"}'

# Đăng nhập
curl -X POST $URL/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","password":"123456"}'

# Profile (dùng token từ response login)
curl $URL/api/users/me \
  -H "Authorization: Bearer TOKEN_HERE"
```

---

## Chi phí Railway

- **Free**: $5 credit/tháng, không cần thẻ để đăng ký
- App + MySQL chạy thử vài ngày: ~$0.5-1 → nằm trong free credit
- Sau khi hết $5 credit mới cần nhập thẻ

---

## Troubleshooting

| Vấn đề | Cách xử lý |
|--------|-----------|
| Build failed | Xem logs tab "Build Logs" trong Railway |
| App crash | Xem tab "Deploy Logs" |
| Cannot connect DB | Kiểm tra lại biến DB_URL có đúng không |
| 502 error | Đợi thêm 1-2 phút sau deploy |
