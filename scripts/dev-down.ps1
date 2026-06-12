$ErrorActionPreference = "Stop"

$Profile = "aims-terraform"
$Region = "ap-northeast-2"

$ClusterName = "aims-dev-eks"
$NodeGroupName = "aims-dev-eks-node-group"

$RdsId = "aims-dev-mysql"

# 중지할 EC2에 아래 태그를 붙여두는 방식
$Ec2TagKey = "DailyControl"
$Ec2TagValue = "true"

Write-Host "===== [1/3] EKS 노드그룹 내리기 ====="

aws eks update-nodegroup-config `
  --region $Region `
  --profile $Profile `
  --cluster-name $ClusterName `
  --nodegroup-name $NodeGroupName `
  --scaling-config minSize=0,maxSize=3,desiredSize=0 | Out-Null

aws eks wait nodegroup-active `
  --region $Region `
  --profile $Profile `
  --cluster-name $ClusterName `
  --nodegroup-name $NodeGroupName

Write-Host "EKS 노드그룹 축소 완료"

Write-Host "===== [2/3] EC2 중지 ====="

$InstanceIdsText = aws ec2 describe-instances `
  --region $Region `
  --profile $Profile `
  --filters "Name=tag:$Ec2TagKey,Values=$Ec2TagValue" "Name=instance-state-name,Values=running" `
  --query "Reservations[].Instances[].InstanceId" `
  --output text

$InstanceIds = $InstanceIdsText -split '\s+' | Where-Object { $_ -and $_ -ne "None" }

if ($InstanceIds.Count -gt 0) {
  aws ec2 stop-instances `
    --region $Region `
    --profile $Profile `
    --instance-ids $InstanceIds | Out-Null

  aws ec2 wait instance-stopped `
    --region $Region `
    --profile $Profile `
    --instance-ids $InstanceIds

  Write-Host "EC2 중지 완료: $InstanceIds"
} else {
  Write-Host "중지할 실행 중 EC2가 없습니다."
}

Write-Host "===== [3/3] RDS 중지 ====="

$RdsStatus = aws rds describe-db-instances `
  --region $Region `
  --profile $Profile `
  --db-instance-identifier $RdsId `
  --query "DBInstances[0].DBInstanceStatus" `
  --output text

if ($RdsStatus -eq "available") {
  aws rds stop-db-instance `
    --region $Region `
    --profile $Profile `
    --db-instance-identifier $RdsId | Out-Null

  aws rds wait db-instance-stopped `
    --region $Region `
    --profile $Profile `
    --db-instance-identifier $RdsId

  Write-Host "RDS 중지 완료"
} else {
  Write-Host "RDS가 available 상태가 아닙니다. 현재 상태: $RdsStatus"
}

Write-Host "===== 개발 환경 종료 완료 ====="