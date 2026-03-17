# AWS Demo - Spring Boot + ECS Fargate + RDS MySQL

## 📁 Project Structure

```
aws-demo/
├── src/main/java/com/demo/awsdemo/
│   ├── model/User.java
│   ├── dto/AuthDto.java
│   ├── repository/UserRepository.java
│   ├── service/AuthService.java
│   ├── controller/AuthController.java
│   └── config/
│       ├── SecurityConfig.java
│       ├── JwtUtil.java
│       ├── JwtAuthFilter.java
│       └── GlobalExceptionHandler.java
├── Dockerfile
├── docker-compose.yml
├── deploy-aws-alb.sh    # Deploy với Load Balancer (recommended)
├── deploy-aws.sh        # Deploy đơn giản (không ALB)
├── cleanup-aws.sh       # Xóa resources sau test
└── test-api.sh          # Test API tự động
```

## API Endpoints

| Method | URL | Auth | Description |
|--------|-----|------|-------------|
| POST | /api/auth/register | No | Đăng ký |
| POST | /api/auth/login | No | Đăng nhập |
| GET | /api/users/me | Bearer JWT | Profile |
| GET | /api/public/health-info | No | Status + user count |
| GET | /actuator/health | No | ECS health check |

---

## 🚀 Option A: Deploy bằng Script (AWS CLI)

### 1. Cài AWS CLI
```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install
```

### 2. Tạo IAM User trên AWS Console
1. **IAM** → **Users** → **Create user**
2. Attach policies:
   - `AmazonECS_FullAccess`
   - `AmazonRDSFullAccess`
   - `AmazonEC2FullAccess`
   - `AmazonEC2ContainerRegistryFullAccess`
   - `CloudWatchLogsFullAccess`
   - `IAMFullAccess`
3. **Security credentials** → **Create access key** → chọn **CLI**

### 3. Configure & Deploy
```bash
aws configure
# Nhập Access Key ID, Secret Key, region: ap-southeast-1

# Sửa password trong script trước!
nano deploy-aws-alb.sh   # đổi DB_PASSWORD và JWT_SECRET

chmod +x deploy-aws-alb.sh cleanup-aws.sh test-api.sh
./deploy-aws-alb.sh      # ~10 phút
```

---

## 🖥️ Option B: Deploy bằng AWS Console (không cần CLI)

### Step 1: Push Docker image lên ECR
```bash
# Tạo ECR repo: ECR → Create repository → "aws-demo"
# Click repo → "View push commands" → làm theo

docker build -t aws-demo .
# (làm theo lệnh push trong View push commands)
```

### Step 2: Tạo RDS MySQL
- **RDS** → **Create database** → MySQL 8.0 → Free tier
- DB name: `awsdemo` | Username: `admin` | Public access: No
- Note lại **endpoint** sau khi tạo xong

### Step 3: Tạo ECS Cluster + Task Definition
- **ECS** → **Clusters** → **Create** → Fargate
- **Task Definitions** → **Create** → Fargate, 0.5 vCPU, 1GB RAM
- Add container: image từ ECR, port 8080
- Environment variables:

| Key | Value |
|-----|-------|
| `DB_URL` | `jdbc:mysql://<rds-endpoint>:3306/awsdemo?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC` |
| `DB_USERNAME` | `admin` |
| `DB_PASSWORD` | `YourPassword` |
| `JWT_SECRET` | `YourJwtSecretKey1234567890123456789012345` |

### Step 4: Tạo ALB + ECS Service
- **EC2** → **Load Balancers** → **Application Load Balancer** → port 80
- Target group: IP type, port 8080, health path `/actuator/health`
- **ECS Service**: attach vào ALB vừa tạo

---

## 🧪 Test

```bash
ALB="http://your-alb-dns.amazonaws.com"

# Register
curl -X POST $ALB/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@test.com","password":"pass123","fullName":"Alice"}'

# Login
curl -X POST $ALB/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","password":"pass123"}'

# Profile
curl $ALB/api/users/me -H "Authorization: Bearer <token>"

# Auto test toàn bộ
./test-api.sh $ALB
```

---

## 💰 Chi phí & Cleanup

| Service | Free Tier | Sau free |
|---------|-----------|----------|
| ECS Fargate | 50 vCPU-h/tháng | ~$0.013/h |
| RDS t3.micro | 750h/tháng | ~$0.017/h |
| ALB | 750h/tháng | ~$0.008/h |

```bash
# Xóa tất cả sau khi test (QUAN TRỌNG!)
./cleanup-aws.sh

# Hoặc chỉ stop tạm (giữ config, không tốn tiền compute)
aws ecs update-service --cluster aws-demo-cluster \
  --service aws-demo-service --desired-count 0 --region ap-southeast-1
```

## 🔧 Xem logs trên AWS

```bash
aws logs tail /ecs/aws-demo --follow --region ap-southeast-1
```

Hoặc vào **CloudWatch** → **Log groups** → `/ecs/aws-demo`
