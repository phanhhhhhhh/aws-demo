#!/bin/bash
# =================================================================
# deploy-aws.sh - Deploy Spring Boot app to AWS ECS Fargate + RDS
# =================================================================
# Usage: ./deploy-aws.sh
# Prerequisites: AWS CLI configured, Docker running

set -e

# ── Config (EDIT THESE) ──────────────────────────────────────────
AWS_REGION="ap-southeast-1"          # Singapore (gần VN nhất)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
APP_NAME="aws-demo"
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"
ECS_CLUSTER="${APP_NAME}-cluster"
ECS_SERVICE="${APP_NAME}-service"
ECS_TASK="${APP_NAME}-task"

DB_NAME="awsdemo"
DB_USERNAME="admin"
DB_PASSWORD="YourStrongPassword123!"   # ← ĐỔI CÁI NÀY!
JWT_SECRET="YourJwtSecretKey1234567890123456789012345"  # ← ĐỔI CÁI NÀY!

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS ECS Deploy: ${APP_NAME}"
echo "  Region: ${AWS_REGION}"
echo "  Account: ${AWS_ACCOUNT_ID}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Create ECR Repository ────────────────────────────────
echo "[1/7] Creating ECR repository..."
aws ecr create-repository \
  --repository-name ${APP_NAME} \
  --region ${AWS_REGION} \
  --image-scanning-configuration scanOnPush=true \
  2>/dev/null || echo "  ECR repo already exists, skipping."

# ── Step 2: Build & Push Docker image ────────────────────────────
echo "[2/7] Building Docker image..."
docker build -t ${APP_NAME}:latest .

echo "  Pushing to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

docker tag ${APP_NAME}:latest ${ECR_REPO}:latest
docker push ${ECR_REPO}:latest
echo "  ✓ Image pushed: ${ECR_REPO}:latest"

# ── Step 3: Create VPC & Subnets (default VPC) ───────────────────
echo "[3/7] Getting default VPC..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text --region ${AWS_REGION})

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[*].SubnetId" \
  --output text --region ${AWS_REGION} | tr '\t' ',')

echo "  VPC: ${VPC_ID}"
echo "  Subnets: ${SUBNET_IDS}"

# ── Step 4: Create Security Groups ───────────────────────────────
echo "[4/7] Creating security groups..."

# App Security Group
APP_SG=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-app-sg" \
  --description "Security group for ${APP_NAME} ECS tasks" \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --query GroupId --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${APP_NAME}-app-sg" \
    --query "SecurityGroups[0].GroupId" \
    --output text --region ${AWS_REGION})

aws ec2 authorize-security-group-ingress \
  --group-id ${APP_SG} \
  --protocol tcp --port 8080 --cidr 0.0.0.0/0 \
  --region ${AWS_REGION} 2>/dev/null || true

# DB Security Group
DB_SG=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-db-sg" \
  --description "Security group for ${APP_NAME} RDS" \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --query GroupId --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${APP_NAME}-db-sg" \
    --query "SecurityGroups[0].GroupId" \
    --output text --region ${AWS_REGION})

aws ec2 authorize-security-group-ingress \
  --group-id ${DB_SG} \
  --protocol tcp --port 3306 \
  --source-group ${APP_SG} \
  --region ${AWS_REGION} 2>/dev/null || true

echo "  App SG: ${APP_SG}"
echo "  DB SG:  ${DB_SG}"

# ── Step 5: Create RDS MySQL ──────────────────────────────────────
echo "[5/7] Creating RDS MySQL (takes ~5 mins)..."

DB_SUBNET_GROUP="${APP_NAME}-subnet-group"
aws rds create-db-subnet-group \
  --db-subnet-group-name ${DB_SUBNET_GROUP} \
  --db-subnet-group-description "Subnet group for ${APP_NAME}" \
  --subnet-ids $(echo ${SUBNET_IDS} | tr ',' ' ') \
  --region ${AWS_REGION} 2>/dev/null || true

aws rds create-db-instance \
  --db-instance-identifier "${APP_NAME}-mysql" \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0 \
  --master-username ${DB_USERNAME} \
  --master-user-password ${DB_PASSWORD} \
  --db-name ${DB_NAME} \
  --db-subnet-group-name ${DB_SUBNET_GROUP} \
  --vpc-security-group-ids ${DB_SG} \
  --allocated-storage 20 \
  --no-publicly-accessible \
  --backup-retention-period 1 \
  --region ${AWS_REGION} 2>/dev/null || echo "  RDS instance already exists, skipping."

