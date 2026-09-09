# Operations and extensions

## Acceptance after deployment

1. Open **Management groups**. Confirm the organization intermediate root and all 11 descendants exist. Verify each supplied subscription has exactly the intended parent. Compact platform subscriptions belong under Platform; separated subscriptions belong under their service child.
2. Open the tenant deployment, inspect every nested deployment, and record outputs. Confirm four platform resource groups and two production application resource groups; optionally two nonproduction resource groups.
3. Check the hub and application VNets: address spaces, two `/26` subnets, NSG associations, deny-all inbound/outbound, and `defaultOutboundAccess=false`. Expect no peering, default egress, public IP, or paid network appliance.
4. In Azure Policy, scope to the intermediate root. Confirm three selected compliance assignments use **DoNotEnforce**, and their identities have no remediation role grants. Check the custom root guardrails and Corp public-IP rule. Wait for Azure's asynchronous evaluation; absence of immediate results is not a successful compliance assessment.
5. Check optional RBAC assignments and group membership. Verify application teams only have Contributor on workload resource groups; network use requires a separate approved permission/design decision.
6. Follow bootstrap cleanup to remove temporary tenant-wide deployment access after establishing operational access.

For a controlled acceptance test in the target greenfield tenant, use a disposable **empty** resource group under the Corp application subscription and test the public-IP guardrail with a deployment **validation/what-if** before any resource creation. Verify denial after policy propagation. Test the chosen region guardrail similarly. These negative live checks have not been executed by this repository's initial build.

## Updating and redeploying

Edit Bicep, run `./scripts/build.ps1`, and commit **both** source and generated JSON. CI uses Bicep **0.47.16** and fails if portal artifacts differ from their source. Upgrade compiler and templates together. Use a stable organization prefix and deployment location; changing names can create a second hierarchy. Resource-group location and named tenant deployment location cannot be changed in place.

For predictable portal deployment, replace `main` in the raw template URL with a reviewed full Git commit SHA and URL-encode it. The compiled templates are self-contained, so a commit URL pins their complete module content. Initiative assignments still ingest minor and patch updates within their pinned major versions.

ARM deployments use incremental mode. Setting an optional subscription/group/policy parameter to blank or false **does not remove** previously deployed resources, role assignments, policies, or subscription placement. Changing group IDs may leave the old role assignment. Changing application archetype or filling dedicated platform IDs can move subscriptions and change inheritance, and the old platform resource groups remain. Review what-if plus explicit retirement actions; never treat parameter removal as a rollback.

Failed tenant deployments are not transactional: earlier nested deployments and moves may persist. Inspect deployment operations, fix the issue, and redeploy the same prefix/configuration. Do not delete/recreate the hierarchy to work around a propagation delay. Existing resource drift, policies, locks, and RBAC must be reviewed before reuse.

## Before hosting workloads

- Design hub/spoke peering or another approved connectivity model. Add DNS resolution, routing, and egress deliberately. A hub VNet alone provides no transit.
- Add explicit NSG allow rules for intended flows, including application-to-private-endpoint access. Current deny-all rules block ordinary workload traffic. Update private-endpoint policies and subnet delegations for each service as needed.
- Reserve dedicated subnets with required names/sizes for future Firewall, Bastion, gateways, or delegated services. Never attach a generic NSG to GatewaySubnet.
- Add central logging, retention, diagnostics, alerting, and a response process. Windows activation, patching, package pulls, and public APIs need approved outbound connectivity.
- Configure Entra access controls, emergency access, lifecycle governance, and audit review. The Identity RG is not directory configuration.
- Review each workload's backup, restore, availability-zone, resilience, data protection, and compliance requirements. Add workload policy and narrowly scoped exceptions.

## Cost boundaries

The default resource set contains management groups, associations, resource groups, Azure policy, managed identities for assignments, Azure RBAC, virtual networks, and NSGs. It does not turn on paid Defender plans or automate deployment/remediation of chargeable resources. Azure Policy evaluation of this Azure-resource scaffold does not require ELZ to provision paid compute.

Deferred features may incur charges: network peering/data transfer, NAT/VPN/ExpressRoute, Azure Firewall/Bastion, private endpoints/private DNS, logging storage/ingestion/retention, guest-configuration scenarios, Sentinel, paid Defender/Entra plans, and all application runtimes. Review current pricing when adding them. Subscription credits and billing offer conditions remain your responsibility. Existing tenant services are outside this scaffold's cost boundary.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| AuthorizationFailed at tenant `/` | Bootstrap role is at tenant scope, not only the root MG; refresh token and allow RBAC propagation |
| Subscription placement denied | Same tenant, enabled subscription, write/move permissions on source and destination parents; no upstream restrictions |
| Validation parameter is not an allowed value | Duplicate explicit subscription IDs, invalid prefix, excluded location, or overlapping/invalid network ranges; correct inputs |
| Invalid subscription ID | Replace example placeholders; use GUIDs, not names; optional shared platform IDs stay blank |
| MissingSubscriptionRegistration | Register Microsoft.Network in the supplied subscription and wait |
| Management group not found immediately after creation | Check nested deployment dependencies and propagation; retry unchanged deployment after Azure catches up |
| Initiative not found / DefinitionVersion error | Run online preflight against the intended public-cloud tenant; verify catalog and available major version; do not substitute a guessed ID |
| Portal cannot download template | Confirm public repository/raw URL is reachable; retry transient GitHub CDN errors; clone and use CLI as fallback |
| Deployment location immutable | Keep the original metadata location or choose a new deployment name |
| Workload networking fails | Scaffold denies traffic by design; add approved NSG rules, DNS, routes, and connectivity |
| No immediate compliance results | Evaluation is asynchronous; verify assignment scope and wait, then inspect policy state |

## Teardown

No automatic destroy command is included. Tenant-wide teardown must explicitly account for hosted resources, subscription moves, inherited access, and retention. Inventory first; move subscriptions to a reviewed parent, remove owned policy/RBAC artifacts, and delete empty child groups from leaves upward. Never delete the existing tenant root. Deleting a management group is not subscription cancellation and does not delete workload resources.
