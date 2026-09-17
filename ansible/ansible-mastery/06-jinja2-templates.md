# 06 — Jinja2 Templates, Filters & Lookups (Config Generation at Scale)

> ⏱️ **Time to complete: ~2.5 hrs** — read 30 min · practice 90 min · self-quiz 30 min
> 📦 **Covers:** template module + `validate` · the Jinja2 filter toolbox (defaults, collection surgery, crypto, time, ternary) · tests · lookups vs query · generating fleet-wide config from inventory · environment-aware templates with mandatory/no_log · escaping (`{{ '{{' }}`, `!unsafe`) & gotchas

> **Interview framing:** At SDE-3 you're expected to *generate correct config for hundreds of hosts from one template*, safely — with validation, defaults, and escaping. Jinja2 is where playbooks become programming.

---

## 1. Template basics — `template` module + `.j2` convention

```yaml
- name: Render nginx config
  ansible.builtin.template:
    src: nginx.conf.j2              # templates/<role>/nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    mode: "0644"
    owner: root
    validate: "nginx -t -c %s"      # %s → temp file; fail BEFORE deploying bad config
    backup: true                    # keep .bak of previous version
  notify: Reload nginx
```

Template syntax:

```jinja
{{ expression }}          {# value substitution #}
{% if env == "prod" %}    {# statement/control flow #}
worker_processes auto;
{% else %}
worker_processes 2;
{% endif %}

{% for upstream in groups['api'] %}
server {{ hostvars[upstream]['ansible_host'] }}:8080;
{% endfor %}

{# comment — never shipped #}
```

**`validate:` is the single highest-signal line you can write** in a template task. Say: *"A typo in nginx.conf can take down a fleet at reload. Validation catches it at task time, on the target, before the file is live."*

---

## 2. The filter toolbox (grouped by what you actually do)

### Defaults & safety
```jinja
{{ db_host | default('localhost') }}              {%# value if undefined #}
{{ db_host | default('localhost', true) }}        {%# ALSO replace false/empty — the (true) matters! #}
{{ required_var | mandatory }}                    {%# fail with clear error if undefined #}
{{ port | int(5432) }}                            {%# coerce with fallback #}
{{ enabled | bool }}
```

### Collections surgery (the interview favorites)
```jinja
{{ groups['web'] | join(', ') }}
{{ users | map(attribute='name') | list }}
{{ servers | selectattr('env', 'equalto', 'prod') | list }}
{{ servers | rejectattr('drained') | map(attribute='host') | list }}
{{ a_list | union(b_list) | unique | sort }}
{{ dict1 | combine(dict2, recursive=true) }}
{{ my_dict | dict2items }}         {{ my_items | items2dict }}
{{ nested | flatten }}
{{ "a,b,c".split(',') }}
{{ groups['web'] | map('extract', hostvars, 'ansible_host') | list }}
```

### Strings, encoding, crypto
```jinja
{{ "host-{}-{}".format(idx, env) }}
{{ path | regex_replace('^/srv', '/data') }}
{{ text | regex_search('listen\s+(\d+)', '\1') }}
{{ payload | to_json }} {{ payload | from_json }}
{{ secret | b64encode }} {{ token | b64decode }}
{{ password | password_hash('sha512', my_salt) }}       {%# /etc/shadow entries #}
{{ blob | hash('sha256') }}
{{ "10 GiB" | human_to_bytes }}
```

### Time & randomness
```jinja
{{ '%Y-%m-%d' | strftime }}                       {%# on the control node! #}
{{ result.ts | to_datetime('%Y-%m-%d %H:%M:%S') }}
{{ ['a','b'] | random }} {{ 50 | random }}        {%# — not idempotent, know why you use it #}
```

### Conditionals inline
```jinja
mode: {{ is_prod | ternary('0640', '0644') }}
```

### Tests (used with `is`)
```jinja
{% if cfg is defined and cfg is not none %}
{% if ver is version('2.0', '>=') %}
{% if path is match('^/etc/') %}
{% if my_list is contains('nginx') %}
{% if result is succeeded %}
```

---

## 3. Lookups — pulling data from OUTSIDE Ansible at control-node time

```yaml
vars:
  ssh_key:   "{{ lookup('ansible.builtin.file', '~/.ssh/id_ed25519.pub') }}"   # read local file
  api_token: "{{ lookup('ansible.builtin.env', 'API_TOKEN') }}"                # env var
  kernel:    "{{ lookup('ansible.builtin.pipe', 'uname -r') }}"                # run a command
  changelog: "{{ lookup('ansible.builtin.url', 'https://releases.internal/notes') }}"
  db_conf:   "{{ lookup('ansible.builtin.ini', 'port', section='db', file='app.ini') }}"
  csv_row:   "{{ lookup('ansible.builtin.csvfile', 'web1', col=1, delimiter=',', file='hosts.csv') }}"
  vault_secret: "{{ lookup('community.hashi_vault.hashi_vault', 'secret=kv/app/db_pass') }}"
  ssm_param: "{{ lookup('amazon.aws.aws_ssm', '/prod/db/password', region='us-east-1') }}"
```

**`lookup` vs `query`** (asked to check depth):

```jinja
{{ lookup('fileglob', 'configs/*') }}   → string, comma-joined when multiple
{{ query('fileglob', 'configs/*') }}    → proper LIST
{{ q('fileglob', 'configs/*') }}        → same as query (shorthand)
```