echo "  Waiting for RDS to be available..."
aws rds wait db-instance-available \
  --db-instance-identifier "${APP_NAME}-mysql" \
  --region ${AWS_REGION}

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "${APP_NAME}-mysql" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text --region ${AWS_REGION})

DB_URL="jdbc:mysql://${DB_ENDPOINT}:3306/${DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
echo "  ✓ RDS Endpoint: ${DB_ENDPOINT}"

# ── Step 6: Create ECS Cluster & Task Definition ─────────────────
echo "[6/7] Setting up ECS Fargate..."

# Create cluster
aws ecs create-cluster \
  --cluster-name ${ECS_CLUSTER} \
  --capacity-providers FARGATE \
  --region ${AWS_REGION} 2>/dev/null || true

# Create IAM role for ECS tasks
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{
      "Effect":"Allow",
      "Principal":{"Service":"ecs-tasks.amazonaws.com"},
      "Action":"sts:AssumeRole"
    }]
  }' 2>/dev/null || true

aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  2>/dev/null || true

# Create CloudWatch log group
aws logs create-log-group \
  --log-group-name "/ecs/${APP_NAME}" \
  --region ${AWS_REGION} 2>/dev/null || true

# Register task definition
TASK_DEF=$(cat <<EOF
{
  "family": "${ECS_TASK}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "containerDefinitions": [{
    "name": "${APP_NAME}",
    "image": "${ECR_REPO}:latest",
    "essential": true,
    "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
    "environment": [
      {"name": "DB_URL",      "value": "${DB_URL}"},
      {"name": "DB_USERNAME", "value": "${DB_USERNAME}"},
      {"name": "DB_PASSWORD", "value": "${DB_PASSWORD}"},
      {"name": "JWT_SECRET",  "value": "${JWT_SECRET}"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/${APP_NAME}",
        "awslogs-region": "${AWS_REGION}",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "healthCheck": {
      "command": ["CMD-SHELL", "wget -qO- http://localhost:8080/actuator/health || exit 1"],
      "interval": 30,
      "timeout": 10,
      "retries": 3,
      "startPeriod": 60
    }
  }]
}
EOF
)

aws ecs register-task-definition \
  --cli-input-json "${TASK_DEF}" \
  --region ${AWS_REGION} > /dev/null

echo "  ✓ Task definition registered"

# Create ECS Service
FIRST_SUBNET=$(echo ${SUBNET_IDS} | cut -d',' -f1)
aws ecs create-service \
  --cluster ${ECS_CLUSTER} \
  --service-name ${ECS_SERVICE} \
  --task-definition ${ECS_TASK} \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[${FIRST_SUBNET}],
    securityGroups=[${APP_SG}],
    assignPublicIp=ENABLED
  }" \
  --region ${AWS_REGION} 2>/dev/null || \
aws ecs update-service \
  --cluster ${ECS_CLUSTER} \
  --service ${ECS_SERVICE} \
  --task-definition ${ECS_TASK} \
  --region ${AWS_REGION} > /dev/null

# ── Step 7: Get Public IP ─────────────────────────────────────────
echo "[7/7] Waiting for service to start..."
sleep 30

TASK_ARN=$(aws ecs list-tasks \
  --cluster ${ECS_CLUSTER} \
  --service-name ${ECS_SERVICE} \
  --query "taskArns[0]" \
  --output text --region ${AWS_REGION})

ENI_ID=$(aws ecs describe-tasks \
  --cluster ${ECS_CLUSTER} \
  --tasks ${TASK_ARN} \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
  --output text --region ${AWS_REGION})

PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --network-interface-ids ${ENI_ID} \
  --query "NetworkInterfaces[0].Association.PublicIp" \
  --output text --region ${AWS_REGION})

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ DEPLOYMENT COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  App URL:  http://${PUBLIC_IP}:8080"
echo "  Health:   http://${PUBLIC_IP}:8080/actuator/health"
echo "  Register: POST http://${PUBLIC_IP}:8080/api/auth/register"
echo "  Login:    POST http://${PUBLIC_IP}:8080/api/auth/login"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
