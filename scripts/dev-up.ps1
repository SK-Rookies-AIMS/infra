$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

$Profile = "aims-terraform"
$Region = "ap-northeast-2"

$ClusterName = "aims-dev-eks"
$NodeGroupName = "aims-dev-eks-node-group"

$RdsId = "aims-dev-mysql"

$TerraformDir = "C:\Users\user\aims-infra\terraform"
$PlanFileName = "dev-up.tfplan"

# 시작할 일반 EC2
$Ec2Names = @(
    "redmine-server",
    "aims-dev-bastion"
)


function Assert-Command {
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

    Assert-Command "EC2 조회 실패: $Name"

    return @(
        $Result -split '\s+' |
        Where-Object { $_ -and $_ -ne "None" }
    )
}


Write-Host ""
Write-Host "===== [1/3] Terraform으로 EKS 노드 그룹 생성 ====="

if (-not (Test-Path $TerraformDir)) {
    throw "Terraform 경로를 찾을 수 없습니다: $TerraformDir"
}

Push-Location $TerraformDir

try {
    $PlanFile = Join-Path $TerraformDir $PlanFileName

    Write-Host ""
    Write-Host "[1-1] terraform fmt"

    terraform fmt -recursive

    Assert-Command "terraform fmt 실패"


    if (-not (Test-Path ".terraform")) {
        Write-Host ""
        Write-Host "[1-2] terraform init"

        terraform init -input=false

        Assert-Command "terraform init 실패"
    }


    Write-Host ""
    Write-Host "[1-3] terraform validate"

    terraform validate

    Assert-Command "terraform validate 실패"


    Write-Host ""
    Write-Host "[1-4] terraform plan"

    terraform plan `
        -input=false `
        -lock-timeout=5m `
        -out="$PlanFile"

    Assert-Command "terraform plan 실패"


    Write-Host ""
    Write-Host "[1-5] terraform apply"

    terraform apply `
        -input=false `
        -lock-timeout=5m `
        "$PlanFile"

    Assert-Command "terraform apply 실패"
}
finally {
    if ($PlanFile -and (Test-Path $PlanFile)) {
        Remove-Item $PlanFile -Force
    }

    Pop-Location
}


Write-Host "EKS 노드 그룹 ACTIVE 상태 확인 중..."

aws eks wait nodegroup-active `
    --region $Region `
    --profile $Profile `
    --cluster-name $ClusterName `
    --nodegroup-name $NodeGroupName

Assert-Command "EKS 노드 그룹 ACTIVE 상태 대기 실패"

$NodeGroupStatus = aws eks describe-nodegroup `
    --region $Region `
    --profile $Profile `
    --cluster-name $ClusterName `
    --nodegroup-name $NodeGroupName `
    --query "nodegroup.status" `
    --output text

Assert-Command "EKS 노드 그룹 상태 확인 실패"

Write-Host "EKS 노드 그룹 생성 완료: $NodeGroupName / $NodeGroupStatus"


Write-Host ""
Write-Host "===== [2/3] RDS 시작 ====="

$RdsStatus = aws rds describe-db-instances `
    --region $Region `
    --profile $Profile `
    --db-instance-identifier $RdsId `
    --query "DBInstances[0].DBInstanceStatus" `
    --output text

Assert-Command "RDS 상태 조회 실패"

$RdsStatus = ([string]$RdsStatus).Trim()

switch ($RdsStatus) {
    "stopped" {
        Write-Host "RDS 시작 요청: $RdsId"

        aws rds start-db-instance `
            --region $Region `
            --profile $Profile `
            --db-instance-identifier $RdsId |
            Out-Null

        Assert-Command "RDS 시작 요청 실패"

        Write-Host "RDS 사용 가능 상태 대기 중..."

        aws rds wait db-instance-available `
            --region $Region `
            --profile $Profile `
            --db-instance-identifier $RdsId

        Assert-Command "RDS 시작 대기 실패"

        Write-Host "RDS 시작 완료"
    }

    "starting" {
        Write-Host "RDS가 이미 시작 중입니다. 완료 대기 중..."

        aws rds wait db-instance-available `
            --region $Region `
            --profile $Profile `
            --db-instance-identifier $RdsId

        Assert-Command "RDS 시작 대기 실패"

        Write-Host "RDS 시작 완료"
    }

    "available" {
        Write-Host "RDS가 이미 사용 가능한 상태입니다."
    }

    default {
        throw "현재 RDS 상태에서는 시작할 수 없습니다. 현재 상태: $RdsStatus"
    }
}


Write-Host ""
Write-Host "===== [3/3] EC2 시작 ====="

foreach ($Ec2Name in $Ec2Names) {
    Write-Host ""
    Write-Host "EC2 확인: $Ec2Name"

    $StoppedIds = Get-Ec2InstanceIds `
        -Name $Ec2Name `
        -States @("stopped")

    if ($StoppedIds.Count -gt 0) {
        aws ec2 start-instances `
            --region $Region `
            --profile $Profile `
            --instance-ids $StoppedIds |
            Out-Null

        Assert-Command "EC2 시작 요청 실패: $Ec2Name"

        aws ec2 wait instance-running `
            --region $Region `
            --profile $Profile `
            --instance-ids $StoppedIds

        Assert-Command "EC2 실행 상태 대기 실패: $Ec2Name"

        aws ec2 wait instance-status-ok `
            --region $Region `
            --profile $Profile `
            --instance-ids $StoppedIds

        Assert-Command "EC2 상태 검사 대기 실패: $Ec2Name"

        Write-Host "EC2 시작 완료: $Ec2Name / $($StoppedIds -join ', ')"
        continue
    }

    $StoppingIds = Get-Ec2InstanceIds `
        -Name $Ec2Name `
        -States @("stopping")

    if ($StoppingIds.Count -gt 0) {
        Write-Host "$Ec2Name 인스턴스가 중지 중입니다. 중지 완료 후 시작합니다."

        aws ec2 wait instance-stopped `
            --region $Region `
            --profile $Profile `
            --instance-ids $StoppingIds

        Assert-Command "EC2 중지 상태 대기 실패: $Ec2Name"

        aws ec2 start-instances `
            --region $Region `
            --profile $Profile `
            --instance-ids $StoppingIds |
            Out-Null

        Assert-Command "EC2 시작 요청 실패: $Ec2Name"

        aws ec2 wait instance-running `
            --region $Region `
            --profile $Profile `
            --instance-ids $StoppingIds

        Assert-Command "EC2 실행 상태 대기 실패: $Ec2Name"

        aws ec2 wait instance-status-ok `
            --region $Region `
            --profile $Profile `
            --instance-ids $StoppingIds

        Assert-Command "EC2 상태 검사 대기 실패: $Ec2Name"

        Write-Host "EC2 시작 완료: $Ec2Name"
        continue
    }

    $RunningIds = Get-Ec2InstanceIds `
        -Name $Ec2Name `
        -States @("pending", "running")

    if ($RunningIds.Count -gt 0) {
        aws ec2 wait instance-running `
            --region $Region `
            --profile $Profile `
            --instance-ids $RunningIds

        Assert-Command "EC2 실행 상태 대기 실패: $Ec2Name"

        aws ec2 wait instance-status-ok `
            --region $Region `
            --profile $Profile `
            --instance-ids $RunningIds

        Assert-Command "EC2 상태 검사 대기 실패: $Ec2Name"

        Write-Host "EC2가 이미 실행 중입니다: $Ec2Name"
    }
    else {
        throw "해당 이름의 EC2를 찾을 수 없습니다: $Ec2Name"
    }
}



