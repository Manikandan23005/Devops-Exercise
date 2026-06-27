#!/usr/bin/env bash
# AWS Region Full Cleanup Script
# Usage: ./nuke-region.sh <region>
set -euo pipefail

REGION="${1:-us-east-1}"
echo ""
echo "=========================================="
echo " NUKING REGION: $REGION"
echo "=========================================="

AWS="aws --region $REGION --no-cli-pager --output text"

# ── 1. CloudFormation Stacks ─────────────────────────────────────────────────
echo "[1/20] CloudFormation Stacks..."
STACKS=$($AWS cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE IMPORT_COMPLETE --query 'StackSummaries[*].StackName' 2>/dev/null || true)
for STACK in $STACKS; do
  echo "  Deleting stack: $STACK"
  $AWS cloudformation delete-stack --stack-name "$STACK" || true
done
# Wait for stacks to delete
for STACK in $STACKS; do
  echo "  Waiting for stack deletion: $STACK"
  $AWS cloudformation wait stack-delete-complete --stack-name "$STACK" 2>/dev/null || true
done

# ── 2. EKS Clusters ──────────────────────────────────────────────────────────
echo "[2/20] EKS Clusters..."
EKS_CLUSTERS=$($AWS eks list-clusters --query 'clusters[*]' 2>/dev/null || true)
for CLUSTER in $EKS_CLUSTERS; do
  echo "  Deleting node groups in: $CLUSTER"
  NODE_GROUPS=$($AWS eks list-nodegroups --cluster-name "$CLUSTER" --query 'nodegroups[*]' 2>/dev/null || true)
  for NG in $NODE_GROUPS; do
    $AWS eks delete-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" || true
    $AWS eks wait nodegroup-deleted --cluster-name "$CLUSTER" --nodegroup-name "$NG" 2>/dev/null || true
  done
  FARGATE_PROFILES=$($AWS eks list-fargate-profiles --cluster-name "$CLUSTER" --query 'fargateProfileNames[*]' 2>/dev/null || true)
  for FP in $FARGATE_PROFILES; do
    $AWS eks delete-fargate-profile --cluster-name "$CLUSTER" --fargate-profile-name "$FP" || true
  done
  echo "  Deleting cluster: $CLUSTER"
  $AWS eks delete-cluster --name "$CLUSTER" || true
  $AWS eks wait cluster-deleted --name "$CLUSTER" 2>/dev/null || true
done

# ── 3. ECS Services & Clusters ───────────────────────────────────────────────
echo "[3/20] ECS Clusters & Services..."
ECS_CLUSTERS=$($AWS ecs list-clusters --query 'clusterArns[*]' 2>/dev/null || true)
for CLUSTER_ARN in $ECS_CLUSTERS; do
  SERVICES=$($AWS ecs list-services --cluster "$CLUSTER_ARN" --query 'serviceArns[*]' 2>/dev/null || true)
  for SVC in $SERVICES; do
    $AWS ecs update-service --cluster "$CLUSTER_ARN" --service "$SVC" --desired-count 0 || true
    $AWS ecs delete-service --cluster "$CLUSTER_ARN" --service "$SVC" --force || true
  done
  TASKS=$($AWS ecs list-tasks --cluster "$CLUSTER_ARN" --query 'taskArns[*]' 2>/dev/null || true)
  for TASK in $TASKS; do
    $AWS ecs stop-task --cluster "$CLUSTER_ARN" --task "$TASK" || true
  done
  echo "  Deleting ECS cluster: $CLUSTER_ARN"
  $AWS ecs delete-cluster --cluster "$CLUSTER_ARN" || true
done

# ── 4. EC2 Instances ─────────────────────────────────────────────────────────
echo "[4/20] EC2 Instances..."
INSTANCE_IDS=$($AWS ec2 describe-instances --query 'Reservations[*].Instances[?State.Name!=`terminated`].InstanceId' --output text 2>/dev/null || true)
if [ -n "$INSTANCE_IDS" ]; then
  echo "  Terminating instances: $INSTANCE_IDS"
  $AWS ec2 terminate-instances --instance-ids $INSTANCE_IDS || true
  $AWS ec2 wait instance-terminated --instance-ids $INSTANCE_IDS 2>/dev/null || true
