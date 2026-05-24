# April 2026 Bootcamp — ECS 2-Tier Infrastructure

Terraform configuration for a production-style **2-tier web application** on AWS: a FastAPI (or similar) app running on **ECS Fargate** behind an **Application Load Balancer**, with a **PostgreSQL RDS** backend.

All resources live in a single flat Terraform root module under `infra/`. There are no nested modules — connections between pieces are expressed through **resource references** (`aws_vpc.this.id`, `aws_security_group.alb_sg.id`, etc.).

---

## High-Level Architecture

```mermaid
flowchart TB
    subgraph Internet["🌐 Internet"]
        Users["Users / Browsers"]
    end

    subgraph DNS["Route 53 + ACM  (route53.tf)"]
        R53["Hosted Zone<br/><code>2tierapp.{domain}</code>"]
        ACM["ACM Certificate<br/>DNS validation"]
    end

    subgraph Public["Public Subnets  (vpc.tf)"]
        IGW["Internet Gateway"]
        NAT["NAT Gateway"]
        ALB["Application Load Balancer<br/>(alb.tf)"]
    end

    subgraph Private["Private Subnets  (vpc.tf)"]
        ECS["ECS Fargate Service<br/>2 tasks · port 8000<br/>(ecs.tf)"]
    end

    subgraph Data["RDS Subnets  (vpc.tf)"]
        RDS["PostgreSQL RDS<br/>(rds.tf)"]
    end

    subgraph Support["Shared Services"]
        ECR["ECR Image<br/>(variables.tf)"]
        SM["Secrets Manager<br/>DB connection string"]
        CW["CloudWatch Logs<br/>(cloudwatch.tf)"]
        IAM["IAM Execution Role<br/>(iam.tf)"]
    end

    Users -->|"HTTPS :443 / HTTP :80"| R53
    R53 -->|"A record alias"| ALB
    ACM -.->|"cert on HTTPS listener"| ALB
    ALB -->|"HTTP :8000"| ECS
    ECS -->|"PostgreSQL :5432"| RDS
    ECS -->|"pull image"| ECR
    ECS -->|"DB_LINK env var"| SM
    SM -->|"stores credentials for"| RDS
    ECS -->|"stdout/stderr"| CW
    ECS -->|"assumes"| IAM
    ECS -->|"outbound via"| NAT
    NAT --> IGW
    ALB --> IGW
    IGW --> Users
```

---

## Terraform File Map

Each `.tf` file owns a slice of the stack. Resources **wire together** by referencing other resources in the same root module.

| File | Responsibility | Key Resources |
|------|----------------|---------------|
| `versions.tf` | Terraform & provider pins, S3 remote state backend | `terraform { backend "s3" ... }` |
| `provider.tf` | AWS provider config & default tags | `provider "aws"` |
| `variables.tf` | Input variables (region, image, domain, ports) | `var.aws_region`, `var.app_image`, … |
| `vpc.tf` | Network foundation | VPC, IGW, NAT, public/private/RDS subnets, route tables |
| `sg.tf` | Layered security groups | `alb_sg` → `ecs_sg` → `rds_sg` |
| `alb.tf` | Public-facing load balancer | ALB, target group, HTTP/HTTPS listeners |
| `route53.tf` | DNS & TLS | Route 53 A record, ACM cert, validation records |
| `ecs.tf` | Compute layer | ECS cluster, task definition, Fargate service |
| `rds.tf` | Data layer | RDS instance, subnet group, Secrets Manager secret |
| `iam.tf` | Task permissions | ECS execution role + ECR/CloudWatch policy |
| `cloudwatch.tf` | Observability | ECS log group |
| `ecr.tf` | Placeholder | Image URI is supplied via `var.app_image` |
| `output.tf` | Outputs (currently commented out) | — |

---

## How Terraform Pieces Connect

### 1. Network Layer — everything anchors to the VPC

```mermaid
flowchart LR
    VPC["aws_vpc.this<br/>10.0.0.0/16"]

    VPC --> IGW["aws_internet_gateway.this"]
    VPC --> PUB1["public_subnet_1<br/>10.0.3.0/24"]
    VPC --> PUB2["public_subnet_2<br/>10.0.4.0/24"]
    VPC --> PRIV1["private_subnet_1<br/>10.0.1.0/24"]
    VPC --> PRIV2["private_subnet_2<br/>10.0.2.0/24"]
    VPC --> RDS1["rds_subnet_1<br/>10.0.5.0/24"]
    VPC --> RDS2["rds_subnet_2<br/>10.0.6.0/24"]

    PUB1 --> NAT["aws_nat_gateway"]
    NAT --> PRIV_RT["private route table<br/>0.0.0.0/0 → NAT"]
    IGW --> PUB_RT["public route table<br/>0.0.0.0/0 → IGW"]

    PRIV_RT --> PRIV1 & PRIV2
    PUB_RT --> PUB1 & PUB2
```

**Who uses which subnets:**

