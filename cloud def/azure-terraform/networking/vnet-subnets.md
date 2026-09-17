# Terraform VNet & Subnets (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is an Azure Virtual Network (VNet) in Terraform?**
**Answer:** `azurerm_virtual_network` — an isolated network with an address space, the foundation for subnets and connectivity.

**A2. How do you declare a VNet?**
**Answer:** `resource "azurerm_virtual_network" "vnet" { name = ... ; resource_group_name = ... ; location = ... ; address_space = ["10.0.0.0/16"] }`.

**A3. What is a subnet in Terraform?**
**Answer:** `azurerm_subnet` — a CIDR range within the VNet's address space, used to place resources (VMs, app services, private endpoints).

**A4. How do you declare a subnet?**
**Answer:** `resource "azurerm_subnet" "web" { name = "web" ; resource_group_name = ... ; virtual_network_name = azurerm_virtual_network.vnet.name ; address_prefixes = ["10.0.1.0/24"] }`.

**A5. What is the difference between a VNet and a subnet?**
**Answer:** A VNet is the top-level network (address space); subnets divide it into smaller CIDR ranges for isolation and routing.

**A6. What is a route table in Azure?**
**Answer:** `azurerm_route_table` + `azurerm_route` — user-defined routes (UDRs) overriding default routing, associated to subnets via `azurerm_subnet_route_table_association`.

**A7. What is the default route in Azure?**
**Answer:** Azure provides system routes (internet, VNet-to-VNet, load balancer); you add UDRs to force traffic through appliances (firewall/NVA) or block routes.

**A8. What is VNet peering in Terraform?**
**Answer:** `azurerm_virtual_network_peering` on each side connects two VNets with low-latency private traffic, including across subscriptions/regions.

**A9. What is a NAT Gateway in Azure?**
**Answer:** `azurerm_nat_gateway` + `azurerm_nat_gateway_public_ip_association` gives outbound internet connectivity for subnets without per-VM public IPs.

**A10. How do you associate a subnet with a NAT gateway?**
**Answer:** `azurerm_subnet_nat_gateway_association` linking the subnet to the NAT gateway.

**A11. What is a private endpoint?**
**Answer:** `azurerm_private_endpoint` — a private IP in your VNet connecting to a PaaS service (storage, SQL, Key Vault) privately.

**A12. What is a service endpoint?**
**Answer:** `azurerm_subnet` `service_endpoints` (e.g. `Microsoft.Storage`) — routes subnet traffic to a service over the Azure backbone without a public endpoint.

**A13. What is DNS resolution in a VNet?**
**Answer:** Azure-provided DNS by default, or custom DNS servers set via `dns_servers` on the VNet.

**A14. How do you get available Azure regions/address space dynamically?**
**Answer:** `data "azurerm_subscription"`/`data "azurerm_locations"`, and compute subnet CIDRs with `cidrsubnet()`.

**A15. What is a network security group and how is it associated?**
**Answer:** `azurerm_network_security_group` with rules, associated to subnets (`azurerm_subnet_network_security_group_association`) or NICs.

## Case B — Advanced / Senior

**B1. How do you design a hub-and-spoke topology in Terraform?**
**Answer:** A hub VNet (firewall/gateway/NVA, shared services) peered with multiple spoke VNets; spokes route 0.0.0.0/0 through the hub firewall via UDRs, and the hub may connect on-prem via VPN/ExpressRoute.

**B2. How do you peer VNets across subscriptions with Terraform?**
**Answer:** In each subscription, create the peering (`azurerm_virtual_network_peering` on both sides, one referencing the remote VNet's resource ID via an aliased provider), allowing forwarding/gateway transit as needed.

**B3. What are the considerations for overlapping address spaces in peering?**
**Answer:** Peered VNets must not overlap; overlapping spaces fail or route unpredictably. Plan CIDR allocation centrally (IPAM or a shared registry) before creating new VNets.

**B4. How do you build a reusable VNet module?**
**Answer:** Inputs: address space, subnet map (names → prefixes, with NSG/service endpoint flags), region; outputs: VNet ID, subnet IDs keyed by name, NSG IDs. Use `for_each` for subnets and `cidrsubnet` for derived CIDRs.

**B5. What is route propagation and how does it interact with UDRs?**
**Answer:** Route tables can disable BGP route propagation (e.g. from a VPN gateway) to force specific paths; system routes still apply where no UDR matches.

**B6. How do you implement forced tunneling to a firewall?**
**Answer:** A UDR with `0.0.0.0/0 → next_hop_type = "VirtualAppliance"` (or firewall private IP) on spoke subnets, so all internet-bound traffic egresses through the hub firewall.

**B7. What is the difference between service endpoints and private endpoints?**
**Answer:** Service endpoints extend subnet-to-service connectivity (no private IP in your VNet, still a public endpoint on the service). Private endpoints give the service a private IP inside your VNet and fully remove public exposure. Private endpoints are the more secure default.

**B8. How do you manage DNS for private endpoints?**
**Answer:** Create private DNS zones (`azurerm_private_dns_zone` + `azurerm_private_dns_zone_virtual_network_link`) for the service, and A records pointing at the private endpoint's IP, so clients resolve to the private address.

**B9. How do you subnet for PaaS with delegation?**
**Answer:** Subnet `delegation` blocks (e.g. `Microsoft.Web/serverFarms`, `Microsoft.ContainerInstance`) dedicate subnets to specific Azure services — required for app service/ACI integration.

**B10. What is the `address_prefixes` vs legacy `address_prefix`?**
**Answer:** `address_prefixes` (list) is the current attribute; `address_prefix` is deprecated. Use the list form to avoid warnings.

**B11. How do you avoid recreation churn when changing subnets?**
**Answer:** Subnet address changes force recreation of the subnet and its resources. Use stable keys with `for_each`, and don't reorder/insert into lists feeding `count`.

**B12. How do you integrate Azure Firewall into a Terraform VNet design?**
**Answer:** Deploy the firewall in the hub's `AzureFirewallSubnet`, route spokes to it via UDRs, add `azurerm_firewall_network_rule_collection`/application rules, and enable diagnostics.

## Case C — Scenario

**C1. Two VNets can't talk after peering — what do you check?**
**Answer:** Both peering objects exist with correct remote IDs and `allow_virtual_network_access = true`, no overlapping address spaces, NSGs allowing traffic, and route tables not blocking. Re-plan to confirm both sides applied.

**C2. You need to force all spoke egress through a central firewall.**
**Answer:** Add a UDR on each spoke subnet pointing 0.0.0.0/0 at the firewall (VirtualAppliance next hop or Azure Firewall), ensure the firewall has a public IP/rules, and verify with a connectivity test.

**C3. A PaaS service must be reachable only from your VNet, not the internet.**
**Answer:** Use a private endpoint (with a private DNS zone for resolution) or service endpoints + service firewall rules to restrict the public endpoint. Disable public network access on the service.

**C4. You must connect on-premises networks to your VNet.**
**Answer:** Deploy a VPN gateway (`azurerm_virtual_network_gateway`) in a `GatewaySubnet` (or ExpressRoute), configure the local network gateway + connection, and set up routing/NSG rules accordingly.

**C5. A subnet change in a plan shows it will destroy VMs inside it.**
**Answer:** The subnet address is changing (immutable). Revert if possible; otherwise stand up the new subnet, move workloads, then remove the old one — never change the prefix in place on a live subnet.

**C6. You're migrating from service endpoints to private endpoints for storage.**
**Answer:** Create the private endpoint + private DNS zone, repoint clients to the private DNS name, update the storage account to disable public access, then remove service endpoint config once traffic flows privately.
