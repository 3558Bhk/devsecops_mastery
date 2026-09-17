# 🅰️ Ansible Mastery — SDE-3 Interview Edition

> **Complete Ansible, taught through scenarios.** One folder, flat files — every topic is its own numbered `.md` (`01-fundamentals.md` … `18-last-minute-revision.md`) with concepts → real-world scenario playbooks → SDE-3 interview Q&A → common pitfalls, plus a time budget in every header.
>
> The goal is not "I know Ansible syntax". The goal is: *"Give me a broken fleet, a deployment problem, or a design question — and I can reason about it like someone who has run production automation."*

> 📇 **[INDEX.md](INDEX.md) — one-page index of every file: exact topics covered + time per file + fast routes by available time.** Start there if you're navigating.
>
> 🎤 **[ansible-interview-questions/](../ansible-interview-questions/00-index.md) — companion folder: 321 topic-wise interview questions (🟢 basic → 🔴 advanced), each with model answers, scenario drills, and behavioral prep.**
>
> ✍️ **Want to learn by writing?** [File 00 — The Playbook Mastery Ladder](00-playbook-writing-guide.md): 12 small graded steps from your first 3-line play to writing a zero-downtime deploy from memory (~14 h, runs alongside the theory files).

---

## 🧭 START HERE — What this repo is & how to use it

### What is this?

A **self-contained study course** for cracking Ansible questions in SDE-3 / senior interviews. It covers **the complete tool** — from architecture internals to AWX/AAP operations — but every topic is taught the way interviews actually probe it: **"here's a production situation, solve it."**

### Who is it for?

Engineers who already know Linux + SSH basics and some YAML. No prior Ansible needed; the course builds from first contact to production-scale design.

### How every file is structured

```
⏱️ time + coverage header   →  know what you're committing to before you start
Concepts                    →  the mental model, briefly
🎬 SCENARIO blocks          →  real production situations + full playbooks, line-by-line "why"
🎤 Interview Corner         →  the exact questions asked, with model answers
⚠️ Pitfalls                 →  the mistakes that expose juniors
```

### The 4-step method per file

