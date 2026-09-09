# Architecture decisions

## Scope and deployment contract

The tenant entry point creates an organization intermediate root and 11 child groups. Platform ownership is split into Connectivity, Management, Identity, and Security. Application archetypes are Corp, Online, and Local. Sandbox and Decommissioned remain siblings. This tracks the current Microsoft landing-zone hierarchy, including Security and Local, while keeping deployment small.

Greenfield means a prepared Entra directory with empty Azure subscriptions, not a tenant with no billing relationship. No hardcoded tenant or subscription IDs are embedded. The same template can be used in different Azure public-cloud tenants after their own bootstrap.

The default compact layout preserves platform/application subscription isolation with two subscriptions. Supplying all three optional platform subscription IDs places connectivity in its own group and separates the four platform services. Explicit duplicates are rejected before hierarchy creation. Every subscription association represents a move, which can change inherited policies and RBAC; use the scaffold on empty subscriptions.

The Bicep tenant orchestrator embeds modules for tenant hierarchy/association, Entra security groups, management-group governance/RBAC, subscription resource groups, and resource-group networking/RBAC. Stable names make repeat deployments target the same resources. No secret, deployment script, paid runtime service, or private registry is required by the deployed template. Compilation restores Microsoft's public Graph extension package; compiled JSON declares MicrosoftGraph provider version 1.0.0 at the root and in Graph modules, including the root import needed for nested authentication. Templates containing Graph resources use ARM languageVersion 2.0 with symbolic resources.

## Management group IDs and display names

Management group IDs such as `elz-platform` are permanent, directory-unique resource identifiers. Azure permits readable strings; GUIDs are not required. The display name is a separate editable label. Keep `prefix` unchanged after the first deployment: changing it creates different resource IDs and does not rename the existing hierarchy. For a later organizational rename, update the display names in the hierarchy module while preserving its IDs.

A GUID generated once and retained would also be valid. Generating new random IDs on every deployment would create new groups and leave policy/RBAC assignments attached to the old scopes. This scaffold uses predictable, stable IDs so redeployments address the same hierarchy. Use a distinct prefix for independent scaffolds in the same tenant. Entra security groups are separate directory objects: Microsoft Graph generates their GUID object IDs, which the template passes to Azure RBAC.

See Microsoft's [management group ID and display-name rules](https://learn.microsoft.com/azure/governance/management-groups/create-management-group-portal).

## Networking and WAF tradeoffs

Default hub `10.0.0.0/16`, production `10.10.0.0/16`, nonproduction `10.20.0.0/16`. Each network allocates its first two `/26` ranges for `snet-workload` and `snet-private-endpoints`; the remaining space is reserved. The tenant template and CLI preflight check private IPv4 ranges, overlap, host bits, and prefix lengths before creating the hierarchy. The standalone application template still requires checking overlap against existing networks in the target environment.

Each subnet has a separate NSG with explicit deny-all inbound and outbound rules at priority 4096; future approved allow rules use lower priority numbers. Both subnets disable default outbound access and enable private-endpoint network policies. NSGs are not comprehensive application-layer inspection, and Azure platform traffic semantics still apply.

The hub is a reserved network foundation. It is not an operational transit network: no peering, gateways, firewall, DNS forwarding, or routes are created. This deliberately defers service and traffic charges. For production workloads, add approved connectivity, egress, monitoring, backup, resilience, and service-specific subnet sizing/delegation. Do not deploy services requiring dedicated subnets into the generic subnet without redesign.

Management, Identity, and Security resource groups establish ownership boundaries. They contain no operating service. The identity subscription is for future Azure-hosted identity infrastructure, not the Entra directory itself. The Graph extension creates static security groups and optionally appends explicitly supplied owners/members; it does not configure Conditional Access, PIM, security defaults, or emergency access users. Production and nonproduction receive distinct contributor groups. Existing group IDs bypass directory writes.

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
- [Microsoft Graph Bicep security-group quickstart](https://learn.microsoft.com/graph/templates/bicep/quickstart-create-bicep-interactive-mode)
- [Group deployment reference and permissions](https://learn.microsoft.com/graph/templates/bicep/reference/groups?view=graph-bicep-1.0)
- [Root Graph import workaround for nested deployment authentication](https://github.com/Azure/bicep/issues/19207)
- [Graph Bicep limitations, including what-if](https://learn.microsoft.com/graph/templates/bicep/limitations)
