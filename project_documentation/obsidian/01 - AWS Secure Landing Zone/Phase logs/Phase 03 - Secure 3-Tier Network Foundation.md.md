# Phase 3 — Secure 3-Tier Network Foundation

## 🎯 Overview

This phase builds the VPC networking layer for the `network` member account (622532143366) — the foundation everything in Phase 4 (Compute) and beyond gets deployed into. The design follows a classic **3-tier architecture** (public / private-app / private-data), spread across 3 Availability Zones for high availability, with layered security (routing + security groups) enforcing which tier can talk to which.

**What was built:**

- 1 VPC with 9 subnets across 3 AZs × 3 tiers
- Internet Gateway + 3 NAT Gateways (one per AZ) for outbound-only private access
- 4 route tables enforcing tier-appropriate traffic paths
- 3 Security Groups implementing a strict trust chain: Internet → ALB → App → DB
- Terraform outputs exposing every ID needed by later phases

## 🏗️ Deploying into a member account

This is the first phase deployed **outside the management account**. Terraform authenticates as `terraform-deployer` (management account), then uses an `assume_role` block to switch identity into `OrganizationAccountAccessRole` inside the `network` account — the same role AWS auto-creates in every member account (from Phase 2.4). This means all resources in this phase physically live in the `network` account, not management, while still using one consistent set of deployer credentials — avoiding the long-lived-credential sprawl the SCPs from Phase 2.5 are designed to prevent.

## 📐 Architecture

```
                    Internet
                        │
                        ▼
              ┌───────────────────┐
              │  Internet Gateway  │
              └───────────────────┘
                        │
   ┌────────────────────┼────────────────────┐
   ▼                    ▼                    ▼
┌─────────┐        ┌─────────┐         ┌─────────┐
│Public   │        │Public   │         │Public   │      10.0.1-3.0/24
│Subnet A │        │Subnet B │         │Subnet C │      (eu-west-1a/b/c)
│NAT + EIP│        │NAT + EIP│         │NAT + EIP│
│ALB-SG   │        │ALB-SG   │         │ALB-SG   │
└────┬────┘        └────┬────┘         └────┬────┘
     │ NAT route        │ NAT route         │ NAT route
     ▼                  ▼                   ▼
┌─────────┐        ┌─────────┐         ┌─────────┐
│Priv-App │        │Priv-App │         │Priv-App │      10.0.4-6.0/24
│Subnet A │        │Subnet B │         │Subnet C │
│App-SG   │        │App-SG   │         │App-SG   │
└────┬────┘        └────┬────┘         └────┬────┘
     │ local route (no NAT/IGW)             │
     ▼                  ▼                   ▼
┌─────────┐        ┌─────────┐         ┌─────────┐
│Priv-Data│        │Priv-Data│         │Priv-Data│      10.0.7-9.0/24
│Subnet A │        │Subnet B │         │Subnet C │
│DB-SG    │        │DB-SG    │         │DB-SG    │
└─────────┘        └─────────┘         └─────────┘
```

**Design rationale — why 3 tiers, not the classic "presentation/app/data":** The public tier's occupant isn't a traditional web server — it's the **ALB itself**, which serves the "public-facing" role a presentation layer historically played. The private-app tier runs the actual application (ECS Fargate, built in Phase 4), and private-data is reserved for RDS. This is a standard, modern variant of 3-tier design for containerized workloads.

## 🛠️ Implementation

