# Architecture decisions

## Scope and deployment contract

The tenant entry point creates an organization intermediate root and 11 child groups. Platform ownership is split into Connectivity, Management, Identity, and Security. Application archetypes are Corp, Online, and Local. Sandbox and Decommissioned remain siblings. This tracks the current Microsoft landing-zone hierarchy, including Security and Local, while keeping deployment small.

Greenfield means a prepared Entra directory with empty Azure subscriptions, not a tenant with no billing relationship. No hardcoded tenant or subscription IDs are embedded. The same template can be used in different Azure public-cloud tenants after their own bootstrap.

The default compact layout preserves platform/application subscription isolation with two subscriptions. Supplying all three optional platform subscription IDs places connectivity in its own group and separates the four platform services. Explicit duplicates are rejected before hierarchy creation. Every subscription association represents a move, which can change inherited policies and RBAC; use the scaffold on empty subscriptions.

The Bicep tenant orchestrator embeds modules for tenant hierarchy/association, management-group governance/RBAC, subscription resource groups, and resource-group networking/RBAC. Stable names make repeat deployments target the same resources. No secret, deployment script, third-party service, or private registry is required by the deployed template.

## Networking and WAF tradeoffs

Default hub `10.0.0.0/16`, production `10.10.0.0/16`, nonproduction `10.20.0.0/16`. Each network allocates its first two `/26` ranges for `snet-workload` and `snet-private-endpoints`; the remaining space is reserved. The tenant template and CLI preflight check private IPv4 ranges, overlap, host bits, and prefix lengths before creating the hierarchy. The standalone application template still requires checking overlap against existing networks in the target environment.

Each subnet has a separate NSG with explicit deny-all inbound and outbound rules at priority 4096; future approved allow rules use lower priority numbers. Both subnets disable default outbound access and enable private-endpoint network policies. NSGs are not comprehensive application-layer inspection, and Azure platform traffic semantics still apply.

The hub is a reserved network foundation. It is not an operational transit network: no peering, gateways, firewall, DNS forwarding, or routes are created. This deliberately defers service and traffic charges. For production workloads, add approved connectivity, egress, monitoring, backup, resilience, and service-specific subnet sizing/delegation. Do not deploy services requiring dedicated subnets into the generic subnet without redesign.

Management, Identity, and Security resource groups establish ownership boundaries. They contain no operating service. The identity subscription is for future Azure-hosted identity infrastructure, not the Entra directory itself. Azure ARM templates here do not configure Microsoft Graph objects, groups, Conditional Access, PIM, security defaults, or emergency access users.

WAF alignment: source-controlled repeatable modules and CI support operational excellence; isolated networks and scoped group access support security; omission of idle premium resources supports cost control. Runtime reliability and performance require workload-specific design and are not established by empty VNets. A fully featured ALZ accelerator or AVM deployment is an alternative with a larger policy/service surface and different operational/cost prerequisites.

## Microsoft Learn research

Research used the Azure MCP server's Microsoft Learn search, code-sample search, full-page fetch, WAF guidance, and Bicep schema tools. Schema lookup failed internally for management-group and policy types; Microsoft Learn resource references were used instead. Current compiler schema checks validate the selected APIs.

- [Azure landing zones and platform/application separation](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)
- [Management group design](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups)
- [Tenant deployments with Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-tenant)
- [Deploy to Azure button and scope selection](https://learn.microsoft.com/azure/azure-resource-manager/templates/deploy-to-azure-button)
- [Resource naming rules](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)
- [WAF virtual network guidance](https://learn.microsoft.com/azure/well-architected/service-guides/virtual-network)
- [Default outbound access and private subnets](https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access)
- [Management groups resource schema](https://learn.microsoft.com/azure/templates/microsoft.management/managementgroups)
- [Subscription association schema](https://learn.microsoft.com/azure/templates/microsoft.management/managementgroups/subscriptions)
- [Policy assignment schema](https://learn.microsoft.com/azure/templates/microsoft.authorization/policyassignments)
- [Virtual network schema](https://learn.microsoft.com/azure/templates/microsoft.network/virtualnetworks)
