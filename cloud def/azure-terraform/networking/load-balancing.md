# Terraform Load Balancing (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What load balancing options does Azure offer?**
**Answer:** Azure Load Balancer (L4), Application Gateway (L7), Azure Front Door (global L7), and Traffic Manager (DNS-based).

**A2. What resources make up an Azure Load Balancer in Terraform?**
**Answer:** `azurerm_lb`, `azurerm_lb_backend_address_pool`, `azurerm_lb_probe`, `azurerm_lb_rule`, plus a public IP (`azurerm_public_ip`).

**A3. What is the difference between a public and internal Load Balancer?**
**Answer:** A public LB has a public frontend IP for internet traffic; an internal LB fronts private traffic inside the VNet (e.g. between tiers).

**A4. What is a backend address pool?**
**Answer:** The set of NICs/IPs receiving traffic, referenced by load balancing rules.

**A5. What is a health probe?**
**Answer:** `azurerm_lb_probe` — a TCP/HTTP/HTTPS check determining which backend instances are healthy.

**A6. What is a load balancing rule?**
**Answer:** `azurerm_lb_rule` maps a frontend port to backend ports with protocol and health probe — the core routing config.

**A7. What is Application Gateway in Terraform?**
**Answer:** `azurerm_application_gateway` — an L7 load balancer with path/host routing, TLS termination, and WAF.

**A8. What are App Gateway's key components?**
**Answer:** Frontend IP configs, listeners, backend pools, HTTP settings, probes, and routing rules.

**A9. What is Azure Front Door?**
**Answer:** `azurerm_cdn_frontdoor_*` (or `azurerm_frontdoor`) — a global L7 service with anycast, CDN, WAF, and URL routing across regions.

**A10. What is Traffic Manager?**
**Answer:** `azurerm_traffic_manager_profile` + endpoints — DNS-level routing (priority/weighted/performance) across endpoints.

**A11. How do you attach a VM's NIC to a backend pool?**
**Answer:** `azurerm_network_interface_backend_address_pool_association` linking the NIC to the pool.

**A12. What is a NAT rule on a Load Balancer?**
**Answer:** `azurerm_lb_nat_rule` — maps a frontend port to a specific VM (e.g. SSH to a jumpbox).

**A13. What is a public IP SKU for a Load Balancer?**
**Answer:** `Standard` (required for modern LB features, zone-redundant) vs `Basic`. Use Standard for production.

**A14. What is an outbound rule?**
**Answer:** `azurerm_lb_outbound_rule` configures how backend VMs egress via the LB's frontend IP (SNAT).

**A15. What is a WAF policy?**
**Answer:** `azurerm_web_application_firewall_policy` attached to App Gateway/Front Door to block OWASP threats.

## Case B — Advanced / Senior

**B1. Load Balancer vs Application Gateway vs Front Door vs Traffic Manager — how do you choose?**
**Answer:** LB for L4 (TCP/UDP) regional; App Gateway for L7 + WAF + TLS regional; Front Door for global L7 + CDN + WAF; Traffic Manager for DNS failover/global routing without proxying traffic.

**B2. How do you configure TLS termination on an Application Gateway?**
**Answer:** `frontend_port` 443, a listener with an SSL certificate (from Key Vault or PFX), and HTTP settings routing decrypted traffic to backends over HTTP or re-encrypted HTTPS.

**B3. How do you do path-based routing on App Gateway?**
**Answer:** One listener + multiple `request_routing_rule`s (or a single rule with `url_path_map`) mapping `/api/*`, `/images/*` to different backend pools.

**B4. What is session affinity and when to use it?**
**Answer:** `cookie_based_affinity` on App Gateway (or LB persistence) pins a client to a backend. Use only when the app isn't stateless; it can break scaling.

**B5. How do you integrate a WAF policy with App Gateway in Terraform?**
**Answer:** Create `azurerm_web_application_firewall_policy` with managed rule sets/custom rules, and reference it in the gateway's `waf_configuration`/policy attachment.

**B6. How do you make a Load Balancer zone-redundant and HA?**
**Answer:** Use Standard SKU with `zones` (or zone-redundant frontend) and backend VMs across availability zones, plus health probes so unhealthy zones drop out.

**B7. What is a health probe design best practice?**
**Answer:** Use a dedicated `/health` path that checks dependencies (not just the root page), set realistic intervals/thresholds, and ensure the backend app's firewall allows the probe.

**B8. How do you use a private Application Gateway for internal apps?**
**Answer:** Frontend private IP (internal), listeners on private ports, and DNS (private zone) resolving the app name to the gateway's private IP.

**B9. How does Front Door route traffic across regions and fail over?**
**Answer:** Front Door's global routing + health probes steer traffic to healthy origins; combined with WAF and caching. Terraform defines origin groups, routes, and rules.

**B10. How do you manage certificates from Key Vault for App Gateway?**
**Answer:** `azurerm_key_vault_certificate` storing the cert, a Key Vault access policy/identity for the gateway, and reference the secret ID in the listener — with `key_vault_secret_id`.

**B11. What are the SNAT port exhaustion considerations with a public LB?**
**Answer:** Outbound connections consume SNAT ports on the LB's frontend IP. Use outbound rules with a larger frontend IP pool, NAT gateway, or dedicated outbound IPs for high egress workloads.

**B12. How do you structure a load-balancing module for reuse?**
**Answer:** A module taking inputs (frontend IP, backend NIC/IPs, probes, rules, WAF/settings) emitting the LB/gateway IDs and frontend IP — instantiated per service or environment.

## Case C — Scenario

**C1. An app behind a Load Balancer returns intermittent 5xx and timeouts.**
**Answer:** Check health probes (are backends marked unhealthy?), backend app health, NSG rules allowing probe + traffic ports, and SNAT exhaustion on outbound. Fix probes/rules and verify.

**C2. You need two domains on one Application Gateway with different backends.**
**Answer:** Multi-site listeners (one per hostname, each with its own certificate and routing rule) pointing to the respective backend pools.

**C3. You're migrating from a classic LB to a zone-redundant Standard LB.**
**Answer:** Create the Standard LB + public IP (zone-redundant) + pools/probes/rules, repoint DNS, verify traffic, then decommission the old LB — keeping both during the cutover.

**C4. A WAF is blocking legitimate traffic (false positives).**
**Answer:** Tune the WAF policy: create exclusions or custom rules for the specific pattern, lower the managed rule set to detection mode first, and monitor before enforcing again.

**C5. You need global low-latency routing with automatic failover for a multi-region app.**
**Answer:** Front Door (global L7 + health-based failover) or Traffic Manager (DNS failover). Configure origins/endpoints per region with probes, and test failover by disabling a region.

**C6. Internal services must load-balance over private IPs only.**
**Answer:** Deploy an internal Standard Load Balancer (private frontend IP) with a private DNS name, backend pools of private NICs, and NSG rules scoped to the VNet.