### VPC and subnets

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}
```

**Sizing decision:** `/16` (65,536 addresses) chosen over a tighter range like `/24` to leave room for dev/staging/prod growth across all three tiers — a `/28` would only yield 11 usable IPs per subnet after AWS's 5 reserved addresses, far too small for a growing platform.

9 subnets carved out in `/24` blocks (256 addresses each, 251 usable):

|Tier|AZ-a|AZ-b|AZ-c|
|---|---|---|---|
|Public|10.0.1.0/24|10.0.2.0/24|10.0.3.0/24|
|Private-app|10.0.4.0/24|10.0.5.0/24|10.0.6.0/24|
|Private-data|10.0.7.0/24|10.0.8.0/24|10.0.9.0/24|

Only public subnets set `map_public_ip_on_launch = true` — private tiers never receive a public IP.

### Internet Gateway — one per VPC

```hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}
```

A single IGW serves all 3 public subnets — it is not an AZ-scoped resource. Public subnets reach it via a shared route table entry (`0.0.0.0/0 → igw`).

### NAT Gateways — one per AZ, unlike the IGW

```hcl
resource "aws_eip" "eip_a" { domain = "vpc" }

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.eip_a.id
  subnet_id     = aws_subnet.public_subnet_a.id
}
```

Unlike the IGW, **NAT Gateways are AZ-bound resources** — a single shared NAT would create a cross-AZ single point of failure. 3 NAT Gateways (one per AZ), each with its own Elastic IP, deployed in the public subnet of their respective AZ. Each private-app subnet routes outbound traffic to _its own AZ's_ NAT Gateway, never a neighboring one — preserving true AZ independence.

### Route tables — 4 total, not 9

|Route table|Scope|Destination for 0.0.0.0/0|
|---|---|---|
|`public_rt`|Shared by all 3 public subnets|IGW|
|`private_app_rt_a/b/c`|One per AZ (3 tables)|That AZ's own NAT Gateway|
|`private_data_rt`|Shared by all 3 private-data subnets|_(no route — see below)_|

**Why private-data needs no explicit route:** every VPC automatically includes an implicit local route (`10.0.0.0/16 → local`) on every route table. This alone lets private-app and private-data subnets reach each other within the VPC — no NAT, no IGW required. The private-data route table exists only to formally associate those subnets and intentionally provide **no path to the internet at all**.

**Why public needs only 1 table but private-app needs 3:** the public route table's target (the IGW) is a single shared resource — one table suffices. Private-app's target (the NAT Gateway) is AZ-specific — each AZ's subnet must route to its own local NAT, requiring 3 separate tables.

### Security Groups — the real access-control layer

Routing determines what traffic is _physically possible_; security groups determine what's _actually permitted_. Even though the VPC's implicit local route lets private-app and private-data subnets reach each other, security groups are what actually stop an attacker who compromises an app-tier task from reaching the database — the SCP-style "possible vs. permitted" distinction, applied at the network layer.

**ALB-SG** — the internet-facing edge:

```hcl
ingress { from_port = 443; to_port = 443; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
egress  { from_port = 0;   to_port = 0;   protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }
```

**App-SG** — trusts only the ALB, never the raw internet:

```hcl
ingress {
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  security_groups = [aws_security_group.alb_sg.id]   # source = an SG, not a CIDR
}
egress { to DB port (5432), scoped to private-data CIDRs only }
egress { to 443, scoped to 0.0.0.0/0 — for outbound calls via NAT (image pulls, external APIs) }
```

**DB-SG** — trusts only the App tier, and needs no egress at all:

```hcl
ingress {
  from_port       = 5432
  to_port         = 5432
  protocol        = "tcp"
  security_groups = [aws_security_group.app_sg.id]
}
# no egress block — SGs are stateful, so the response to an allowed
# inbound request is automatically permitted back out
```

**Key concept validated through this build:** the `from_port`/`to_port` fields in _any_ SG rule — ingress or egress — always describe the **destination's listening port**, never a "source port" on the caller's own side. The caller's actual source port is ephemeral and irrelevant; AWS never asks for it.

**Referencing a security group as a source (not a CIDR)** is the mechanism that makes tier-to-tier trust identity-based rather than IP-based — "only things wearing the ALB-SG can reach here," regardless of what IP they happen to have.

### Outputs

`network/outputs.tf` exposes 6 values consumed by every later phase via `terraform_remote_state`:

```hcl
output "vpc_id"                     { value = aws_vpc.main.id }
output "public_subnet_ids"          { value = [...] }              # list — always consumed as a group
output "private_app_subnets_ids"    { value = [...] }
output "private_data_subnets_ids"   { value = [...] }
output "security_groups_ids" {                                     # map — always consumed by name
  value = {
    alb = aws_security_group.alb_sg.id
    app = aws_security_group.app_sg.id
    db  = aws_security_group.db_sg.id
  }
}
```

**Design rule applied — list vs. map:** subnets are exposed as **lists** because downstream code always consumes all of them together (e.g., an ALB's `subnets` argument wants every public subnet, not one specifically). Security groups are exposed as a **map** because downstream code picks exactly one at a time, by role, in different resources (the ALB needs only `alb`, the ECS Service needs only `app`). The consumption pattern — "always together" vs. "one at a time by name" — determined the data structure, not stylistic preference.

## 🚀 Deployment

```bash
cd infra/network
terraform init
terraform apply
```

Result: ~31 resources created (1 VPC, 1 IGW, 9 subnets, 4 route tables, 9 route table associations, 3 EIPs, 3 NAT Gateways, 3 Security Groups) plus the 6 outputs written to remote state.

## 📸 Evidence

![[6 4.png]]
 _1 — Route tables list (7 total, includes default VPC's main table)._

![[7 3.png]] _2 — Security Groups list (5 total, includes both VPCs' default SGs)._

![[8 3.png]] _3 — `terraform state list`, network/._

![[1 3.png]] _4 — VPCs list, atlas-fintech-network-vpc 10.0.0.0/16._

![[2 3.png]] _5 — Subnets list (12 total, includes default VPC's 3)._

![[3 3.png]] _6 — Internet gateways (2, includes default VPC's)._

![[4 3.png]] _7 — NAT gateways (3, one per AZ)._

![[5 3.png]] _8 — Elastic IPs (4, 3 tied to the NAT gateways)._

## 💡 Lessons Learned

1. **Terraform resource ordering in the file is irrelevant to AWS's actual creation order.** Terraform builds a dependency graph from resource _references_, not file position — a resource can be written before or after something it depends on, and Terraform still creates things in the correct order.
    
2. **NAT Gateway vs. Internet Gateway have fundamentally different AZ scoping**, and this single distinction explains the entire 1-vs-3 route table asymmetry between the public and private-app tiers.
    
3. **The classic 3-tier "presentation/app/data" model maps differently onto modern containerized architecture** — the ALB fills the public tier's functional role without being a traditional web server, which is a deliberate, common variant rather than a deviation from the pattern.
    
4. **Cross-account Terraform via `assume_role`** keeps a single deployer identity working across every member account without creating IAM users per-account — directly reinforcing the "no long-lived credentials in member accounts" principle established via SCPs in Phase 2.
    

## ✅ Completion Status

|Component|Status|
|---|---|
|VPC + 9 subnets (3 tiers × 3 AZs)|✅ Complete|
|Internet Gateway|✅ Complete|
|3 NAT Gateways + EIPs (1 per AZ)|✅ Complete|
|4 route tables + all associations|✅ Complete|
|3 Security Groups (ALB → App → DB trust chain)|✅ Complete|
|Terraform outputs (list vs. map pattern)|✅ Complete|
|Deployed to `network` account via `assume_role`|✅ Complete|

**Next:** Phase 4 (Compute) builds ECS Fargate, ALB resources, and the ECS Service directly on top of this network foundation, consuming these exact outputs via `terraform_remote_state`.

## 📚 References

- [Amazon VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)
- [NAT Gateways](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [Security Groups vs. Network ACLs](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-comparison.html)
- [Terraform aws_security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)