# AIMS Infrastructure

AI 기반 자동차 스마트팩토리 관제 시스템의 개발 환경을 구축하고 운영하기 위한 인프라 저장소입니다.

Terraform으로 AWS 인프라를 관리하고, Kubernetes와 Kustomize로 서비스 배포 구성을 정의합니다. Argo CD의 App of Apps 패턴을 통해 `dev` 브랜치의 변경 사항을 Amazon EKS에 자동 반영합니다.

---

## 주요 기능

### 1. Terraform 기반 AWS 인프라 관리

* 기존 VPC와 Public/Private Subnet 조회
* Amazon EKS 클러스터 및 Managed Node Group 구성
* EKS OIDC Provider와 IRSA용 IAM Role 구성
* Amazon RDS for MySQL 구성
* Amazon ElastiCache for Redis 구성
* Amazon MSK 및 Kafka Topic 구성
* 서비스별 Security Group과 통신 규칙 구성
* Route 53 DNS 레코드 및 ACM 인증서 구성
* S3 Backend와 DynamoDB Lock을 이용한 Terraform 상태 관리

### 2. Kubernetes 기반 마이크로서비스 배포

| 서비스              |   포트 | Replica | 외부 경로          | Secret                              |
| ---------------- | ---: | ------: | -------------- | ----------------------------------- |
| Frontend         |   80 |       2 | `/`            | 없음                                  |
| Backend          | 8081 |       2 | `/api`, `/ws`  | `backend-rds-secret`                |
| Assembly Service | 8082 |       1 | `/api/process` | `assembly-service-secret`           |
| Quality Service  | 8083 |       2 | `/api/quality` | `quality-service-runtime-secret` |
| AI Service API   | 8000 |       1 | `/api/ai`      | `ai-service-secret`              |

각 Deployment에는 다음 설정이 포함되어 있습니다.

* Startup, Readiness, Liveness Probe
* CPU 및 Memory Requests/Limits
* ConfigMap과 Secret 기반 환경 변수 주입
* ClusterIP Service
* ECR 이미지 태그 기반 버전 관리

### 3. Argo CD GitOps 자동 배포

* `argocd/root-dev.yaml`에서 하위 Application 통합 관리
* `dev` 브랜치 자동 감시
* 자동 Sync, Prune, Self Heal 활성화
* 서비스별 Kustomize 경로 독립 관리

```text
Application Repository
        │
        ├─ Docker Image Build
        └─ Amazon ECR Push
                │
                ▼
Infra Repository의 kustomization.yaml 이미지 태그 변경
                │
                ▼
             Argo CD
                │
                ▼
            Amazon EKS
```

### 4. 공용 ALB 기반 경로 라우팅

각 Ingress는 `aims-dev-app` ALB Group을 공유합니다.

```text
Route 53 / ACM
      │
      ▼
AWS Application Load Balancer
      ├─ /             → Frontend:80
      ├─ /api          → Backend:8081
      ├─ /ws           → Backend:8081
      ├─ /api/process  → Assembly Service:8082
      ├─ /api/quality  → Quality Service:8083
      └─ /api/ai       → AI Service API:8000
```

* Internet-facing ALB
* Target Type `ip`
* HTTP → HTTPS 리다이렉트
* 서비스별 Health Check 경로 적용
* Backend `/api`, `/ws` 경로에 Sticky Session 적용

### 5. Kafka 이벤트 스트리밍

Amazon MSK는 IAM 인증과 TLS 방식으로 구성되어 있습니다.

주요 Topic:

* `factory.manufacturing.raw`
* `factory.manufacturing.analysis`
* `factory.manufacturing.alert`
* `factory.equipment.status`
* `quality.inspection.drive_detail`
* `quality.inspection.status_detail`
* `quality.inspection.process`
* `quality.inspection.risk_history`
* `quality.inspection.risk_trend`
* `quality.inspection.summary`

Topic은 Terraform의 `aws_msk_topic` 리소스로 관리하며 Replication Factor는 2입니다.

### 6. Elastic Stack 구성

`platform` 네임스페이스에 다음 리소스를 배포합니다.

* Elasticsearch 8.17.0
* Kibana 8.17.0
* Logstash 8.17.0 기반 커스텀 이미지
* Logstash의 MSK 접근을 위한 ServiceAccount와 IRSA
* Kibana 전용 ALB Ingress

### 7. IRSA 기반 AWS 권한 분리

| 대상                           | 주요 권한                 |
| ---------------------------- | --------------------- |
| Backend                      | S3 객체 조회 및 저장         |
| Assembly Service             | MSK Topic 접근          |
| Logstash                     | MSK Topic 읽기          |
| AWS Load Balancer Controller | ALB 및 Target Group 관리 |
| EBS CSI Driver               | EBS Volume 관리         |

