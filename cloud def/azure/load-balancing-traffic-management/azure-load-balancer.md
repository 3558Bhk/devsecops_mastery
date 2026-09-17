# Azure Load Balancer — Interview Questions

> **Cloud:** Azure · **Category:** Load Balancing & Traffic Management · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Azure Load Balancers are ARM JSON (`Microsoft.Network/loadBalancers`) with frontends, backend pools, rules, and probes.

```json
{
  "type": "Microsoft.Network/loadBalancers",
  "apiVersion": "2023-04-01",
  "name": "myLB",
  "sku": { "name": "Standard" },
  "properties": {
    "frontendIPConfigurations": [{ "name": "fe", "properties": { "publicIPAddress": { "id": "/subscriptions/<sub>/.../publicIPAddresses/pip" } } }],
    "backendAddressPools": [{ "name": "pool1" }],
    "probes": [{ "name": "http", "properties": { "protocol": "Tcp", "port": 80 } }],
    "loadBalancingRules": [{
      "name": "http",
      "properties": {
        "frontendIPConfiguration": { "id": "[resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations','myLB','fe')]" },
        "backendAddressPool": { "id": "[resourceId('Microsoft.Network/loadBalancers/backendAddressPools','myLB','pool1')]" },
        "protocol": "Tcp", "frontendPort": 80, "backendPort": 80
      }
    }]
  }
}
```

**Key fields:** `sku` (Standard/Basic) · `frontendIPConfigurations` · `backendAddressPools` · `probes` · `loadBalancingRules` (`frontendPort`→`backendPort`) · `inboundNatRules` (per-VM NAT) · `outboundRules` (SNAT).


## Case A — Basic

**A1. What is Azure Load Balancer?**
**Answer:** A Layer 4 (TCP/UDP) load balancer that distributes traffic to backend VMs/VMSS, providing high availability, health probes, and SNAT for outbound — available in **Basic** and **Standard** SKUs.

**A2. What OSI layer does Azure Load Balancer operate at?**
**Answer:** **Layer 4** (transport) — it routes by IP/port, not HTTP content (unlike Application Gateway, which is L7).

**A3. What are the two configurations of Azure Load Balancer?**
**Answer:** **Public** (fronts internet traffic) and **Internal** (for private, intra-VNet traffic).

