#!/bin/bash
# =================================================================
# deploy-aws-alb.sh - Deploy với Application Load Balancer
# App URL sẽ là DNS cố định, không bị đổi IP mỗi lần restart
# =================================================================
set -e

# ── Config (EDIT THESE) ──────────────────────────────────────────
AWS_REGION="ap-southeast-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
APP_NAME="aws-demo"
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"
ECS_CLUSTER="${APP_NAME}-cluster"
ECS_SERVICE="${APP_NAME}-service"
ECS_TASK="${APP_NAME}-task"

DB_NAME="awsdemo"
DB_USERNAME="admin"
DB_PASSWORD="YourStrongPassword123!"    # ← ĐỔI!
JWT_SECRET="YourJwtSecret_ChangeThis_MinLength40Chars!!"  # ← ĐỔI!

# ─────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deploy with ALB | Region: ${AWS_REGION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Build & Push to ECR ───────────────────────────────────
echo ""
echo "[1/8] 🐳 Building & pushing Docker image..."
aws ecr create-repository --repository-name ${APP_NAME} --region ${AWS_REGION} 2>/dev/null || true
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
docker build -t ${APP_NAME}:latest .
docker tag ${APP_NAME}:latest ${ECR_REPO}:latest
docker push ${ECR_REPO}:latest
echo "  ✓ Image pushed: ${ECR_REPO}:latest"

# ── Step 2: Networking ────────────────────────────────────────────
echo ""
echo "[2/8] 🌐 Setting up VPC & subnets..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" --output text --region ${AWS_REGION})

# Get at least 2 subnets (required for ALB)
SUBNET_ARRAY=($(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[*].SubnetId" --output text --region ${AWS_REGION}))

SUBNET_1=${SUBNET_ARRAY[0]}
SUBNET_2=${SUBNET_ARRAY[1]}
echo "  VPC: ${VPC_ID} | Subnet1: ${SUBNET_1} | Subnet2: ${SUBNET_2}"

# ── Step 3: Security Groups ───────────────────────────────────────
echo ""
echo "[3/8] 🔒 Creating security groups..."

# ALB SG - public HTTP/HTTPS
ALB_SG=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-alb-sg" \
  --description "ALB SG for ${APP_NAME}" \
  --vpc-id ${VPC_ID} --region ${AWS_REGION} \
  --query GroupId --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${APP_NAME}-alb-sg" "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[0].GroupId" --output text --region ${AWS_REGION})

aws ec2 authorize-security-group-ingress --group-id ${ALB_SG} \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 --region ${AWS_REGION} 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id ${ALB_SG} \
  --protocol tcp --port 443 --cidr 0.0.0.0/0 --region ${AWS_REGION} 2>/dev/null || true

# App SG - only allow traffic FROM ALB
APP_SG=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-app-sg" \
  --description "App SG for ${APP_NAME}" \
  --vpc-id ${VPC_ID} --region ${AWS_REGION} \
  --query GroupId --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${APP_NAME}-app-sg" "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[0].GroupId" --output text --region ${AWS_REGION})

aws ec2 authorize-security-group-ingress --group-id ${APP_SG} \
  --protocol tcp --port 8080 --source-group ${ALB_SG} --region ${AWS_REGION} 2>/dev/null || true

# DB SG - only allow from App
DB_SG=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-db-sg" \
  --description "DB SG for ${APP_NAME}" \
  --vpc-id ${VPC_ID} --region ${AWS_REGION} \
  --query GroupId --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${APP_NAME}-db-sg" "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[0].GroupId" --output text --region ${AWS_REGION})

aws ec2 authorize-security-group-ingress --group-id ${DB_SG} \
  --protocol tcp --port 3306 --source-group ${APP_SG} --region ${AWS_REGION} 2>/dev/null || true

echo "  ✓ ALB SG: ${ALB_SG} | App SG: ${APP_SG} | DB SG: ${DB_SG}"