---

## 기술 스택

| 분류                     | 기술                                            |
| ---------------------- | --------------------------------------------- |
| Infrastructure as Code | Terraform `>= 1.5.0`                          |
| Terraform Provider     | AWS Provider `6.49.0`, TLS Provider `4.3.0`   |
| Cloud                  | AWS Seoul Region (`ap-northeast-2`)           |
| Compute                | Amazon EKS, EC2, ECR                          |
| Orchestration          | Kubernetes, Kustomize                         |
| GitOps                 | Argo CD, App of Apps                          |
| Load Balancing         | AWS Load Balancer Controller, ALB             |
| Database               | Amazon RDS for MySQL                          |
| Cache                  | Redis OSS 7.1, Amazon ElastiCache             |
| Messaging              | Amazon MSK, Apache Kafka 3.9.x, IAM SASL, TLS |
| Logging                | Elasticsearch, Kibana, Logstash 8.17.0        |
| DNS/SSL                | Route 53, ACM                                 |
| Authentication         | IAM, IRSA, EKS OIDC Provider                  |
| State Management       | S3 Backend, DynamoDB Lock                     |
| Automation             | AWS CLI, PowerShell, Batch Script             |

### 주요 인프라 기본값

| 리소스         | 기본 구성                                          |
| ----------- | ---------------------------------------------- |
| EKS Node    | `m5.large`, On-Demand, Amazon Linux 2023       |
| EKS Scaling | Min 0 / Desired 3 / Max 3                      |
| RDS         | MySQL, `db.t3.medium`, gp3 20GB, 최대 100GB      |
| Redis       | `cache.t4g.medium` 2대, Primary 1 + Replica 1   |
| MSK         | `kafka.t3.small` Broker 2대, Broker당 EBS 100GiB |

> `eks_version`의 기본값은 `null`입니다. 별도 버전을 지정하지 않으면 생성 시점의 AWS 기본 지원 버전이 사용됩니다.

---

## 패키지 구조
```text
infra-dev/
├── argocd/
│   ├── apps/
│   │   ├── ai-service-dev.yaml
│   │   ├── assembly-service-dev.yaml
│   │   ├── backend-app.yaml
│   │   ├── elastic-stack-app.yaml
│   │   ├── frontend-app.yaml
│   │   ├── ingress-app.yaml
│   │   └── quality-service-app.yaml
│   └── root-dev.yaml                           # App of Apps Root Application
│
├── k8s/
│   ├── ai-service/
│   │   ├── api-deployment.yaml
│   │   ├── worker-deployment.yaml
│   │   ├── service.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   │
│   ├── assembly-service/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   │
│   ├── backend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   │
│   ├── frontend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   │
│   ├── ingress/
│   │   ├── frontend-ingress.yaml
│   │   ├── backend-ingress.yaml
│   │   ├── assembly-service-ingress.yaml
│   │   ├── quality-service-ingress.yaml
│   │   ├── ai-service-ingress.yaml
│   │   └── kustomization.yaml
│   │
│   ├── quality-service/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   │
│   └── platform/
│       ├── argocd/
│       │   ├── ingress.yaml
│       │   └── values.yaml
│       │
│       ├── elastic-stack/
│       │   ├── logstash-image/
│       │   │   ├── Dockerfile
│       │   │   ├── config/
│       │   │   └── pipeline/
│       │   │
│       │   └── manifests/
│       │       ├── 01-elasticsearch.yaml
│       │       ├── 02-kibana.yaml
│       │       ├── 03-logstash-serviceaccount.yaml
│       │       ├── 04-logstash-deployment.yaml
│       │       └── 05-kibana-ingress.yaml
│       │
│       └── kafbat/
│           ├── kafbat-ingress.yaml
│           ├── kafbat-msk-policy.json
│           ├── kafbat-portforward-rbac.yaml
│           ├── kafbat-trust-policy.json
│           └── kafbat-values.yaml
│
├── scripts/
│   ├── dev-up.ps1
│   ├── dev-down.ps1
│   ├── up_Mon.ps1
│   ├── down_Fri.ps1
│   └── *.bat
│
├── terraform/
│   ├── versions.tf                         # Terraform 및 Provider 버전
│   ├── provider.tf                         # AWS Provider
│   ├── backend.tf                          # S3 Backend 및 DynamoDB Lock
│   ├── variables.tf
│   ├── outputs.tf
│   ├── eks.tf                              # EKS, Node Group, Add-on, OIDC
│   ├── rds.tf                              # RDS MySQL
│   ├── elasticache.tf                      # Redis
│   ├── msk.tf                              # MSK 및 Kafka Topic
│   ├── security_group.tf
│   ├── route53_acm.tf
│   ├── backend-irsa.tf
│   ├── assembly-irsa.tf
│   ├── logstash-irsa.tf
│   └── iam_policy_lbc.json
│
├── .gitignore
└── README.md
```

