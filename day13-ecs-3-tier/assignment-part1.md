Here are the detailed assignments from Session 13:

---

**Assignment 1 — Deploy Three-Tier App on ECS with Service Connect**

You have already deployed a two-tier app on ECS in the previous session. Now take the same React + Flask + PostgreSQL app from the repository and deploy it as a three-tier architecture on ECS.

Requirements:
- Frontend (React) and Backend (Flask) should run as separate ECS services
- Use Service Connect to enable frontend-to-backend communication using a DNS name within the namespace — not hardcoded IPs or ports
- Backend should connect to PostgreSQL on RDS
- Place your load balancer in front of the frontend service on public subnets
- Backend should be on private subnets, not directly exposed
- Run the database migration job as a separate step before the app starts, not as part of the app container itself
- Use the VPC Terraform module from class to provision networking

This is given as a self-driven project. All the code is in the repository. The goal is for you to wire it together end to end.

---

**Assignment 2 — Terraform Loops and Conditionals (Mandatory before next class)**

Go through Akhilesh's blog posts on `count`, `for_each`, and ternary conditions on livingdevops.com. These are the handwritten posts, not the AI-generated ones — check the T1, T2, T4 tags.

After reading, do the following hands-on exercises:

- Create a Terraform config that takes a list of subnet CIDRs as input and creates that many subnets using `count`
- Use `count.index` to map CIDR and availability zone from the list
- Write a ternary condition that creates a NAT gateway only if a variable `need_nat_gateway` is true, and creates either 1 or N NAT gateways based on a second variable `single_nat_gateway`
- Write a `locals` block that defines two ECS services (frontend and backend) as a list of maps with name, image, port, and environment variables

The goal is to be comfortable reading and writing these patterns before the next class because the ECS templating session will build directly on top of this.

---

**Assignment 3 — Terraform Module Versioning Best Practices (Research + Notes)**

This is a common senior-level interview question. Research and write your own notes on the following:

Understand the difference between these two version constraint styles inside a Terraform module:

```hcl
# Style 1
required_version = ">= 1.3.0"

# Style 2
required_version = "~> 1.3"
```

Your notes should cover:
- What does `~>` (pessimistic constraint) actually mean for major vs minor versions
- Why you should never hardcode an exact version like `= 1.3.0` inside a reusable module
- Why the version constraint inside a module is only for compatibility signaling, not for initialization — initialization always happens at the root level
- When should you use `>= x.x` vs `~> x.x` and what are the tradeoffs
- Same applies to the AWS provider version inside your module

If somebody asks you in an interview how you handle versioning when building internal Terraform modules for your team, you should be able to answer this confidently with real reasoning.

---

**Assignment 4 — AWS Organizations and Multi-Account Access (Research)**

Watch at least one YouTube video on AWS Organizations. After watching, make notes covering:

- What is the root account and why you never use it for daily work
- How member accounts are created and organized under an AWS Organization
- What SCPs (Service Control Policies) are and how they restrict permissions at the account level
- How engineers in a company get access to multiple AWS accounts without creating IAM users in each account — specifically how IAM roles, SSO, and assume role work together
- What STS AssumeRole is and when Terraform uses it in the backend config to access a state bucket in a different account

This directly connects to what was shown in class about the `role_arn` option in the S3 backend config. You should understand why that option exists and when you would need it in a real company setup.

---

**Assignment 5 — Multi-Environment Terraform Setup (Hands-on)**

Replicate the environment separation approach shown in class. Your folder structure should look like this:

```
infra/
  modules/
    network/
      network.tf
      variables.tf
      outputs.tf
      versions.tf
  vars/
    dev.tfvars
    prod.tfvars
    dev.backend.hcl
    prod.backend.hcl
  network.tf
  variables.tf
  versions.tf
```

Requirements:
- The `dev.tfvars` should create a VPC with 2 public and 2 private subnets, single NAT gateway, smaller naming prefix
- The `prod.tfvars` should create a VPC with 2 public and 2 private subnets, one NAT per subnet, different naming prefix
- Backend config files should point to different state file keys for each environment
- Run `terraform init -backend-config=vars/dev.backend.hcl` and `terraform plan -var-file=vars/dev.tfvars` successfully for both environments from the same code base

The goal is to prove that the exact same Terraform code deploys differently based on which var file and backend config you pass at runtime — no code duplication.

---

**Assignment 6 — Contribute to the VPC Module**

The VPC Terraform module is available in Akhilesh's public GitHub repository. Clone it, read through the full code, and make at least one improvement. A good starting point that was mentioned in class is adding proper `region` variable support since it is currently missing.

Once done, raise a pull request. Even if it is small, the goal is to practice the contribution workflow and understand how public modules are structured and maintained over time.

---

Come to the next class having done at least Assignments 2 and 5. The next session will directly build on the looping and multi-environment concepts so going in without that foundation will make it hard to follow.