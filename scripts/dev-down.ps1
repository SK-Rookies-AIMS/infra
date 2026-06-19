$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

$Profile = "aims-terraform"
$Region = "ap-northeast-2"

$ClusterName = "aims-dev-eks"
$NodeGroupName = "aims-dev-eks-node-group"

$RdsId = "aims-dev-mysql"

# 중지할 일반 EC2
$Ec2Names = @(
    "redmine-server",
    "aims-dev-bastion"
)


function Assert-AwsCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorMessage (ExitCode: $LASTEXITCODE)"
    }
}


function Get-Ec2InstanceIds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string[]]$States
    )

    $StateValues = $States -join ","

    $Result = aws ec2 describe-instances `
        --region $Region `
        --profile $Profile `
        --filters `
            "Name=tag:Name,Values=$Name" `
            "Name=instance-state-name,Values=$StateValues" `
        --query "Reservations[].Instances[].InstanceId" `
        --output text

    Assert-AwsCommand "EC2 조회 실패: $Name"

    return @(
        $Result -split '\s+' |
        Where-Object { $_ -and $_ -ne "None" }
    )
}


Write-Host ""
Write-Host "===== [1/3] EKS 노드 그룹 삭제 ====="

$NodeGroupResult = aws eks list-nodegroups `
    --region $Region `
    --profile $Profile `
    --cluster-name $ClusterName `
    --query "nodegroups[]" `
    --output text

Assert-AwsCommand "EKS 노드 그룹 조회 실패"

$NodeGroups = @(
    $NodeGroupResult -split '\s+' |
    Where-Object { $_ -and $_ -ne "None" }
)

if ($NodeGroups -contains $NodeGroupName) {
    Write-Host "노드 그룹 삭제 요청: $NodeGroupName"

    aws eks delete-nodegroup `
        --region $Region `
        --profile $Profile `
        --cluster-name $ClusterName `
        --nodegroup-name $NodeGroupName |
        Out-Null

    Assert-AwsCommand "EKS 노드 그룹 삭제 요청 실패"

    Write-Host "노드 그룹 삭제 완료 대기 중..."

    aws eks wait nodegroup-deleted `
        --region $Region `
        --profile $Profile `
        --cluster-name $ClusterName `
        --nodegroup-name $NodeGroupName

    Assert-AwsCommand "EKS 노드 그룹 삭제 대기 실패"

    Write-Host "EKS 노드 그룹 삭제 완료"
}
else {
    Write-Host "EKS 노드 그룹이 이미 삭제되어 있습니다."
}


Write-Host ""
Write-Host "===== [2/3] RDS 중지 ====="

$RdsStatus = aws rds describe-db-instances `
    --region $Region `
    --profile $Profile `
    --db-instance-identifier $RdsId `
    --query "DBInstances[0].DBInstanceStatus" `
    --output text

Assert-AwsCommand "RDS 상태 조회 실패"

$RdsStatus = ([string]$RdsStatus).Trim()

switch ($RdsStatus) {
    "available" {
        Write-Host "RDS 중지 요청: $RdsId"

        aws rds stop-db-instance `
            --region $Region `
            --profile $Profile `
            --db-instance-identifier $RdsId |
            Out-Null

        Assert-AwsCommand "RDS 중지 요청 실패"

        Write-Host "RDS 중지 완료 대기 중..."

        aws rds wait db-instance-stopped `
            --region $Region `
            --profile $Profile `
            --db-instance-identifier $RdsId

        Assert-AwsCommand "RDS 중지 대기 실패"

        Write-Host "RDS 중지 완료"
    }

    "stopping" {
        Write-Host "RDS가 이미 중지 중입니다. 완료 대기 중..."

        aws rds wait db-instance-stopped `
            --region $Region `
            --profile $Profile `
            --db-instance-identifier $RdsId

        Assert-AwsCommand "RDS 중지 대기 실패"

        Write-Host "RDS 중지 완료"
    }

    "stopped" {
        Write-Host "RDS가 이미 중지되어 있습니다."
    }

    default {
        throw "현재 RDS 상태에서는 중지할 수 없습니다. 현재 상태: $RdsStatus"
    }
}


Write-Host ""
Write-Host "===== [3/3] EC2 중지 ====="

foreach ($Ec2Name in $Ec2Names) {
    Write-Host ""
    Write-Host "EC2 확인: $Ec2Name"

    $RunningIds = Get-Ec2InstanceIds `
        -Name $Ec2Name `
        -States @("pending", "running")

    if ($RunningIds.Count -gt 0) {
        aws ec2 wait instance-running `
            --region $Region `
            --profile $Profile `
            --instance-ids $RunningIds

        Assert-AwsCommand "EC2 실행 상태 대기 실패: $Ec2Name"

        aws ec2 stop-instances `
            --region $Region `
            --profile $Profile `
            --instance-ids $RunningIds |
            Out-Null

        Assert-AwsCommand "EC2 중지 요청 실패: $Ec2Name"

        aws ec2 wait instance-stopped `
            --region $Region `
            --profile $Profile `
            --instance-ids $RunningIds

        Assert-AwsCommand "EC2 중지 대기 실패: $Ec2Name"

        Write-Host "EC2 중지 완료: $Ec2Name / $($RunningIds -join ', ')"
        continue
    }

    $StoppingIds = Get-Ec2InstanceIds `
        -Name $Ec2Name `
        -States @("stopping")

    if ($StoppingIds.Count -gt 0) {
        Write-Host "$Ec2Name 인스턴스가 이미 중지 중입니다."

        aws ec2 wait instance-stopped `
            --region $Region `
            --profile $Profile `
            --instance-ids $StoppingIds

        Assert-AwsCommand "EC2 중지 대기 실패: $Ec2Name"

        Write-Host "EC2 중지 완료: $Ec2Name"
        continue
    }

    $StoppedIds = Get-Ec2InstanceIds `
        -Name $Ec2Name `
        -States @("stopped")

    if ($StoppedIds.Count -gt 0) {
        Write-Host "EC2가 이미 중지되어 있습니다: $Ec2Name"
    }
    else {
        Write-Host "해당 이름의 EC2를 찾지 못했습니다: $Ec2Name"
    }
}


Write-Host ""
Write-Host "============================================"
Write-Host "개발 환경 종료 완료"
Write-Host "1. EKS 노드 그룹: 삭제"
Write-Host "2. RDS: 중지"
Write-Host "3. redmine-server: 중지"
Write-Host "4. aims-dev-bastion: 중지"
Write-Host "============================================"