---

## 실행 방법

### 1. 사전 요구사항

* Terraform 1.5 이상
* AWS CLI, kubectl, Git
* PowerShell 5.1 이상 또는 PowerShell 7
* AWS Profile `aims-terraform`
* 기존 VPC, Public/Private Subnet
* Terraform Backend용 S3 Bucket과 DynamoDB Table
* ECR Repository, Route 53 Hosted Zone
* Argo CD와 AWS Load Balancer Controller

```bash
aws configure --profile aims-terraform
aws sts get-caller-identity --profile aims-terraform
```

### 2. Terraform 변수 설정

환경별 값은 Git에 커밋하지 않는 `terraform.tfvars`에 작성합니다.

```hcl
my_ip = "xxxxxxxx/32"
vpc_id = "vpc-xxxxxxxxxxxxxxxxx"

# ALB 생성 후 Route 53 Alias 연결 시 입력
alb_dns_name = "xxxxxxxx.ap-northeast-2.elb.amazonaws.com"
alb_zone_id  = "XXXXXXXXXXXXXX"
```

### 3. Terraform 적용

```bash
cd terraform
terraform fmt
terraform init
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Plan에서 예상하지 않은 RDS, MSK, Redis 또는 IAM 리소스의 삭제·재생성이 없는지 확인합니다.

### 4. EKS 연결

```bash
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name aims-dev-eks \
  --profile aims-terraform

kubectl get nodes -o wide
```

### 5. Namespace 및 Secret 준비

```bash
kubectl create namespace aims-project
kubectl create namespace platform
```

Secret 매니페스트는 저장소에 포함하지 않습니다.

* `backend-rds-secret`
* `assembly-service-secret`
* `ai-service-secret` 선택
* `quality-service-runtime-secret` 선택

필요한 Key는 각 애플리케이션의 환경 변수 정의를 기준으로 생성하고, Secret 값은 Git에 커밋하지 않습니다.

### 6. Argo CD Root Application 적용

```bash
kubectl apply -f argocd/root-dev.yaml

kubectl get applications -n platform
kubectl get pods -n aims-project
kubectl get pods -n platform
kubectl get ingress -A
```

> Terraform은 AWS Load Balancer Controller의 IAM Role과 Policy를 생성하지만 Controller 자체는 별도로 설치해야 합니다. Argo CD 설치 파일도 현재 저장소에 포함되어 있지 않습니다.

---

## 이미지 배포 방식

각 서비스의 `kustomization.yaml`에서 ECR 이미지 태그를 관리합니다.

```yaml
images:
  - name: <ECR_REPOSITORY>/aims/backend
    newName: <ECR_REPOSITORY>/aims/backend
    newTag: dev-<COMMIT_SHA>
```

1. 애플리케이션 저장소에서 Docker Image를 빌드합니다.
2. Image를 Amazon ECR에 Push합니다.
3. 인프라 저장소 `dev` 브랜치의 `newTag`를 변경합니다.
4. 변경 사항을 Push합니다.
5. Argo CD가 변경을 감지해 Deployment를 갱신합니다.

---

## 운영 명령어

```bash
# 전체 리소스 확인
kubectl get pods,svc,ingress -n aims-project

# Rollout 확인
kubectl rollout status deployment/backend -n aims-project
kubectl rollout status deployment/assembly-service -n aims-project
kubectl rollout status deployment/quality-service -n aims-project
kubectl rollout status deployment/ai-service-api -n aims-project

# 로그 확인
kubectl logs deployment/backend -n aims-project --tail=200
kubectl logs deployment/ai-service-api -n aims-project --tail=200

# Argo CD 확인
kubectl get applications -n platform
kubectl describe application aims-dev-root -n platform

```

---

## 브랜치 및 배포 정책

* 개발 배포 브랜치: `dev`
* Argo CD Auto Sync: 활성화
* Resource Prune: 활성화
* Self Heal: 활성화
* 이미지 태그: `dev-<commit-sha>` 형식 권장

```text
Feature Branch
    → Terraform Plan 또는 Kustomize Render 확인
    → Pull Request Review
    → dev Branch Merge
    → Argo CD Sync 확인
    → Service Health Check 확인
```