| Subnet type | CIDR blocks | Consumed by |
|-------------|-------------|-------------|
| Public | `10.0.3.0/24`, `10.0.4.0/24` | ALB, NAT Gateway |
| Private | `10.0.1.0/24`, `10.0.2.0/24` | ECS Fargate tasks |
| RDS | `10.0.5.0/24`, `10.0.6.0/24` | RDS subnet group |

---

### 2. Security Groups — layered trust chain

Security groups reference each other instead of open CIDR rules, creating a **north-to-south trust chain**:

```mermaid
flowchart LR
    Internet["0.0.0.0/0"] -->|" :80, :443 "| ALB_SG["alb_sg<br/>(sg.tf)"]
    ALB_SG -->|" :8000 "| ECS_SG["ecs_sg<br/>(sg.tf)"]
    ECS_SG -->|" :5432 "| RDS_SG["rds_sg<br/>(sg.tf)"]
```

| Security Group | Attached to | Inbound | Source |
|----------------|-------------|---------|--------|
| `aws_security_group.alb_sg` | ALB | 80, 443 | Internet (`0.0.0.0/0`) |
| `aws_security_group.ecs_sg` | ECS tasks | 8000 | `alb_sg` |
| `aws_security_group.rds_sg` | RDS | 5432 | `ecs_sg` |

All three security groups set `vpc_id = aws_vpc.this.id`.

---

### 3. Load Balancer → ECS — service registration

```mermaid
flowchart TB
    ALB["aws_alb.app"] -->|"subnets"| PUB["public_subnet_1/2"]
    ALB -->|"security_groups"| ALB_SG["alb_sg"]

    TG["aws_alb_target_group.name<br/>port 8000 · target_type=ip"] -->|"vpc_id"| VPC["aws_vpc.this"]

    LIST_HTTP["listener :80"] --> TG
    LIST_HTTPS["listener :443"] --> TG
    LIST_HTTPS -->|"certificate_arn"| CERT["aws_acm_certificate.app_cert"]

    SVC["aws_ecs_service.app_service"] -->|"load_balancer.target_group_arn"| TG
    SVC -->|"network_configuration.subnets"| PRIV["private_subnet_1/2"]
    SVC -->|"network_configuration.security_groups"| ECS_SG["ecs_sg"]
    SVC -->|"task_definition"| TD["aws_ecs_task_definition.service"]
    SVC -->|"cluster"| CLUSTER["aws_ecs_cluster.ecs_cluster"]
```

The target group uses `target_type = "ip"` because Fargate tasks register by **task ENI IP**, not EC2 instance ID.

---

### 4. ECS Task — image, secrets, logs, IAM

```mermaid
flowchart TB
    TD["aws_ecs_task_definition.service"]

    TD -->|"execution_role_arn"| ROLE["aws_iam_role.ecs_task_execution_role"]
    TD -->|"container image"| IMG["var.app_image<br/>(ECR URI)"]
    TD -->|"environment DB_LINK"| SECRET["aws_secretsmanager_secret_version.rds_password"]
    TD -->|"logConfiguration.awslogs-group"| LG["aws_cloudwatch_log_group.ecs_log_group"]

    ROLE -->|"policy attachment"| POL["aws_iam_policy.task_execution_policy"]
    POL -->|"logs:PutLogEvents"| LG
    POL -->|"ecr:*"| ECR["ECR pull permissions"]
```

The task definition injects the full PostgreSQL connection string as the `DB_LINK` environment variable, sourced from Secrets Manager.

---

### 5. RDS + Secrets Manager — data layer

```mermaid
flowchart TB
    PW["random_password.rds_password"] --> RDS["aws_db_instance.this"]
    PW --> SECVER["aws_secretsmanager_secret_version.rds_password"]

    SNG["aws_db_subnet_group.this"] -->|"subnet_ids"| RDS_SUB["rds_subnet_1/2"]
    RDS -->|"db_subnet_group_name"| SNG
    RDS -->|"vpc_security_group_ids"| RDS_SG["rds_sg"]

    RDS -->|"endpoint, port, db_name, username"| SECVER
    SECRET["aws_secretsmanager_secret.rds_password"] --> SECVER

    SECVER -->|"secret_string = postgresql://..."| ECS["ECS task DB_LINK"]
```

---

### 6. DNS & TLS — public hostname to ALB

```mermaid
flowchart LR
    ZONE["data.aws_route53_zone.app"] --> RECORD["aws_route53_record.app_record<br/>2tierapp.{domain}"]
    RECORD -->|"alias → dns_name"| ALB["aws_alb.app"]

    CERT["aws_acm_certificate.app_cert"] --> VALID["aws_route53_record.cert_validation<br/>(for_each validation option)"]
    VALID --> ZONE
    CERT --> LISTENER["aws_alb_listener.https :443"]
    LISTENER --> ALB
```

---

## Full Dependency Graph (Terraform apply order)

Terraform resolves this graph automatically. Arrows show **"depends on"** direction:

