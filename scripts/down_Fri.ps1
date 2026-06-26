param(
    [string]$AwsProfile = "aims-terraform",
    [string]$Region = "ap-northeast-2",
    [string]$ClusterName = "aims-dev-eks",
    [string]$BastionName = "aims-dev-bastion",
    [string]$BastionEipAllocationId = "eipalloc-0e532418e62bc234a"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($LASTEXITCODE -ne 0) {
        throw "$Message (ExitCode: $LASTEXITCODE)"
    }
}

function Convert-ToValueArray {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Trim() -eq "None") {
        return @()
    }

    return @(
        $Text -split '\s+' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne "None" }
    )
}

function Assert-RequiredCommand {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "필수 명령을 찾을 수 없습니다: $Name"
    }
}

Write-Host ""
Write-Host "=================================================="
Write-Host " AIMS Friday Down: EKS + Bastion 삭제"
Write-Host "=================================================="
Write-Host "AWS profile : $AwsProfile"
Write-Host "Region      : $Region"
Write-Host "EKS cluster : $ClusterName"
Write-Host "Bastion     : $BastionName"
Write-Host ""
Write-Host "유지 대상: RDS, MSK, Redis, ALB, Security Group, IAM, EIP"
Write-Host ""

Assert-RequiredCommand -Name "aws"

