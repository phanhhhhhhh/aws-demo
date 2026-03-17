#!/bin/bash
# =================================================================
# cleanup-aws.sh - Xóa toàn bộ resources sau khi test xong
# Chạy cái này để tránh bị tính phí!
# =================================================================
set -e

AWS_REGION="ap-southeast-1"   # ← Đổi nếu bạn deploy region khác
APP_NAME="aws-demo"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🗑️  AWS Cleanup: ${APP_NAME}"
echo "  Region: ${AWS_REGION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "  ⚠️  Xác nhận xóa tất cả? (yes/no): " confirm
[ "$confirm" != "yes" ] && echo "Cancelled." && exit 0

echo ""

# 1. Stop ECS Service
echo "[1/7] Stopping ECS service..."
aws ecs update-service \
  --cluster "${APP_NAME}-cluster" \
  --service "${APP_NAME}-service" \
  --desired-count 0 \
  --region ${AWS_REGION} 2>/dev/null && echo "  ✓ ECS service stopped" || echo "  - ECS service not found"

aws ecs delete-service \
  --cluster "${APP_NAME}-cluster" \
  --service "${APP_NAME}-service" \
  --force --region ${AWS_REGION} 2>/dev/null && echo "  ✓ ECS service deleted" || true

# 2. Delete ECS Cluster
echo "[2/7] Deleting ECS cluster..."
aws ecs delete-cluster \
  --cluster "${APP_NAME}-cluster" \
  --region ${AWS_REGION} 2>/dev/null && echo "  ✓ ECS cluster deleted" || echo "  - Not found"

# 3. Delete ALB & Target Group
echo "[3/7] Deleting ALB..."
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names "${APP_NAME}-alb" --region ${AWS_REGION} \
  --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null)

if [ "$ALB_ARN" != "None" ] && [ -n "$ALB_ARN" ]; then
  # Delete listeners first
  LISTENER_ARNS=$(aws elbv2 describe-listeners \
    --load-balancer-arn ${ALB_ARN} --region ${AWS_REGION} \
    --query "Listeners[*].ListenerArn" --output text 2>/dev/null)
  for L in $LISTENER_ARNS; do
    aws elbv2 delete-listener --listener-arn ${L} --region ${AWS_REGION} 2>/dev/null || true
  done
  aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN} --region ${AWS_REGION}
  echo "  ✓ ALB deleted"
  sleep 10
fi

TG_ARN=$(aws elbv2 describe-target-groups \
  --names "${APP_NAME}-tg" --region ${AWS_REGION} \
  --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null)
[ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ] && \
  aws elbv2 delete-target-group --target-group-arn ${TG_ARN} --region ${AWS_REGION} && \
  echo "  ✓ Target group deleted" || true

# 4. Delete RDS
echo "[4/7] Deleting RDS MySQL (takes ~5 mins)..."
aws rds delete-db-instance \
  --db-instance-identifier "${APP_NAME}-mysql" \
  --skip-final-snapshot \
  --region ${AWS_REGION} 2>/dev/null && echo "  Waiting for RDS deletion..." || echo "  - RDS not found"

aws rds wait db-instance-deleted \
  --db-instance-identifier "${APP_NAME}-mysql" \
  --region ${AWS_REGION} 2>/dev/null && echo "  ✓ RDS deleted" || true

aws rds delete-db-subnet-group \
  --db-subnet-group-name "${APP_NAME}-subnet-group" \
  --region ${AWS_REGION} 2>/dev/null && echo "  ✓ DB subnet group deleted" || true

# 5. Delete ECR images
echo "[5/7] Cleaning ECR..."
aws ecr batch-delete-image \
  --repository-name ${APP_NAME} \
  --image-ids imageTag=latest \
  --region ${AWS_REGION} 2>/dev/null && echo "  ✓ ECR images deleted" || echo "  - ECR not found"

aws ecr delete-repository \
  --repository-name ${APP_NAME} \
  --force --region ${AWS_REGION} 2>/dev/null && echo "  ✓ ECR repo deleted" || true

# 6. Delete Security Groups
echo "[6/7] Deleting security groups..."
sleep 10  # Wait for dependencies to clear
for SG_NAME in "${APP_NAME}-app-sg" "${APP_NAME}-alb-sg" "${APP_NAME}-db-sg"; do
  SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_NAME}" \
    --query "SecurityGroups[0].GroupId" --output text --region ${AWS_REGION} 2>/dev/null)
  if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    aws ec2 delete-security-group --group-id ${SG_ID} --region ${AWS_REGION} 2>/dev/null && \
      echo "  ✓ Deleted: ${SG_NAME}" || echo "  ! Could not delete ${SG_NAME} (still in use, delete manually)"
  fi
done

# 7. Delete CloudWatch logs
echo "[7/7] Deleting CloudWatch logs..."
aws logs delete-log-group \
  --log-group-name "/ecs/${APP_NAME}" \
  --region ${AWS_REGION} 2>/dev/null && echo "  ✓ Log group deleted" || echo "  - Not found"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Cleanup complete!"
echo "  Kiểm tra AWS Console để đảm bảo không còn resources:"
echo "  https://console.aws.amazon.com/billing/home#/bills"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
