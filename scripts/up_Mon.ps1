param(
    [string]$AwsProfile = "aims-terraform",
    [string]$Region = "ap-northeast-2",
    [string]$ClusterName = "aims-dev-eks",
    [string]$NodeGroupName = "aims-dev-eks-node-group",
    [string]$BastionName = "aims-dev-bastion",
    [string]$BastionEipAllocationId = "eipalloc-0e532418e62bc234a",
    [switch]$AutoApprove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TerraformDir = Join-Path $RepoRoot "terraform"
$PlanFile = Join-Path $TerraformDir "up_Mon.tfplan"

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($LASTEXITCODE -ne 0) {
        throw "$Message (ExitCode: $LASTEXITCODE)"
    }
}

function Assert-RequiredCommand {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "필수 명령을 찾을 수 없습니다: $Name"
    }
}

Write-Host ""
Write-Host "=================================================="
Write-Host " AIMS Monday Up: Terraform으로 EKS + Bastion 생성"
Write-Host "=================================================="
Write-Host "Repository : $RepoRoot"
Write-Host "Terraform  : $TerraformDir"
Write-Host "AWS profile: $AwsProfile"
Write-Host "Region     : $Region"
Write-Host ""

Assert-RequiredCommand -Name "aws"
Assert-RequiredCommand -Name "terraform"

if (-not (Test-Path $TerraformDir)) {
    throw "Terraform 폴더를 찾을 수 없습니다: $TerraformDir"
}

aws sts get-caller-identity `
    --profile $AwsProfile `
    --region $Region `
    --output table
Assert-LastExitCode "AWS 인증 확인 실패"

Push-Location $TerraformDir

try {
    if (Test-Path $PlanFile) {
        Remove-Item $PlanFile -Force
    }

    Write-Host ""
    Write-Host "===== [1/6] terraform fmt ====="
    terraform fmt -recursive
    Assert-LastExitCode "terraform fmt 실패"

    Write-Host ""
    Write-Host "===== [2/6] terraform init ====="
    terraform init -input=false
    Assert-LastExitCode "terraform init 실패"

    Write-Host ""
    Write-Host "===== [3/6] terraform validate ====="
    terraform validate
    Assert-LastExitCode "terraform validate 실패"

    Write-Host ""
    Write-Host "===== [4/6] terraform plan ====="
    terraform plan `
        -input=false `
        -lock-timeout=5m `
        -out="$PlanFile"
    Assert-LastExitCode "terraform plan 실패"

    Write-Host ""
    Write-Host "===== Terraform plan 상세 내용 ====="
    terraform show -no-color "$PlanFile"
    Assert-LastExitCode "terraform plan 출력 실패"

    if (-not $AutoApprove) {
        Write-Host ""
        Write-Host "계획에서 RDS, MSK, Redis, ALB 삭제 또는 예상 밖 변경이 보이면 APPLY를 입력하지 마세요."
        $Confirmation = Read-Host "계획대로 적용하려면 APPLY를 입력하세요"

        if ($Confirmation -cne "APPLY") {
            Write-Host "terraform apply를 취소했습니다."
            exit 0
        }
    }

    Write-Host ""
    Write-Host "===== [5/6] terraform apply ====="
    terraform apply `
        -input=false `
        -lock-timeout=5m `
        "$PlanFile"
    Assert-LastExitCode "terraform apply 실패"
}
finally {
    if (Test-Path $PlanFile) {
        Remove-Item $PlanFile -Force
    }

    Pop-Location
}

Write-Host ""
Write-Host "===== [6/6] 생성 결과 확인 ====="

aws eks wait cluster-active `
    --profile $AwsProfile `
    --region $Region `
    --name $ClusterName
Assert-LastExitCode "EKS 클러스터 ACTIVE 대기 실패"

aws eks wait nodegroup-active `
    --profile $AwsProfile `
    --region $Region `
    --cluster-name $ClusterName `
    --nodegroup-name $NodeGroupName
Assert-LastExitCode "EKS 노드 그룹 ACTIVE 대기 실패"

Write-Host "kubeconfig 업데이트 중..."
aws eks update-kubeconfig `
    --profile $AwsProfile `
    --region $Region `
    --name $ClusterName
Assert-LastExitCode "kubeconfig 업데이트 실패"

$BastionInstanceId = aws ec2 describe-instances `
    --profile $AwsProfile `
    --region $Region `
    --filters `
        "Name=tag:Name,Values=$BastionName" `
        "Name=instance-state-name,Values=pending,running" `
    --query "Reservations[].Instances[].InstanceId | [0]" `
    --output text
Assert-LastExitCode "Bastion EC2 조회 실패"

if ([string]::IsNullOrWhiteSpace($BastionInstanceId) -or $BastionInstanceId -eq "None") {
    throw "Terraform 적용 후 Bastion EC2를 찾지 못했습니다."
}

aws ec2 wait instance-running `
    --profile $AwsProfile `
    --region $Region `
    --instance-ids $BastionInstanceId
Assert-LastExitCode "Bastion 실행 상태 대기 실패"

aws ec2 wait instance-status-ok `
    --profile $AwsProfile `
    --region $Region `
    --instance-ids $BastionInstanceId
Assert-LastExitCode "Bastion 상태 검사 대기 실패"

$BastionPublicIp = aws ec2 describe-addresses `
    --profile $AwsProfile `
    --region $Region `
    --allocation-ids $BastionEipAllocationId `
    --query "Addresses[0].PublicIp" `
    --output text
Assert-LastExitCode "Bastion Public IP 확인 실패"

$EipInstanceId = aws ec2 describe-addresses `
    --profile $AwsProfile `
    --region $Region `
    --allocation-ids $BastionEipAllocationId `
    --query "Addresses[0].InstanceId" `
    --output text
Assert-LastExitCode "Bastion EIP 연결 대상 확인 실패"

if ($EipInstanceId -ne $BastionInstanceId) {
    throw "Bastion EIP가 새 인스턴스에 연결되지 않았습니다. EIP InstanceId: $EipInstanceId"
}

if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Write-Host ""
    Write-Host "EKS 노드 확인:"
    kubectl get nodes -o wide
    Assert-LastExitCode "kubectl 노드 확인 실패"
}
else {
    Write-Host "kubectl이 없어 노드 확인은 생략합니다."
}

Write-Host ""
Write-Host "=================================================="
Write-Host " Monday Up 완료"
Write-Host " - EKS cluster : $ClusterName"
Write-Host " - Node group  : $NodeGroupName"
Write-Host " - Bastion ID  : $BastionInstanceId"
Write-Host " - Bastion IP  : $BastionPublicIp"
Write-Host "=================================================="
Write-Host ""
Write-Host "다음 작업:"
Write-Host "1. AWS Load Balancer Controller 재설치/확인"
Write-Host "2. Namespace, Secret, ConfigMap 재적용"
Write-Host "3. backend/assembly/quality/ai/frontend GitHub Actions 재배포"
Write-Host "4. Ingress 및 서비스 상태 확인"