```mermaid
flowchart BT
    subgraph Foundation
        VPC["vpc.tf<br/>VPC · subnets · IGW · NAT · routes"]
        CW["cloudwatch.tf<br/>log group"]
        RAND["rds.tf<br/>random_password"]
    end

    subgraph Security
        SG["sg.tf<br/>alb_sg · ecs_sg · rds_sg"]
    end

    subgraph Data
        RDS["rds.tf<br/>subnet group · RDS · secrets"]
    end

    subgraph Edge
        ALB["alb.tf<br/>ALB · target group · listeners"]
        DNS["route53.tf<br/>zone · A record · ACM · validation"]
    end

    subgraph Compute
        IAM["iam.tf<br/>execution role · policy"]
        ECS["ecs.tf<br/>cluster · task def · service"]
    end

    VPC --> SG
    VPC --> ALB
    VPC --> RDS
    SG --> ALB
    SG --> ECS
    SG --> RDS

    RAND --> RDS
    RDS --> ECS

    ALB --> DNS
    ALB --> ECS

    CW --> IAM
    IAM --> ECS

    DNS --> ALB
```

---

## Request & Data Flow

End-to-end path when a user hits the app:

```mermaid
sequenceDiagram
    actor User
    participant R53 as Route 53
    participant ALB as ALB (public)
    participant ECS as ECS Task (private)
    participant RDS as RDS (isolated subnet)

    User->>R53: GET https://2tierapp.{domain}/login
    R53->>ALB: Alias A record
    ALB->>ECS: Forward to target group :8000
    Note over ALB,ECS: Allowed by alb_sg → ecs_sg
    ECS->>RDS: Query via DB_LINK (PostgreSQL :5432)
    Note over ECS,RDS: Allowed by ecs_sg → rds_sg
    RDS-->>ECS: Query result
    ECS-->>ALB: HTTP 200
    ALB-->>User: Response
```

**Outbound from ECS tasks** (e.g. pulling ECR images, writing logs) routes through the **NAT Gateway** in the public subnet, then out via the **Internet Gateway**.

---

## Remote State

State is stored remotely in S3 (configured in `versions.tf`):

| Setting | Value |
|---------|-------|
| Bucket | `state-bucket-879381241087` |
| Key | `april26/ecs/terraform.tfstate` |
| Region | `ap-south-1` |
| Locking | S3 native lockfile (`use_lockfile = true`) |
| Encryption | Enabled |

---

## Variables

| Variable | Default | Used by |
|----------|---------|---------|
| `aws_region` | `ap-south-1` | Provider, subnets, logs |
| `ecs_cluster_name` | `april-2tier-ecs-cluster` | ECS cluster |
| `ecs_task_def` | `april-2tier-taskdef` | Task definition, IAM, log group |
| `ecs_service` | `april-2tier-ecs-service` | ECS service |
| `app_image` | ECR URI (`april-ecs-2tier:1.0`) | Container image |
| `container_name` | `2tier` | Task & service load balancer block |
| `port` | `8000` | Target group, container port, health check |
| `domain` | `livingdevops.org` | Route 53 & ACM |

---

## Deploy

```bash
cd infra

# Initialize backend & providers
terraform init

# Preview changes
terraform plan

# Apply infrastructure
terraform apply
```

### Prerequisites

- AWS credentials with permissions for VPC, ECS, RDS, ALB, Route 53, ACM, IAM, Secrets Manager, and CloudWatch
- An existing **Route 53 hosted zone** for `var.domain`
- A container image pushed to **ECR** (or update `var.app_image`)
- S3 bucket `state-bucket-879381241087` accessible for remote state

---

## File Reference Quick Links

```
infra/
├── versions.tf      # Terraform version, providers, S3 backend
├── provider.tf      # AWS provider (ap-south-1)
├── variables.tf     # All input variables
├── vpc.tf           # VPC, subnets, IGW, NAT, routing
├── sg.tf            # Security groups (ALB → ECS → RDS)
├── alb.tf           # Load balancer, target group, listeners
├── route53.tf       # DNS records, ACM certificate
├── ecs.tf           # ECS cluster, task definition, service
├── rds.tf           # PostgreSQL, secrets, random password
├── iam.tf           # ECS task execution role & policy
├── cloudwatch.tf    # ECS log group
├── ecr.tf           # (placeholder — image via variable)
├── output.tf        # Outputs
└── readme.md        # This file
```

---

## Architecture Summary

| Layer | AWS Service | Terraform file | Network placement |
|-------|-------------|----------------|-------------------|
| DNS / TLS | Route 53, ACM | `route53.tf` | Global / regional |
| Edge | Application Load Balancer | `alb.tf` | Public subnets |
| Compute | ECS Fargate | `ecs.tf` | Private subnets |
| Data | RDS PostgreSQL | `rds.tf` | RDS subnets (no public access) |
| Secrets | Secrets Manager | `rds.tf` | Regional |
| Identity | IAM | `iam.tf` | Regional |
| Observability | CloudWatch Logs | `cloudwatch.tf` | Regional |
| Network | VPC, IGW, NAT | `vpc.tf` | `ap-south-1` |
| Firewall | Security Groups | `sg.tf` | VPC-scoped |

The design follows a classic **2-tier pattern**: the presentation/compute tier (ECS) and the data tier (RDS) are isolated in separate subnets, with traffic entering only through the ALB and database access restricted to ECS tasks via security group references.
