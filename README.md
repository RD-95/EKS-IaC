# EKS Infrastructure as Code (IaC)

This repository contains Terraform code to provision a production-ready Amazon EKS (Elastic Kubernetes Service) cluster on AWS from scratch, built step by step. Each component was added incrementally so the infrastructure is easy to understand, debug and extend.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [AWS Services Used](#aws-services-used)
- [Repository Structure](#repository-structure)
- [Step by Step Breakdown](#step-by-step-breakdown)
- [GitHub Actions Pipeline](#github-actions-pipeline)
- [Prerequisites](#prerequisites)
- [How to Deploy](#how-to-deploy)
- [Deployed Application](#deployed-application)
- [Cost Considerations](#cost-considerations)

---

## Architecture Overview

```
us-east-1
└── VPC (10.0.0.0/16)
    ├── Public Subnet AZ-a  (10.0.1.0/24)  ← NAT Gateway, Load Balancers
    ├── Public Subnet AZ-b  (10.0.2.0/24)  ← Load Balancers
    ├── Private Subnet AZ-a (10.0.3.0/24)  ← EKS Worker Nodes
    └── Private Subnet AZ-b (10.0.4.0/24)  ← EKS Worker Nodes
```

Worker nodes sit in private subnets and are never directly reachable from the internet. All outbound traffic from nodes (pulling images, calling AWS APIs) flows through the NAT Gateway. Inbound traffic to applications is handled by an AWS Load Balancer.

---

## AWS Services Used

### 1. Amazon VPC (Virtual Private Cloud)
A VPC is a logically isolated network within AWS that you fully control. All resources in this project live inside a single VPC with CIDR `10.0.0.0/16`, giving 65,536 available IP addresses. DNS hostnames and DNS support are enabled so that EKS nodes can resolve internal AWS service endpoints.

**Why we need it:** Without a VPC, resources would be placed in the default AWS network which is shared, uncontrolled and not suitable for production workloads.

---

### 2. Public Subnets (x2)
Two public subnets are created across two Availability Zones (`us-east-1a` and `us-east-1b`). Resources placed in public subnets can be assigned a public IP address and communicate directly with the internet through the Internet Gateway.

**Why we need them:**
- The NAT Gateway must live in a public subnet
- AWS Load Balancers that serve external traffic must be placed in public subnets
- Spreading across two AZs ensures availability if one AZ has an outage

---

### 3. Private Subnets (x2)
Two private subnets are created, also across two Availability Zones. EKS worker nodes run exclusively in private subnets. They have no public IP addresses and cannot be reached directly from the internet.

**Why we need them:**
- Security: worker nodes are not exposed to the internet
- EKS best practice: nodes should always be private
- Outbound internet access (for pulling images) still works via the NAT Gateway

---

### 4. Internet Gateway (IGW)
The Internet Gateway is attached to the VPC and acts as the bridge between the VPC and the public internet. It is referenced in the public route table so that resources in public subnets can send and receive internet traffic.

**Why we need it:** Without an IGW, nothing in the VPC can reach the internet and nothing from the internet can reach your public resources. The NAT Gateway itself depends on the IGW to function.

---

### 5. NAT Gateway
The NAT (Network Address Translation) Gateway is placed in the first public subnet with an Elastic IP address. It allows resources in private subnets to initiate outbound connections to the internet (e.g. pulling Docker images from GHCR or Docker Hub) while blocking all inbound connections from the internet.

**Why we need it:** EKS worker nodes in private subnets need to pull container images and communicate with AWS APIs (e.g. EC2, ECR, S3). Without a NAT Gateway, nodes in private subnets have no internet access at all and the cluster cannot function.

> **Cost note:** Only one NAT Gateway is deployed (instead of one per AZ) to reduce costs. This is fine for dev/test but means both private subnets share a single outbound path.

---

### 6. Route Tables
Two route tables are configured:

- **Public Route Table:** Routes `0.0.0.0/0` (all internet traffic) to the Internet Gateway. Associated with both public subnets.
- **Private Route Table:** Routes `0.0.0.0/0` to the NAT Gateway. Associated with both private subnets.

**Why we need them:** Subnets do not automatically know where to send traffic. Route tables define the traffic flow rules. Without them, nodes can't reach the internet and the ELB can't forward traffic to pods.

---

### 7. IAM Roles
Two IAM roles are created:

**EKS Cluster Role**
Assumed by the EKS control plane. Allows AWS to manage network interfaces, security groups, and load balancers on your behalf. Attached policy: `AmazonEKSClusterPolicy`.

**EKS Node Group Role**
Assumed by EC2 worker nodes. Three policies are attached:
- `AmazonEKSWorkerNodePolicy` — allows nodes to register with the cluster
- `AmazonEKS_CNI_Policy` — allows the VPC CNI plugin to assign pod IPs using ENIs
- `AmazonEC2ContainerRegistryReadOnly` — allows nodes to pull images from ECR

**Why we need them:** AWS uses IAM to control what services can do. Without these roles, the control plane cannot manage infrastructure and nodes cannot join the cluster or pull images.

---

### 8. Amazon EKS (Elastic Kubernetes Service) — Control Plane
The EKS cluster provides the managed Kubernetes control plane: the API server, etcd (state store), scheduler, and controller manager. AWS fully manages, patches and operates these components.

Both public and private endpoint access are enabled:
- **Private access:** `kubectl` calls from within the VPC stay on the internal network
- **Public access:** allows running `kubectl` from a local machine

**Why we need it:** This is the brain of the Kubernetes cluster. It tracks what is running where, schedules pods onto nodes, and responds to `kubectl` commands.

---

### 9. EKS Managed Node Group
A managed node group of `t3.micro` EC2 instances is created in the private subnets. These are the worker nodes that actually run your pods.

Configuration:
- `desired = 2`, `min = 1`, `max = 3`
- Placed across two private subnets for availability
- Rolling update with `max_unavailable = 1` — one node replaced at a time

**Why we need it:** The EKS control plane only manages scheduling. The actual container workloads run on EC2 worker nodes. Without a node group there is nowhere for pods to run.

> **Note on t3.micro:** Each t3.micro node supports a maximum of 4 pods due to ENI limits on the instance type. System pods (kube-proxy, aws-node, coredns) consume most of those slots, leaving very limited room for application pods. This is acceptable for learning but consider `t3.small` or `t3.medium` for real workloads.

---

### 10. S3 Bucket (Terraform Remote State)
An S3 bucket stores the `terraform.tfstate` file remotely. Versioning and AES-256 encryption are enabled. All public access is blocked.

**Why we need it:** By default Terraform stores state locally. In a CI/CD pipeline (GitHub Actions), each run starts with a fresh environment and has no access to the previous local state. Without remote state, every pipeline run would try to recreate all resources from scratch, causing conflicts and errors. Remote state ensures all runs share the same view of what already exists.

---

### 11. DynamoDB Table (State Locking)
A DynamoDB table named `eks-iac-tf-lock` is used to lock the Terraform state during runs.

**Why we need it:** If two pipeline runs execute `terraform apply` at the same time, they could both read the same state, make conflicting changes and corrupt it. The DynamoDB lock ensures only one run can modify state at a time. The `PAY_PER_REQUEST` billing mode keeps it within the free tier.

---

### 12. AWS Elastic Load Balancer (ELB)
When a Kubernetes `Service` of type `LoadBalancer` is created, AWS automatically provisions a Classic Load Balancer that routes external HTTP traffic to the pods.

**Why we need it:** EKS pods run on private nodes with no public IPs. The ELB is the public-facing entry point that accepts requests from the internet and forwards them to healthy pods on the correct port.

---

## Repository Structure

```
.
├── bootstrap/                  # Run once locally to create S3 + DynamoDB for state
│   ├── main.tf
│   └── variables.tf
├── modules/
│   ├── vpc/                    # VPC, subnets, IGW, NAT GW, route tables
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── iam/                    # EKS cluster role + node group role
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── eks/                    # EKS control plane
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── node_group/             # EKS managed node group
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── k8s/
│   ├── deployment.yaml         # Diffchecker app deployment
│   └── service.yaml            # LoadBalancer service
├── main.tf                     # Root module wiring all modules together
├── provider.tf                 # AWS provider + S3 backend config
├── outputs.tf                  # Key outputs (VPC ID, cluster endpoint etc.)
└── .github/
    └── workflows/
        └── terraform.yml       # CI/CD pipeline
```

---

## Step by Step Breakdown

| Step | What was added |
|---|---|
| 1 | VPC + public and private subnets |
| 2 | Internet Gateway, NAT Gateway, route tables |
| 3 | IAM roles for EKS cluster and worker nodes |
| 3.5 | Switched to S3 remote backend to fix state drift in CI/CD |
| 4 | EKS control plane |
| 5 | EKS managed node group |
| 6 | Kubernetes manifests for the diffchecker application |

---

## GitHub Actions Pipeline

The pipeline is defined in `.github/workflows/terraform.yml`.

| Trigger | Behaviour |
|---|---|
| Pull Request to `main` | Runs `terraform plan` and posts the output as a PR comment |
| Manual dispatch → `plan` | Runs plan only |
| Manual dispatch → `apply` | Runs `terraform apply -auto-approve` |
| Manual dispatch → `destroy` | Runs `terraform destroy -auto-approve` |

### Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured (`aws configure`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed

---

## How to Deploy

### Step 1 — Bootstrap remote state (run once locally)

```bash
git clone https://github.com/RD-95/EKS-IaC.git
cd EKS-IaC/bootstrap
terraform init
terraform apply
```

### Step 2 — Deploy infrastructure via GitHub Actions

Go to your repo → **Actions → Terraform → Run workflow → apply**

This provisions the VPC, subnets, NAT Gateway, IAM roles, EKS cluster and node group.

Takes approximately 15-20 minutes in total.

### Step 3 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-cluster
kubectl get nodes
```

You should see 2 nodes in `Ready` state.

### Step 4 — Deploy the application

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl get svc diffchecker
```

The `EXTERNAL-IP` column will show the ELB hostname after 1-2 minutes.

### Destroy everything

Go to **Actions → Terraform → Run workflow → destroy**

---

## Deployed Application

The **diffchecker** application is pulled from the public GitHub Container Registry package:

```
ghcr.io/rd-95/diffchecker:latest
```

It runs as 2 replicas across the private worker nodes and is exposed via an AWS Classic Load Balancer on port 80, forwarding to the container on port 5000.

---

## Cost Considerations

| Resource | Approx. Cost |
|---|---|
| EKS Control Plane | ~$0.10/hr (~$72/month) |
| NAT Gateway | ~$0.045/hr + data transfer |
| EC2 t3.micro nodes (x2) | Free tier: 750 hrs/month per account (first 12 months) |
| S3 + DynamoDB (state) | Free tier eligible |
| Classic Load Balancer | ~$0.025/hr |

> **Always run `terraform destroy` when not using the cluster to avoid unnecessary charges.**
