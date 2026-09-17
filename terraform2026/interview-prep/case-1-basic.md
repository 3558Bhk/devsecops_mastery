# Case 1 — Basic Questions (bullet Q&A)

> Level: **basic → basic → basic** (freshers / first interviews)
> Format: question → spaced answer → next question
> Use the "flow" notes where an answer explains a sequence of steps.

---

### Q1. What is Terraform, in one line?

- Terraform is an **Infrastructure as Code (IaC)** tool that lets you define, create, and change cloud resources using simple configuration files (`.tf`), instead of clicking through a portal.

---

### Q2. What does "Infrastructure as Code" actually mean, and why do we do it?

- Infrastructure = servers, databases, networks — declared in **version-controlled code** (Git) like application code.

- Why:
  - **Repeatable** — the same environment can be rebuilt exactly, anywhere.
  - **Reviewable** — changes go through pull requests before touching production.
  - **Auditable** — Git history answers "who changed what, when".
  - **Disposable** — destroy and recreate an environment in minutes.

---

### Q3. What are the four commands in the Terraform loop, and what does each do?

- **`terraform init`** — downloads the providers (plugins that talk to AWS/Azure) and configures the backend (where state is stored).
- **`terraform plan`** — reads your code + current state and prints the proposed changes (create / update / delete) **without doing anything**.
- **`terraform apply`** — performs the plan on the real cloud.
- **`terraform destroy`** — deletes everything Terraform created (reads state, reverses it).

- Flow (the daily loop):
  1. write/edit `.tf` files →
  2. `init` (first time, or after provider changes) →
  3. `plan` → read the diff →
  4. `apply` (only if the diff is what you expect) →
  5. later: `destroy` when the environment is done.

---

### Q4. What is the Terraform state file, and why is it important?

- `terraform.tfstate` is a **record of everything Terraform has created**: resource addresses, their cloud IDs, and attributes.

- Why it matters:
  - It's how Terraform knows what **already exists** (so it can update instead of recreate).
  - It maps your code (e.g. `aws_s3_bucket.web`) to real cloud IDs (e.g. `arn:aws:s3:::my-bucket`).
  - `destroy` only deletes what's in state — so a lost state file = orphaned resources.

- Key habit: state files often contain secrets → never commit them to Git; store them in S3/Azure Storage (a "remote backend").

---

### Q5. What is a provider, and why does Terraform need one?

- A **provider** is a plugin that speaks one cloud's API (e.g. `hashicorp/aws`, `hashicorp/azurerm`).

- Terraform core doesn't know how to create a bucket — the provider translates your `aws_s3_bucket` block into actual API calls.

- You declare providers in the `required_providers` block of the `terraform {}` block and **pin versions** (e.g. `~> 5.0`) so a new provider release can't silently change your infrastructure.

---

### Q6. What is the difference between a `resource` and a `data` source?

- `resource` — something Terraform **creates and manages** (its lifecycle: create/update/destroy).
- `data` — something that **already exists** and Terraform only **reads** (an AMI ID, a VPC someone else made, your account ID).

- Example: `data "aws_ami" "al2023"` looks up the latest Amazon Linux image so you don't hardcode an image ID.

---

### Q7. What are variables, and what are the variable types you use day-to-day?

- `variable` blocks define **inputs** to your configuration — values you can change per environment without editing code.

- Common ones:
  - `string`, `number`, `bool`, `list(string)`, `map(string)`, `object`, `set`.
  - `sensitive = true` — hides the value from `plan`/`apply` output (passwords, tokens).
  - `validation {}` — rejects bad values early (e.g. environment must be `dev`/`staging`/`prod`).

- Values are supplied (priority order): CLI `-var` → `terraform.tfvars` → `*.auto.tfvars` → environment variables → prompt.

---

### Q8. What are outputs, and when do you use them?

- `output` blocks are **the answers Terraform gives you after `apply`**: URLs, ARNs, names, IPs.

- Typical uses:
  - Print the website URL after creating a web app.
  - Feed one module's output into another module's input (module → module wiring).
  - Give operators the exact resource names to check in the console.

- Tip: mark secret-ish outputs `sensitive = true` so they're masked in the CLI.

---

### Q9. What is the difference between `count` and `for_each`?

- `count` — create **N copies** of a resource: `count = 3`. The index is a number (`count.index`).
- `for_each` — create **one per key** in a set or map: `for_each = toset(["web", "api"])`. The key is meaningful (`for_each.key`).

- When to use which:
  - `count` → "three identical web servers".
  - `for_each` → "one per named item" (per subnet, per environment) — because keys are **stable**: deleting item B of 3 doesn't shift B's index to 0.
  - Rule of thumb: prefer `for_each` when identity matters.

---

### Q10. What is a module, and why would you write one?

- A **module** is a folder of `.tf` files with declared inputs (variables), outputs, and resources — a reusable unit.

- Why:
  - **DRY** — write "a VPC with 3 subnets" once, use it in 10 projects.
  - **Abstraction** — the caller sees `vpc_cidr`, not 14 resource blocks.
  - **Sharing** — publish to the registry or a Git repo the team uses.

- Two kinds: **root module** (your project folder) and **child modules** (folders referenced with `source = "./modules/vpc"` or a registry address).

---

### Q11. Local backend vs remote backend — what's the difference, and why does a team need remote?

- **Local backend** — state lives in `terraform.tfstate` on your laptop. Fine for one person learning.

- **Remote backend** (S3 + DynamoDB on AWS, or Azure Storage on Azure) — state lives in the cloud:
  - Everyone's `plan` sees the same current state.
  - **Locking** (DynamoDB table) prevents two people from applying at once (corrupts state otherwise).
  - State survives a laptop crash; can be encrypted and versioned.

- Flow to switch: add a `backend {}` block in `terraform {}`, then `terraform init -migrate-state`.

---

### Q12. What does `terraform plan` show, and what does "idempotency" have to do with it?

- `plan` shows the **diff** between your code and the real world (via state):
  - `+` create, `~` in-place update, `-/+` destroy & recreate, `-` delete.

- **Idempotency** = running `apply` twice in a row: the second run does **nothing** ("No changes. Your infrastructure matches the configuration.").

- Why it matters:
  - Your config describes a *desired state*, not a sequence of commands — Terraform converges on it.
  - A non-idempotent setup (e.g. random values in code, out-of-band changes) shows up as a permanent plan diff — that's a bug to fix, not a thing to live with.

---

### Q13. You made a mistake in your `.tf` file. `terraform validate` passes, but `plan` shows a scary replace. What do you do?

- Read the plan carefully — the scary part is usually `-/+ destroy and then create` on a stateful resource (DB, volume).
- Common causes:
  - Changing an attribute that **forces replacement** (e.g. a table's partition key, an instance type on some resources).
  - A renamed/removed argument making Terraform think it's a new resource.
- What to do:
  1. Revert the change (`git checkout` the file).
  2. Understand which attribute forces replacement (the plan tells you: "forces replacement").
  3. Choose a strategy: accept replacement (with a data-migration plan), or find an attribute that updates in place.
- Rule: **never `apply` a plan you can't explain.**