aws sts get-caller-identity `
    --profile $AwsProfile `
    --region $Region `
    --output table
Assert-LastExitCode "AWS 인증 확인 실패"

$Confirmation = Read-Host "계속하려면 DELETE를 입력하세요"
if ($Confirmation -cne "DELETE") {
    Write-Host "작업을 취소했습니다."
    exit 0
}

# -----------------------------------------------------------------------------
# 1. EKS 관리형 노드 그룹 / Fargate 프로필 / 클러스터 삭제
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "===== [1/2] EKS 클러스터 삭제 ====="

$ClusterStatus = aws eks describe-cluster `
    --profile $AwsProfile `
    --region $Region `
    --name $ClusterName `
    --query "cluster.status" `
    --output text 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "현재 EKS 상태: $ClusterStatus"

    if ($ClusterStatus -eq "DELETING") {
        Write-Host "EKS 클러스터가 이미 삭제 중입니다. 완료를 기다립니다."
        aws eks wait cluster-deleted `
            --profile $AwsProfile `
            --region $Region `
            --name $ClusterName
        Assert-LastExitCode "EKS 클러스터 삭제 대기 실패"
    }
    else {
        $NodeGroupText = aws eks list-nodegroups `
        --profile $AwsProfile `
        --region $Region `
        --cluster-name $ClusterName `
        --query "nodegroups[]" `
        --output text
    Assert-LastExitCode "EKS 노드 그룹 조회 실패"

    $NodeGroups = @(Convert-ToValueArray -Text $NodeGroupText)

    foreach ($NodeGroupName in $NodeGroups) {
        Write-Host "노드 그룹 삭제 요청: $NodeGroupName"

        aws eks delete-nodegroup `
            --profile $AwsProfile `
            --region $Region `
            --cluster-name $ClusterName `
            --nodegroup-name $NodeGroupName `
            --output json | Out-Null
        Assert-LastExitCode "노드 그룹 삭제 요청 실패: $NodeGroupName"

        Write-Host "노드 그룹 삭제 완료 대기 중: $NodeGroupName"
        aws eks wait nodegroup-deleted `
            --profile $AwsProfile `
            --region $Region `
            --cluster-name $ClusterName `
            --nodegroup-name $NodeGroupName
        Assert-LastExitCode "노드 그룹 삭제 대기 실패: $NodeGroupName"
    }

    if ($NodeGroups.Count -eq 0) {
        Write-Host "삭제할 관리형 노드 그룹이 없습니다."
    }

    $FargateText = aws eks list-fargate-profiles `
        --profile $AwsProfile `
        --region $Region `
        --cluster-name $ClusterName `
        --query "fargateProfileNames[]" `
        --output text
    Assert-LastExitCode "EKS Fargate 프로필 조회 실패"

    $FargateProfiles = @(Convert-ToValueArray -Text $FargateText)

    foreach ($FargateProfileName in $FargateProfiles) {
        Write-Host "Fargate 프로필 삭제 요청: $FargateProfileName"

        aws eks delete-fargate-profile `
            --profile $AwsProfile `
            --region $Region `
            --cluster-name $ClusterName `
            --fargate-profile-name $FargateProfileName `
            --output json | Out-Null
        Assert-LastExitCode "Fargate 프로필 삭제 요청 실패: $FargateProfileName"

        aws eks wait fargate-profile-deleted `
            --profile $AwsProfile `
            --region $Region `
            --cluster-name $ClusterName `
            --fargate-profile-name $FargateProfileName
        Assert-LastExitCode "Fargate 프로필 삭제 대기 실패: $FargateProfileName"
    }

    Write-Host "EKS 클러스터 삭제 요청: $ClusterName"
    aws eks delete-cluster `
        --profile $AwsProfile `
        --region $Region `
        --name $ClusterName `
        --output json | Out-Null
    Assert-LastExitCode "EKS 클러스터 삭제 요청 실패"

    Write-Host "EKS 클러스터 삭제 완료 대기 중..."
    aws eks wait cluster-deleted `
        --profile $AwsProfile `
        --region $Region `
        --name $ClusterName
    Assert-LastExitCode "EKS 클러스터 삭제 대기 실패"

        Write-Host "EKS 클러스터 삭제 완료: $ClusterName"
    }
}
else {
    Write-Host "EKS 클러스터가 이미 없거나 조회할 수 없습니다: $ClusterName"
}

# -----------------------------------------------------------------------------
# 2. Bastion EC2 종료
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "===== [2/2] Bastion EC2 종료 ====="

$BastionIdText = aws ec2 describe-instances `
    --profile $AwsProfile `
    --region $Region `
    --filters `
        "Name=tag:Name,Values=$BastionName" `
        "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" `
    --query "Reservations[].Instances[].InstanceId" `
    --output text
Assert-LastExitCode "Bastion EC2 조회 실패"

$BastionInstanceIds = @(Convert-ToValueArray -Text $BastionIdText)

if ($BastionInstanceIds.Count -gt 0) {
    Write-Host "종료할 Bastion 인스턴스: $($BastionInstanceIds -join ', ')"

    aws ec2 terminate-instances `
        --profile $AwsProfile `
        --region $Region `
        --instance-ids $BastionInstanceIds `
        --output json | Out-Null
    Assert-LastExitCode "Bastion EC2 종료 요청 실패"

    Write-Host "Bastion EC2 종료 완료 대기 중..."
    aws ec2 wait instance-terminated `
        --profile $AwsProfile `
        --region $Region `
        --instance-ids $BastionInstanceIds
    Assert-LastExitCode "Bastion EC2 종료 대기 실패"

    Write-Host "Bastion EC2 종료 완료"
}
else {
    Write-Host "종료할 Bastion EC2가 없습니다."
}

# EIP는 release하지 않고 계정에 유지되는지 확인만 함
$BastionPublicIp = aws ec2 describe-addresses `
    --profile $AwsProfile `
    --region $Region `
    --allocation-ids $BastionEipAllocationId `
    --query "Addresses[0].PublicIp" `
    --output text
Assert-LastExitCode "Bastion EIP 확인 실패"

Write-Host ""
Write-Host "=================================================="
Write-Host " Friday Down 완료"
Write-Host " - EKS 클러스터: 삭제"
Write-Host " - Bastion EC2   : 종료"
Write-Host " - Bastion EIP   : 유지 ($BastionPublicIp)"
Write-Host " - RDS/MSK/Redis/ALB/SG/IAM: 변경하지 않음"
Write-Host "=================================================="
Write-Host "월요일에는 scripts\up_Mon.bat을 실행하세요."