fi

# ── 5. Auto Scaling Groups ───────────────────────────────────────────────────
echo "[5/20] Auto Scaling Groups..."
ASGS=$($AWS autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[*].AutoScalingGroupName' 2>/dev/null || true)
for ASG in $ASGS; do
  echo "  Deleting ASG: $ASG"
  $AWS autoscaling delete-auto-scaling-group --auto-scaling-group-name "$ASG" --force-delete || true
done

# ── 6. Launch Configurations / Templates ─────────────────────────────────────
echo "[6/20] Launch Configurations & Templates..."
LCS=$($AWS autoscaling describe-launch-configurations --query 'LaunchConfigurations[*].LaunchConfigurationName' 2>/dev/null || true)
for LC in $LCS; do
  $AWS autoscaling delete-launch-configuration --launch-configuration-name "$LC" || true
done
LTS=$($AWS ec2 describe-launch-templates --query 'LaunchTemplates[*].LaunchTemplateId' 2>/dev/null || true)
for LT in $LTS; do
  $AWS ec2 delete-launch-template --launch-template-id "$LT" || true
done

# ── 7. Load Balancers ─────────────────────────────────────────────────────────
echo "[7/20] Load Balancers (ELBv2 & Classic)..."
LB_ARNS=$($AWS elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerArn' 2>/dev/null || true)
for LB in $LB_ARNS; do
  LISTENERS=$($AWS elbv2 describe-listeners --load-balancer-arn "$LB" --query 'Listeners[*].ListenerArn' 2>/dev/null || true)
  for L in $LISTENERS; do
    $AWS elbv2 delete-listener --listener-arn "$L" || true
  done
  echo "  Deleting LB: $LB"
  $AWS elbv2 delete-load-balancer --load-balancer-arn "$LB" || true
done
TG_ARNS=$($AWS elbv2 describe-target-groups --query 'TargetGroups[*].TargetGroupArn' 2>/dev/null || true)
for TG in $TG_ARNS; do
  $AWS elbv2 delete-target-group --target-group-arn "$TG" || true
done
CLASSIC_LBS=$($AWS elb describe-load-balancers --query 'LoadBalancerDescriptions[*].LoadBalancerName' 2>/dev/null || true)
for CLB in $CLASSIC_LBS; do
  $AWS elb delete-load-balancer --load-balancer-name "$CLB" || true
done

# ── 8. RDS ────────────────────────────────────────────────────────────────────
echo "[8/20] RDS Instances & Clusters..."
RDS_CLUSTERS=$($AWS rds describe-db-clusters --query 'DBClusters[*].DBClusterIdentifier' 2>/dev/null || true)
for RDS_CLUSTER in $RDS_CLUSTERS; do
  MEMBERS=$($AWS rds describe-db-clusters --db-cluster-identifier "$RDS_CLUSTER" --query 'DBClusters[0].DBClusterMembers[*].DBInstanceIdentifier' 2>/dev/null || true)
  for MEMBER in $MEMBERS; do
    $AWS rds delete-db-instance --db-instance-identifier "$MEMBER" --skip-final-snapshot --delete-automated-backups || true
  done
  $AWS rds delete-db-cluster --db-cluster-identifier "$RDS_CLUSTER" --skip-final-snapshot || true
done
RDS_INSTANCES=$($AWS rds describe-db-instances --query 'DBInstances[*].DBInstanceIdentifier' 2>/dev/null || true)
for RDS in $RDS_INSTANCES; do
  echo "  Deleting RDS: $RDS"
  $AWS rds delete-db-instance --db-instance-identifier "$RDS" --skip-final-snapshot --delete-automated-backups || true
done

# ── 9. ElastiCache ────────────────────────────────────────────────────────────
echo "[9/20] ElastiCache..."
EC_CLUSTERS=$($AWS elasticache describe-cache-clusters --query 'CacheClusters[*].CacheClusterId' 2>/dev/null || true)
for EC in $EC_CLUSTERS; do
  $AWS elasticache delete-cache-cluster --cache-cluster-id "$EC" || true
done
REPL_GROUPS=$($AWS elasticache describe-replication-groups --query 'ReplicationGroups[*].ReplicationGroupId' 2>/dev/null || true)
for RG in $REPL_GROUPS; do
  $AWS elasticache delete-replication-group --replication-group-id "$RG" --retain-primary-cluster || true
done

# ── 10. Lambda ────────────────────────────────────────────────────────────────
echo "[10/20] Lambda Functions..."
LAMBDAS=$($AWS lambda list-functions --query 'Functions[*].FunctionName' 2>/dev/null || true)
for FN in $LAMBDAS; do
  echo "  Deleting Lambda: $FN"
  $AWS lambda delete-function --function-name "$FN" || true
done

# ── 11. S3 Buckets ────────────────────────────────────────────────────────────
echo "[11/20] S3 Buckets (in region $REGION)..."
ALL_BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text 2>/dev/null || true)
for BUCKET in $ALL_BUCKETS; do
  BUCKET_REGION=$(aws s3api get-bucket-location --bucket "$BUCKET" --query 'LocationConstraint' --output text 2>/dev/null || true)
  # us-east-1 returns 'None' for location
  if [ "$BUCKET_REGION" = "$REGION" ] || { [ "$REGION" = "us-east-1" ] && [ "$BUCKET_REGION" = "None" ]; }; then
    echo "  Emptying & deleting bucket: $BUCKET"
    aws s3 rm "s3://$BUCKET" --recursive 2>/dev/null || true
    # Remove versioned objects
    aws s3api delete-objects --bucket "$BUCKET" \
      --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query '{Objects: Versions[*].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)" \
      2>/dev/null || true
    # Remove delete markers
    aws s3api delete-objects --bucket "$BUCKET" \
      --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query '{Objects: DeleteMarkers[*].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)" \
      2>/dev/null || true
    aws s3api delete-bucket --bucket "$BUCKET" 2>/dev/null || true
  fi
done

# ── 12. DynamoDB ──────────────────────────────────────────────────────────────
echo "[12/20] DynamoDB Tables..."
DYNAMO_TABLES=$($AWS dynamodb list-tables --query 'TableNames[*]' 2>/dev/null || true)
for TABLE in $DYNAMO_TABLES; do
  echo "  Deleting DynamoDB table: $TABLE"
  $AWS dynamodb delete-table --table-name "$TABLE" || true
done

# ── 13. SNS Topics ────────────────────────────────────────────────────────────
echo "[13/20] SNS Topics..."
SNS_TOPICS=$($AWS sns list-topics --query 'Topics[*].TopicArn' 2>/dev/null || true)
for TOPIC in $SNS_TOPICS; do
  $AWS sns delete-topic --topic-arn "$TOPIC" || true
done

# ── 14. SQS Queues ────────────────────────────────────────────────────────────
echo "[14/20] SQS Queues..."
SQS_QUEUES=$($AWS sqs list-queues --query 'QueueUrls[*]' 2>/dev/null || true)
for QUEUE in $SQS_QUEUES; do
  $AWS sqs delete-queue --queue-url "$QUEUE" || true
done

# ── 15. CloudWatch ────────────────────────────────────────────────────────────
echo "[15/20] CloudWatch Alarms & Log Groups..."
CW_ALARMS=$($AWS cloudwatch describe-alarms --query 'MetricAlarms[*].AlarmName' 2>/dev/null || true)
if [ -n "$CW_ALARMS" ]; then
  $AWS cloudwatch delete-alarms --alarm-names $CW_ALARMS || true
fi
LOG_GROUPS=$($AWS logs describe-log-groups --query 'logGroups[*].logGroupName' 2>/dev/null || true)
for LG in $LOG_GROUPS; do
  $AWS logs delete-log-group --log-group-name "$LG" || true
done

# ── 16. ECR Repositories ──────────────────────────────────────────────────────
echo "[16/20] ECR Repositories..."
ECR_REPOS=$($AWS ecr describe-repositories --query 'repositories[*].repositoryName' 2>/dev/null || true)
for REPO in $ECR_REPOS; do
  $AWS ecr delete-repository --repository-name "$REPO" --force || true
done

# ── 17. Secrets Manager & SSM Parameters ─────────────────────────────────────
echo "[17/20] Secrets Manager & SSM Parameters..."
SECRETS=$($AWS secretsmanager list-secrets --query 'SecretList[*].ARN' 2>/dev/null || true)
for SECRET in $SECRETS; do
  $AWS secretsmanager delete-secret --secret-id "$SECRET" --force-delete-without-recovery || true
done
SSM_PARAMS=$($AWS ssm describe-parameters --query 'Parameters[*].Name' 2>/dev/null || true)
for PARAM in $SSM_PARAMS; do
  $AWS ssm delete-parameter --name "$PARAM" || true
done

# ── 18. EC2 AMIs & Snapshots ──────────────────────────────────────────────────
echo "[18/20] EC2 AMIs & Snapshots..."
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
AMIS=$($AWS ec2 describe-images --owners "$ACCOUNT_ID" --query 'Images[*].ImageId' 2>/dev/null || true)
for AMI in $AMIS; do
  $AWS ec2 deregister-image --image-id "$AMI" || true
done
SNAPSHOTS=$($AWS ec2 describe-snapshots --owner-ids "$ACCOUNT_ID" --query 'Snapshots[*].SnapshotId' 2>/dev/null || true)
for SNAP in $SNAPSHOTS; do
  $AWS ec2 delete-snapshot --snapshot-id "$SNAP" || true
done

# ── 19. Key Pairs & Elastic IPs ───────────────────────────────────────────────
echo "[19/20] Key Pairs, Elastic IPs, Security Groups..."
KEY_PAIRS=$($AWS ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' 2>/dev/null || true)
for KP in $KEY_PAIRS; do
  $AWS ec2 delete-key-pair --key-name "$KP" || true
done
EIP_ALLOC_IDS=$($AWS ec2 describe-addresses --query 'Addresses[*].AllocationId' 2>/dev/null || true)
for EIP in $EIP_ALLOC_IDS; do
  $AWS ec2 release-address --allocation-id "$EIP" || true
done

# ── 20. VPC & Networking ──────────────────────────────────────────────────────
echo "[20/20] VPC & Networking Resources..."
VPC_IDS=$($AWS ec2 describe-vpcs --query 'Vpcs[?IsDefault==`false`].VpcId' 2>/dev/null || true)
for VPC in $VPC_IDS; do
  echo "  Cleaning VPC: $VPC"
  # NAT Gateways
  NAT_GWS=$($AWS ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC" --query 'NatGateways[?State!=`deleted`].NatGatewayId' 2>/dev/null || true)
  for NAT in $NAT_GWS; do
    $AWS ec2 delete-nat-gateway --nat-gateway-id "$NAT" || true
  done
  sleep 10
  # Internet Gateways
  IGW_IDS=$($AWS ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" --query 'InternetGateways[*].InternetGatewayId' 2>/dev/null || true)
  for IGW in $IGW_IDS; do
    $AWS ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC" || true
    $AWS ec2 delete-internet-gateway --internet-gateway-id "$IGW" || true
  done
  # Subnets
  SUBNETS=$($AWS ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --query 'Subnets[*].SubnetId' 2>/dev/null || true)
  for SUBNET in $SUBNETS; do
    $AWS ec2 delete-subnet --subnet-id "$SUBNET" || true
  done
  # Route Tables (non-main)
  RTS=$($AWS ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' 2>/dev/null || true)
  for RT in $RTS; do
    $AWS ec2 delete-route-table --route-table-id "$RT" || true
  done
  # Security Groups (non-default)
  SGS=$($AWS ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --query 'SecurityGroups[?GroupName!=`default`].GroupId' 2>/dev/null || true)
  for SG in $SGS; do
    $AWS ec2 delete-security-group --group-id "$SG" || true
  done
  # VPC Endpoints
  ENDPOINTS=$($AWS ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC" --query 'VpcEndpoints[*].VpcEndpointId' 2>/dev/null || true)
  if [ -n "$ENDPOINTS" ]; then
    $AWS ec2 delete-vpc-endpoints --vpc-endpoint-ids $ENDPOINTS || true
  fi
  # Delete VPC
  echo "  Deleting VPC: $VPC"
  $AWS ec2 delete-vpc --vpc-id "$VPC" || true
done

echo ""
echo "=========================================="
echo " DONE: $REGION cleanup complete!"
echo "=========================================="