1. **Read** the concepts (don't skip the "Interview Corner" — read it *before* practicing so you know what matters).
2. **Type & run** every playbook in your lab (typing ≠ reading — this is where retention happens).
3. **Re-run everything once** and check it reports `changed=0` — internalize idempotency physically.
4. **Explain out loud** the scenario's talking points as if to an interviewer. If you can't narrate it, you don't own it yet.

### ⏳ Total time budget

| Pace | Duration |
|---|---|
| Full course + labs | **≈ 40 focused hours** |
| Aggressive (3–4 h/day) | ~2 weeks |
| Sustainable (2 h/day) | ~3 weeks |
| Relaxed (1 h/day + weekends) | ~4–5 weeks |
| **Last-minute rescue** | File 18 only: 45 min full pass / 10 min ⚡ sections |

Per-file times are on each file's header and in the table below — they assume read + lab practice + self-quiz.

### If you only have ONE day →  [18 — Last-Minute Revision](18-last-minute-revision.md). Then come back and go deep on 04, 08, 10, 16.

---

## 🗺️ The Learning Path (times included — do them in order)

| # | File | Topic | ⏱️ Time | Weight |
|---|------|-------|---------|--------|
| 01 | [fundamentals](01-fundamentals.md) | Architecture, agentless model, idempotency, ansible.cfg, ad-hoc | **~2.5 h** | 🔥🔥🔥 |
| 02 | [inventory & ad-hoc](02-inventory-adhoc.md) | INI/YAML inventories, groups, patterns, host/group vars | **~1.5 h** | 🔥🔥🔥 |
| 03 | [playbook basics](03-playbook-basics.md) | Plays, tasks, modules, handlers, register, check mode | **~2.5 h** | 🔥🔥🔥 |
| 04 | [variables & facts](04-variables-facts.md) | Variable precedence (the #1 question), facts, magic vars | **~2 h** | 🔥🔥🔥 |
| 05 | [control flow](05-control-flow.md) | when, loops, tags, import vs include, delegate_to, run_once | **~2 h** | 🔥🔥🔥 |
| 06 | [Jinja2 templates](06-jinja2-templates.md) | Filters, tests, lookups, validate, config generation at scale | **~2.5 h** | 🔥🔥 |
| 07 | [roles & collections](07-roles-collections.md) | Role anatomy, defaults vs vars, Galaxy, FQCN, role deps | **~2.5 h** | 🔥🔥🔥 |
| 08 | [error handling](08-error-handling.md) | block/rescue/always, failed_when, rollbacks | **~2 h** | 🔥🔥🔥 (senior signal) |
| 09 | [vault & secrets](09-vault-secrets.md) | Vault IDs, encrypt_string, no_log, external secret managers | **~1.5 h** | 🔥🔥 |
| 10 | [rolling deploys & async](10-rolling-deploys-async.md) | serial, strategy, canary, async/poll, zero-downtime deploys | **~3 h** | 🔥🔥🔥 (the SDE-3 scenario) |
| 11 | [performance tuning](11-performance-tuning.md) | forks, pipelining, fact caching, profiling 500-host runs | **~1.5 h** | 🔥🔥 |
| 12 | [cloud & dynamic inventory](12-cloud-dynamic-inventory.md) | aws_ec2 plugin, provisioning, add_host pattern, Terraform bridge | **~2 h** | 🔥🔥 |
| 13 | [Docker, K8s & CI/CD](13-docker-k8s-cicd.md) | docker/k8s modules, Ansible in pipelines, Ansible vs GitOps | **~2 h** | 🔥🔥🔥 |
| 14 | [custom plugins & testing](14-custom-plugins-testing.md) | Custom modules, filters, callbacks, ansible-lint, Molecule | **~3 h** | 🔥🔥 |
| 15 | [AWX / Ansible Automation Platform](15-awx-aap.md) | Job templates, surveys, workflows, RBAC, execution environments | **~1.5 h** | 🔥🔥 |
| 16 | [Scenario Cookbook](16-scenario-cookbook.md) | **6 end-to-end production projects** (LEMP, blue-green, patching, DR…) | **~5 h** | 🔥🔥🔥 |
| 17 | [Interview Cheat Sheet](17-interview-cheatsheet.md) | 55 rapid-fire Q&A, comparison tables, revision card | **~1.5 h** (20 min/rep) | 🔥🔥🔥 |
| 18 | [Last-Minute Revision](18-last-minute-revision.md) | Everything compressed: snippets, killer answers, traps, day-of checklist | **45 min** (10 min/day-of) | 🚨 final pass |

**Cumulative milestone markers:** after 04 (~8.5 h) you can handle 70% of questions · after 10 (~22 h) you can handle the scenario rounds · after 16 (~37 h) you can lead the design discussion.

---

## 🧪 Set up your lab first (you cannot master this by reading)

### Option A — Vagrant (recommended: real VMs, real SSH)

```ruby
# Vagrantfile — 1 controller + 3 nodes
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  (1..3).each do |i|
    config.vm.define "node#{i}" do |n|
      n.vm.hostname = "node#{i}"
      n.vm.network "private_network", ip: "192.168.56.#{10 + i}"
    end
  end
end
```

```bash
vagrant up
ssh-keygen -t ed25519 -f ~/.vagrant_key -N ''
for i in 1 2 3; do
  sshpass -p vagrant ssh-copy-id -i ~/.vagrant_key vagrant@192.168.56.$((10+i))
done
```

### Option B — Docker (lightweight, fast)

```bash
docker network create ansinet
for n in node1 node2 node3; do
  docker run -d --name $n --hostname $n --network ansinet \
    -e ROOT_PASSWORD=root rastasheep/ubuntu-sshd
done
# controller container (or your laptop) -> docker network connect ansinet <controller>
ssh-keygen -t ed25519 -N '' -f ~/.ansible_lab
docker cp ~/.ansible_lab.pub node1:/tmp/ && docker exec node1 sh -c \
  'mkdir -p /root/.ssh && cat /tmp/*.pub >> /root/.ssh/authorized_keys'
# repeat for node2, node3
```

### Verify

```bash
ansible all -i "node1,node2,node3," -m ping       # note the trailing comma!
```

---

## 🎯 How SDE-3 interviews actually test Ansible

1. **Scenario design questions** — *"How would you roll out a new version to 200 web servers with zero downtime?"* → Files 08, 10, 16.
2. **Debug/troubleshooting questions** — *"This playbook works for 5 hosts but times out at 500. What do you check?"* → Files 11, 04.
3. **Precedence & internals** — *"If I pass `-e`, does it beat `set_fact`? Why?"* → File 04.
4. **Code review on the whiteboard** — they show a bad playbook; you find the 6 anti-patterns (shell instead of modules, missing names, secrets in plaintext, no handlers, no check-mode safety, no serial). → File 17.
5. **System design** — design a self-service automation platform → Files 13, 15.

**Rule of thumb:** at SDE-3 level, every answer should include the words *idempotency, blast radius, rollback, and observability* somewhere. That's what separates seniors from task-runners.

---

## ✅ Progress checklist

- [ ] Lab running, `ansible all -m ping` green
- [ ] I can explain the push model & how modules execute over SSH
- [ ] I can recite variable precedence top and bottom 3 levels without notes
- [ ] I can write a role blindfolded (defaults/vars/handlers/meta)
- [ ] I can design a zero-downtime deploy with serial + health checks + rollback
- [ ] I can set up dynamic inventory for AWS from memory
- [ ] I know import vs include cold
- [ ] I've read the Cookbook (16) end-to-end at least twice
- [ ] I can answer all 55 rapid-fire questions in file 17 in under 20 minutes
- [ ] I've done at least one full 10-minute pass of file 18 on interview morning
