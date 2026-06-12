$ErrorActionPreference = "Stop"

$Profile = "aims-terraform"
$Region = "ap-northeast-2"

$ClusterName = "aims-dev-eks"
$NodeGroupName = "aims-dev-eks-node-group"

$RdsId = "aims-dev-mysql"

$Ec2TagKey = "DailyControl"
$Ec2TagValue = "true"

Write-Host "===== [1/3] RDS 시작 ====="

$RdsStatus = aws rds describe-db-instances `
  --region $Region `
  --profile $Profile `
  --db-instance-identifier $RdsId `
  --query "DBInstances[0].DBInstanceStatus" `
  --output text

if ($RdsStatus -eq "stopped") {
  aws rds start-db-instance `
    --region $Region `
    --profile $Profile `
    --db-instance-identifier $RdsId | Out-Null

  aws rds wait db-instance-available `
    --region $Region `
    --profile $Profile `
    --db-instance-identifier $RdsId

  Write-Host "RDS 시작 완료"
} else {
  Write-Host "RDS가 stopped 상태가 아닙니다. 현재 상태: $RdsStatus"
}

Write-Host "===== [2/3] EC2 시작 ====="

$InstanceIdsText = aws ec2 describe-instances `
  --region $Region `
  --profile $Profile `
  --filters "Name=tag:$Ec2TagKey,Values=$Ec2TagValue" "Name=instance-state-name,Values=stopped" `
  --query "Reservations[].Instances[].InstanceId" `
  --output text

$InstanceIds = $InstanceIdsText -split '\s+' | Where-Object { $_ -and $_ -ne "None" }

if ($InstanceIds.Count -gt 0) {
  aws ec2 start-instances `
    --region $Region `
    --profile $Profile `
    --instance-ids $InstanceIds | Out-Null

  aws ec2 wait instance-running `
    --region $Region `
    --profile $Profile `
    --instance-ids $InstanceIds

  Write-Host "EC2 시작 완료: $InstanceIds"
} else {
  Write-Host "시작할 중지 상태 EC2가 없습니다."
}

Write-Host "===== [3/3] EKS 노드그룹 올리기 ====="

aws eks update-nodegroup-config `
  --region $Region `
  --profile $Profile `
  --cluster-name $ClusterName `
  --nodegroup-name $NodeGroupName `
  --scaling-config minSize=0,maxSize=3,desiredSize=2 | Out-Null

aws eks wait nodegroup-active `
  --region $Region `
  --profile $Profile `
  --cluster-name $ClusterName `
  --nodegroup-name $NodeGroupName

Write-Host "EKS 노드그룹 확대 완료"

Write-Host "===== 개발 환경 시작 완료 ====="