> 💬 **Say:** *"Lookups execute **on the control node**, at templating time — not on the target, not idempotent, not check-mode-safe. That's why secrets from Vault/SSM lookups flow through vars instead of tasks. If I need target-side files I use `slurp` or `command`."*

### 🎬 SCENARIO — generate `/etc/hosts` from the whole inventory

```jinja
# templates/hosts.j2
127.0.0.1   localhost
{% for host in groups['all'] %}
{{ hostvars[host]['ansible_host'] }}  {{ host }}.internal  {{ host }}
{% endfor %}
```

```yaml
- name: Distribute consistent /etc/hosts
  ansible.builtin.template:
    src: hosts.j2
    dest: /etc/hosts
    mode: "0644"
```

One template → identical fleet-wide name resolution. This exact task (generating config *from inventory*) is the canonical Jinja2 interview exercise.

### 🎬 SCENARIO — environment-aware app config with guarded secrets

```jinja
# templates/app.env.j2
APP_ENV={{ env }}
DB_HOST={{ db.host | default('localhost') }}
DB_PORT={{ db.port | default(5432) }}
{% if env == "prod" %}
WORKERS={{ ansible_facts['processor_count'] * 2 + 1 }}
LOG_LEVEL=warn
TIMEOUT_S=30
{% else %}
WORKERS=2
LOG_LEVEL=debug
TIMEOUT_S=300
RELOAD=true
{% endif %}
API_TOKEN={{ api_token | mandatory }}     {# refuse to render without it #}
```

```yaml
- ansible.builtin.template:
    src: app.env.j2
    dest: /opt/api/app.env
    mode: "0600"                # secrets inside → tight perms
    validate: "/opt/api/bin/config-check %s"
  no_log: true                  # don't leak rendered content to stdout (file 09)
  notify: Restart api
```

**The four production guards in one task: `mandatory` (fail loud), `validate` (fail early), `mode 0600` (contain), `no_log` (don't echo).** Presenting this quartet is an instant senior signal.

---

## 4. Escaping & gotchas (where templates bite)

```jinja
{# when you LITERALLY need braces (e.g. generating Ansible/Helm templates): #}
{{ '{{' }} .Values.image {{ '}}' }}

{# mark data as never-templated: #}
raw_cert: !unsafe "{{ not_jinja_I_promise }}"

{# whitespace control: #}
{% if x %}
{{- value -}}     {# trims whitespace/newlines around the expression #}
{% endif %}
```

Gotchas interviewers love:
- **Undefined behaves like `false` in `{% if %}`** — `{% if not cfg %}` hides typos. Use `cfg is defined` + `mandatory` for anything critical.
- `default('x')` does NOT replace empty strings/`false` — `default('x', true)` does.
- Facts in templates come from the **target host**, lookups from the **control node** — mixing timezones/dirs is a classic bug.
- `hash_behaviour=replace` (default) means whole-dict replacement across var sources — merge explicitly with `combine(recursive=true)`.

---

## 5. 🎤 SDE-3 Interview Corner

**Q1. `template` vs `copy`?**
> `copy` ships bytes verbatim (idempotent via checksum). `template` renders Jinja2 from vars/facts first. Use `copy` with `content:` for short static content; `template` when any value must adapt per host/env.

**Q2. How do you ensure a rendered config won't kill the service on reload?**
> `validate:` runs a target-side check command on a temp file before the real write; combined with handlers, a bad config fails the task and no restart ever happens. For services lacking validation commands: `nginx -t`-style wrappers, or CI-side rendering + lint.

**Q3. Generate an nginx upstream block for all `web` hosts using Jinja2.**
> The `groups['web']` + `hostvars[...]` `for` loop above. Add: filter to reachable/active hosts with `selectattr`, sort for stable config (avoid pointless reloads from order changes), and pin via `| sort`.

**Q4. What's the difference between a lookup, a filter, and a test?**
> Filter: transform a value (`x | upper`). Test: boolean predicate (`x is defined`). Lookup: fetch external data at control-node time (`lookup('file', ...)`). All three are Jinja2 extension points you can write yourself (file 14).

**Q5. Why did your template render empty vars without error?**
> Undefined defaults silently inside `{{ }}` when guarded by `if`, or `default()` masking a typo. Policy: `mandatory` for required inputs; lint rule `name[template]`/`jinja[invalid]`; and `--check --diff` to eyeball rendered output before apply.

**Q6. Is templating idempotent?**
> The module is — it compares rendered output checksum to the file. Non-idempotent *inputs* (timestamps, `random`) cause perpetual `changed` → spurious handler runs. Keep templates deterministic; inject timestamps via `set_fact` only where drift-reporting accepts it.

---

## ⚠️ Common pitfalls

- `dest` filename without `.j2` on `src` mismatch confusion — convention: `src: foo.conf.j2`, `dest: /etc/foo.conf`.
- Forgetting `mode:` → config files world-readable with secrets inside.
- Jinja inside `when:` — you write **bare expressions** there (`when: x == 1`), NOT `{{ }}`.
- Loops in templates over **unordered dicts** → config churn between runs; sort everything.
- Trusting `default()` to catch typos (it "works" and hides real bugs).

---

**➡️ Next:** [07 — Roles & Collections](07-roles-collections.md)