# ── Step 4: RDS MySQL ─────────────────────────────────────────────
echo ""
echo "[4/8] 🗄️  Creating RDS MySQL (takes ~5 mins)..."

aws rds create-db-subnet-group \
  --db-subnet-group-name "${APP_NAME}-subnet-group" \
  --db-subnet-group-description "Subnet group for ${APP_NAME}" \
  --subnet-ids ${SUBNET_1} ${SUBNET_2} \
  --region ${AWS_REGION} 2>/dev/null || true

aws rds create-db-instance \
  --db-instance-identifier "${APP_NAME}-mysql" \
  --db-instance-class db.t3.micro \
  --engine mysql --engine-version 8.0 \
  --master-username ${DB_USERNAME} \
  --master-user-password ${DB_PASSWORD} \
  --db-name ${DB_NAME} \
  --db-subnet-group-name "${APP_NAME}-subnet-group" \
  --vpc-security-group-ids ${DB_SG} \
  --allocated-storage 20 \
  --no-publicly-accessible \
  --backup-retention-period 1 \
  --region ${AWS_REGION} 2>/dev/null || echo "  RDS already exists."

echo "  Waiting for RDS..."
aws rds wait db-instance-available \
  --db-instance-identifier "${APP_NAME}-mysql" --region ${AWS_REGION}

DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "${APP_NAME}-mysql" \
  --query "DBInstances[0].Endpoint.Address" --output text --region ${AWS_REGION})

DB_URL="jdbc:mysql://${DB_HOST}:3306/${DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
echo "  ✓ RDS host: ${DB_HOST}"

# ── Step 5: Application Load Balancer ────────────────────────────
echo ""
echo "[5/8] ⚖️  Creating Application Load Balancer..."

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${APP_NAME}-alb" \
  --subnets ${SUBNET_1} ${SUBNET_2} \
  --security-groups ${ALB_SG} \
  --scheme internet-facing \
  --type application \
  --region ${AWS_REGION} \
  --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || \
  aws elbv2 describe-load-balancers \
    --names "${APP_NAME}-alb" --region ${AWS_REGION} \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${ALB_ARN} --region ${AWS_REGION} \
  --query "LoadBalancers[0].DNSName" --output text)

# Target Group
TG_ARN=$(aws elbv2 create-target-group \
  --name "${APP_NAME}-tg" \
  --protocol HTTP --port 8080 \
  --vpc-id ${VPC_ID} \
  --target-type ip \
  --health-check-path "/actuator/health" \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --region ${AWS_REGION} \
  --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || \
  aws elbv2 describe-target-groups \
    --names "${APP_NAME}-tg" --region ${AWS_REGION} \
    --query "TargetGroups[0].TargetGroupArn" --output text)

# Listener HTTP:80
aws elbv2 create-listener \
  --load-balancer-arn ${ALB_ARN} \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
  --region ${AWS_REGION} 2>/dev/null || true

echo "  ✓ ALB DNS: ${ALB_DNS}"
echo "  ✓ Target Group: ${TG_ARN}"

# ── Step 6: ECS Setup ─────────────────────────────────────────────
echo ""
echo "[6/8] 📦 Setting up ECS..."

aws ecs create-cluster \
  --cluster-name ${ECS_CLUSTER} --region ${AWS_REGION} 2>/dev/null || true

# IAM role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  2>/dev/null || true
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  2>/dev/null || true

# CloudWatch logs
aws logs create-log-group --log-group-name "/ecs/${APP_NAME}" --region ${AWS_REGION} 2>/dev/null || true