**A4. What are the main components?**
**Answer:** **Frontend IP** (the LB's IP), **backend pool** (target VMs/VMSS/IPs), **health probes**, **load-balancing rules** (frontend→backend port mapping), and optional **inbound NAT rules** and **outbound rules**.

**A5. What is a backend pool?**
**Answer:** The set of resources (VM NICs, VMSS instances, or IP addresses) that receive traffic from the load balancer.

**A6. What is a health probe?**
**Answer:** A check (TCP, HTTP, or HTTPS) that the LB runs against backends to determine health; only healthy backends receive traffic.

**A7. What is a load-balancing rule?**
**Answer:** Maps a frontend IP/port to a backend port (e.g., frontend 80 → backend 8080), with the health probe and session persistence settings.

**A8. What is session persistence (sticky sessions)?**
**Answer:** Keeps a client's traffic on the same backend VM (via 5-tuple hash, source-IP, or source-IP+protocol) — useful for stateful apps.

**A9. What is the difference between Azure Load Balancer (L4) and Application Gateway (L7)?**
**Answer:** LB = TCP/UDP, high throughput, low latency, no HTTP inspection. App Gateway = HTTP/HTTPS with path/host routing, TLS offload, WAF, cookie affinity. Combine them: LB in front of App Gateway for scale.

**A10. What is the difference between Basic and Standard SKU?**
**Answer:** **Standard** = supports availability zones, backend pools up to 1,000 instances, HTTPS probes, multiple frontends, HA ports, and outbound rules. **Basic** = limited (single availability set, 300 instances, no zone support, being retired for many scenarios). Use Standard.

**A11. What is SNAT and outbound rules in Azure Load Balancer?**
**Answer:** The LB provides **Source NAT** for outbound internet traffic from backend VMs (translating private IPs to the LB's public IP). **Outbound rules** control which frontend IP and ports are used, and port allocation.

**A12. Does Azure Load Balancer preserve the client's source IP?**
**Answer:** For **inbound** data-path traffic, yes — the backend sees the client's real IP (the LB doesn't NAT inbound data traffic). For **outbound**, it SNATs (backend IP → LB public IP).

**A13. What is a floating IP (Direct Server Return)?**
**Answer:** A mode where the LB doesn't rewrite the destination IP/port — the backend sees the original frontend IP, enabling scenarios like SQL Always On listener and HA ports.

**A14. What are HA ports?**
**Answer:** A load-balancing rule on **all ports** (single rule for any port) — used for NVAs (firewalls) so the LB passes all traffic without per-port rules.

**A15. What is Azure Load Balancer's availability model?**
**Answer:** Standard LB is **zone-redundant** by default (spans AZs) and can be **zonal**; it's highly available with a 99.99% SLA for the data path.

---

## Case B — Advanced (Senior)

**B1. Explain the load-balancing distribution algorithm (5-tuple hash) and how it affects session affinity.**
**Answer:** The Standard LB hashes the **5-tuple (source IP, source port, dest IP, dest port, protocol)** to pick a backend. Changing the default (e.g., to source-IP affinity) keeps a client pinned to one backend. The default 5-tuple spreads traffic well but the **same client's new connections may land on different backends** — configure session persistence if the app needs stickiness.

**B2. How does Azure Load Balancer handle health probes (TCP vs HTTP vs HTTPS) and what are the probe gotchas?**
**Answer:** Probes test backend health on a configurable port/interval/threshold. **NSGs must allow probe traffic** (the `AzureLoadBalancer` service tag is allowed by default rules). Gotchas: probe port must match the backend's listening port (or a dedicated probe port), probe path must return 200, and probe frequency/threshold tuning avoids flapping.

**B3. Why do you need both an inbound rule and NSG allow for client traffic, and how does the data path differ from the probe path?**
**Answer:** **Probes** come from Azure's platform (allow `AzureLoadBalancer`). **Client data** passes through the LB with the **client's source IP preserved**, so the backend NSG must allow the **client IPs** on the service port — a frequent misconfiguration ("LB is healthy but users get no response").

**B4. What is SNAT port exhaustion and how do you design around it (outbound rules, NAT gateway)?**
**Answer:** Each LB public IP provides ~64k SNAT ports; many concurrent outbound connections can **exhaust** them, causing intermittent outbound failures. Mitigate: more **frontend IPs** in the outbound rule, allocate ports per-VM (standard LB outbound rules), or use a dedicated **NAT Gateway** (which scales SNAT ports better). Monitor SNAT connection metrics.

**B5. Explain HA ports + floating IP for NVA (firewall) load balancing.**
**Answer:** An NVA (e.g., firewall VM) needs **all ports** forwarded transparently. **HA ports** creates one rule for all ports; **floating IP** lets the backend see the original destination IP (no DNAT), so the firewall receives packets with the original client destination. This enables active-active/passive firewall designs with the LB in front.

**B6. How do you build a zone-redundant vs zonal load balancer, and when?**
**Answer:** **Zone-redundant** (default): one frontend IP served from all AZs — survives an AZ failure. **Zonal**: frontend pinned to one AZ. Use zone-redundant for general HA; zonal for latency-optimized or AZ-affinity designs. Backends should span the same AZs to avoid cross-AZ imbalance.

**B7. What is the recommended architecture for a multi-tier web app with Azure Load Balancer (L4) + Application Gateway (L7)?**
**Answer:** Internet → **App Gateway/WAF** (L7 routing, TLS offload) → **internal LB** (L4) → web tier → internal LB → app tier → DB. The L4 LB adds scale/HA behind the L7 gateway and between tiers; App Gateway handles routing/WAF. This is the standard "LB in front of App GW (or behind)" composite.

**B8. How do you monitor Azure Load Balancer (metrics, logs, alerts)?**
**Answer:** Metrics: **Data Path Availability** (key health metric), **ByteCount/PacketCount**, **SNAT Connection Count**, **Used SNAT Ports**, **Health Probe Status**, **VipAvailability**. Enable **diagnostics logs** (LoadBalancerProbeHealthStatus, LoadBalancerAlertEvent) to Log Analytics; alert on Data Path Availability drops and SNAT exhaustion.

**B9. Compare Azure Load Balancer vs Application Gateway vs Traffic Manager vs Front Door.**
**Answer:** **LB** = regional L4 (TCP/UDP), high throughput. **App Gateway** = regional L7 with path/host routing, TLS, WAF. **Traffic Manager** = global **DNS-based** routing (no data-path proxying). **Front Door** = global L7 with anycast, CDN, WAF, URL routing. Choose by layer + scope (regional vs global).

**B10. What are the scale limits of Azure Load Balancer (backend pool, rules, throughput)?**
**Answer:** Standard LB: **1,000 backend instances**, many rules, frontend IPs; throughput scales with the platform (no fixed cap but governed by IP limits and rules). For >1,000 instances, use multiple LBs or scale units. Check current limits for rules/frontends per LB.

**B11. How does Azure Load Balancer integrate with VMSS (autoscaling backends)?**
**Answer:** Add the **VMSS** to the backend pool; as instances scale in/out, the LB automatically includes new instances (probe health gates traffic). Use a **health probe + LB rule**, and the VMSS's overprovisioning/custom scaling with the LB provides elastic, healthy capacity.

**B12. What is the relationship between Azure Load Balancer and availability sets/zones for HA?**
**Answer:** Backends should be spread across **fault/update domains** (availability set) or **availability zones** so the LB has healthy targets during maintenance/failures. Zone-redundant LB + zone-distributed backends = best HA. The LB itself is highly available (SLA 99.99% data path for Standard).

---

## Case C — Scenario

**C1. Scenario:** A web app on 5 VMs needs to handle HTTPS traffic with high availability and automatic failover.
**Question:** Design the load balancing.
**Answer:** **Public Standard Load Balancer** (zone-redundant) with a frontend IP, backend pool = the 5 VMs (across AZs/availability set), **HTTPS health probe** (or TCP 443), and a **load-balancing rule** 443→443. Add **session persistence** if needed, NSG allows for probes + client traffic, and monitor Data Path Availability. (For TLS offload/path routing, use App Gateway instead/in front.)

**C2. Scenario:** Users get intermittent outbound failures from backend VMs during peak hours, but inbound works fine.
**Question:** Diagnose and fix.
**Answer:** Likely **SNAT port exhaustion** — outbound connections exhausted the LB's SNAT ports. Fix: add **more frontend IPs** to the outbound rule, use **outbound rules with per-VM port allocation**, or deploy a **NAT Gateway** for outbound. Monitor **Used SNAT Ports / SNAT Connection Count** and alert before exhaustion.

**C3. Scenario:** The load balancer health probe shows "degraded" for one VM; the app on that VM is actually fine.
**Question:** Diagnose.
**Answer:** Check the **probe config**: wrong port (app listens on 8080, probe on 80), probe **path** returning non-200, or the VM's **NSG blocking the `AzureLoadBalancer` probe** traffic. Also check probe interval/threshold causing flapping. Fix the probe settings or NSG rule, then confirm probe status recovers.

**C4. Scenario:** You need to load balance an active-active firewall (NVA) pair that must see the original destination IP.
**Question:** Which LB features?
**Answer:** **Standard LB with HA ports** (a single rule for all ports) + **floating IP (DSR)** so the NVAs receive packets with the **original destination IP** preserved — enabling transparent firewall behavior. Deploy the pair behind the LB (active-active) or with a failover mechanism, and ensure symmetric return routing.

**C5. Scenario:** A stateful app requires that a user's requests always hit the same VM during their session.
**Question:** Configure it.
**Answer:** Set **session persistence** on the load-balancing rule to **Client IP** (source-IP affinity) or Client IP + protocol — the LB then hashes on the client IP, pinning the user to one backend. Caveat: this can imbalance load behind NATs/proxies where many users share one IP; consider app-level sessions instead.

**C6. Scenario:** You must route traffic to different backend ports (frontend 80 → backend 8080) and also expose RDP to specific VMs directly.
**Question:** Which LB components do you use?
**Answer:** **Load-balancing rule** for the 80→8080 mapping (with probe + backend pool). For direct RDP, use **inbound NAT rules** (map a frontend port, e.g., 33891, to a specific VM's 3389) — distinct from load-balancing rules. Both use the same frontend IP.