# Task definition
aws ecs register-task-definition --region ${AWS_REGION} --cli-input-json "{
  \"family\": \"${ECS_TASK}\",
  \"networkMode\": \"awsvpc\",
  \"requiresCompatibilities\": [\"FARGATE\"],
  \"cpu\": \"512\",
  \"memory\": \"1024\",
  \"executionRoleArn\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole\",
  \"containerDefinitions\": [{
    \"name\": \"${APP_NAME}\",
    \"image\": \"${ECR_REPO}:latest\",
    \"essential\": true,
    \"portMappings\": [{\"containerPort\": 8080, \"protocol\": \"tcp\"}],
    \"environment\": [
      {\"name\": \"DB_URL\",      \"value\": \"${DB_URL}\"},
      {\"name\": \"DB_USERNAME\", \"value\": \"${DB_USERNAME}\"},
      {\"name\": \"DB_PASSWORD\", \"value\": \"${DB_PASSWORD}\"},
      {\"name\": \"JWT_SECRET\",  \"value\": \"${JWT_SECRET}\"}
    ],
    \"logConfiguration\": {
      \"logDriver\": \"awslogs\",
      \"options\": {
        \"awslogs-group\": \"/ecs/${APP_NAME}\",
        \"awslogs-region\": \"${AWS_REGION}\",
        \"awslogs-stream-prefix\": \"ecs\"
      }
    },
    \"healthCheck\": {
      \"command\": [\"CMD-SHELL\", \"wget -qO- http://localhost:8080/actuator/health || exit 1\"],
      \"interval\": 30,
      \"timeout\": 10,
      \"retries\": 3,
      \"startPeriod\": 60
    }
  }]
}" > /dev/null

echo "  ✓ Task definition registered"

# ── Step 7: ECS Service with ALB ──────────────────────────────────
echo ""
echo "[7/8] 🚀 Creating ECS service..."

aws ecs create-service \
  --cluster ${ECS_CLUSTER} \
  --service-name ${ECS_SERVICE} \
  --task-definition ${ECS_TASK} \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[${SUBNET_1},${SUBNET_2}],
    securityGroups=[${APP_SG}],
    assignPublicIp=ENABLED
  }" \
  --load-balancers "targetGroupArn=${TG_ARN},containerName=${APP_NAME},containerPort=8080" \
  --health-check-grace-period-seconds 90 \
  --region ${AWS_REGION} 2>/dev/null || \
aws ecs update-service \
  --cluster ${ECS_CLUSTER} \
  --service ${ECS_SERVICE} \
  --task-definition ${ECS_TASK} \
  --region ${AWS_REGION} > /dev/null

# ── Step 8: Done ──────────────────────────────────────────────────
echo ""
echo "[8/8] ⏳ Waiting for service to be stable (~2 mins)..."
aws ecs wait services-stable \
  --cluster ${ECS_CLUSTER} \
  --services ${ECS_SERVICE} \
  --region ${AWS_REGION}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  DEPLOYMENT COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🌐 Base URL  : http://${ALB_DNS}"
echo "  ❤️  Health   : http://${ALB_DNS}/actuator/health"
echo "  📋 Info      : http://${ALB_DNS}/api/public/health-info"
echo ""
echo "  📮 Register  : POST http://${ALB_DNS}/api/auth/register"
echo "  🔐 Login     : POST http://${ALB_DNS}/api/auth/login"
echo "  👤 Profile   : GET  http://${ALB_DNS}/api/users/me"
echo ""
echo "  📊 CloudWatch Logs:"
echo "     https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups/log-group/%2Fecs%2F${APP_NAME}"
echo ""
echo "  ⚠️  Cleanup command (tránh tốn tiền):"
echo "     aws ecs update-service --cluster ${ECS_CLUSTER} --service ${ECS_SERVICE} --desired-count 0 --region ${AWS_REGION}"
echo "     aws rds delete-db-instance --db-instance-identifier ${APP_NAME}-mysql --skip-final-snapshot --region ${AWS_REGION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Save output to file
cat > .env.deployed << EOF
ALB_URL=http://${ALB_DNS}
DB_HOST=${DB_HOST}
ECR_REPO=${ECR_REPO}
ECS_CLUSTER=${ECS_CLUSTER}
REGION=${AWS_REGION}
EOF
echo "  Saved to .env.deployed"
