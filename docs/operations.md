# Operations and extensions

## Acceptance after deployment

1. Open **Management groups**. Confirm the organization intermediate root and all 11 descendants exist. Verify each supplied subscription has exactly the intended parent. Compact platform subscriptions belong under Platform; separated subscriptions belong under their service child.
2. Open the tenant deployment, inspect every nested deployment, and record outputs. Confirm four platform resource groups and two production application resource groups; optionally two nonproduction resource groups.
3. Check the hub and application VNets: address spaces, two `/26` subnets, NSG associations, deny-all inbound/outbound, and `defaultOutboundAccess=false`. Expect no peering, default egress, public IP, or paid network appliance.
4. In Azure Policy, scope to the intermediate root. Confirm three selected compliance assignments use **DoNotEnforce**, and their identities have no remediation role grants. Check the custom root guardrails and Corp public-IP rule. Wait for Azure's asynchronous evaluation; absence of immediate results is not a successful compliance assessment.
5. If **Configure Hierarchy Settings** was enabled, open **Management groups → Settings** and confirm the default management group is `<prefix>-sandbox` and authorization is required for creating management groups. If **Enable Activity Log Collection** was enabled, open `log-<prefix>-management` in the management resource group and confirm the `AzureActivity` table receives entries from every placed subscription; each subscription shows an `<prefix>-activity-log` diagnostic setting under **Monitor → Activity log → Export**.
6. Check `securityGroupObjectIds` in deployment outputs and find those IDs in **Entra ID → Groups**. Expect three groups in compact mode or four with nonproduction. Verify static/security-enabled/non-mail settings, expected owners/members, and Azure RBAC assignments. Production and nonproduction groups must be separate unless you explicitly chose to reuse a group. Application teams only have Contributor on their own workload RGs; network use requires a separate approved permission/design decision.
7. Follow bootstrap cleanup to remove temporary tenant-wide deployment access after establishing operational access.

For a controlled acceptance test in the target greenfield tenant, use a disposable **empty** resource group under the Corp application subscription and test the public-IP guardrail with a deployment **validation/what-if** before any resource creation. Verify denial after policy propagation. Test the chosen region guardrail similarly. These negative live checks have not been executed by this repository's initial build.

## Updating and redeploying

Edit Bicep, run `./scripts/build.ps1`, and commit **both** source and generated JSON. CI uses Bicep **0.47.16** and fails if portal artifacts differ from their source. Upgrade compiler and templates together. Use a stable organization prefix and deployment location; changing names can create a second hierarchy. Resource-group location and named tenant deployment location cannot be changed in place.

The README buttons use `https://cdn.jsdelivr.net/gh/shadowarmor/elz@<full-commit-sha>/<template>.json`. They are pinned to a reviewed template commit, rather than a mutable branch. After publishing a template change, update both button URLs to that new full commit SHA in a follow-up documentation commit. Verify each endpoint returns HTTP 200, `Access-Control-Allow-Origin: *`, and JSON matching the committed template before publishing the new links. URL-encode the complete CDN URL after `https://portal.azure.com/#create/Microsoft.Template/uri/`.

The compiled templates are self-contained, so a commit URL pins their complete module content. Initiative assignments still ingest minor and patch updates within their pinned major versions. jsDelivr serves the public GitHub files without Azure or GitHub credentials; it hosts no tenant parameters. CLI deployments use local files and do not depend on this CDN.

Earlier revisions named custom policy definitions and assignments with a fixed `elz-` prefix; the current templates use the organization prefix. Redeploying over an older scaffold with a different prefix creates a second set of definitions and assignments alongside the old ones, which must be removed explicitly.

ARM deployments use incremental mode. Setting an optional subscription/group/policy parameter to blank or false **does not remove** previously deployed resources, role assignments, policies, or subscription placement. Turning off hierarchy settings or activity-log collection likewise leaves the tenant settings, workspace, and diagnostic settings in place. Graph groups also persist, and membership arrays use append semantics: removing an ID from parameters does not revoke membership. Changing group IDs may leave the old role assignment. The previous template reused the production group for nonproduction; after upgrading, review and explicitly remove that prior nonproduction assignment if separation is intended. Changing application archetype or filling dedicated platform IDs can move subscriptions and change inheritance, and the old platform resource groups remain. Review configuration and explicit retirement actions; never treat parameter removal as a rollback. Graph changes are not supported by what-if.

Failed tenant deployments are not transactional: earlier nested deployments and moves may persist. Inspect deployment operations, fix the issue, and redeploy the same prefix/configuration. Do not delete/recreate the hierarchy to work around a propagation delay. Existing resource drift, policies, locks, and RBAC must be reviewed before reuse.

## Before hosting workloads

- Design hub/spoke peering or another approved connectivity model. Add DNS resolution, routing, and egress deliberately. A hub VNet alone provides no transit.
- Add explicit NSG allow rules for intended flows, including application-to-private-endpoint access. Current deny-all rules block ordinary workload traffic. Update private-endpoint policies and subnet delegations for each service as needed.
- Reserve dedicated subnets with required names/sizes for future Firewall, Bastion, gateways, or delegated services. Never attach a generic NSG to GatewaySubnet.
- Add central logging, retention, diagnostics, alerting, and a response process. Windows activation, patching, package pulls, and public APIs need approved outbound connectivity.
- Configure Entra access controls, emergency access, lifecycle governance, and audit review. The Identity RG is not directory configuration.
- Put the platform administrators group's Contributor assignment at the Platform management group behind Privileged Identity Management or an equivalent just-in-time control. The Cloud Adoption Framework recommends that platform-team access at management-group scope be granted only when needed; the standing assignment here is a bootstrap baseline.
- If you left **Configure Hierarchy Settings** off, set a default management group for new subscriptions and require authorization for management-group creation in **Management groups → Settings**, so nothing lands under the tenant root by accident.
- Review each workload's backup, restore, availability-zone, resilience, data protection, and compliance requirements. Add workload policy and narrowly scoped exceptions.

## Cost boundaries

The default resource set contains management groups, associations, resource groups, Azure policy, managed identities for assignments, ordinary static Entra security groups, Azure RBAC, virtual networks, and NSGs. It does not turn on paid Defender plans or automate deployment/remediation of chargeable resources. No deployment-script container/storage or premium group feature is provisioned for group creation. The optional activity-log workspace uses the pay-as-you-go plan with 30-day workspace retention: activity-log ingestion is free and the `AzureActivity` table keeps 90 days at no charge, but any other data later pointed at that workspace is billed per GB. Consider a daily cap before adding other sources.

Deferred features may incur charges: network peering/data transfer, NAT/VPN/ExpressRoute, Azure Firewall/Bastion, private endpoints/private DNS, logging storage/ingestion/retention, guest-configuration scenarios, Sentinel, paid Defender/Entra plans, and all application runtimes. Review current pricing when adding them. Subscription credits and billing offer conditions remain your responsibility. Existing tenant services are outside this scaffold's cost boundary.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| AuthorizationFailed at tenant `/` | Bootstrap role is at tenant scope, not only the root MG; refresh token and allow RBAC propagation |
| Subscription placement denied | Same tenant, enabled subscription, write/move permissions on source and destination parents; no upstream restrictions |
| Validation parameter is not an allowed value | Duplicate explicit subscription IDs, a subscription/group/owner/member ID that is not a hyphenated GUID, invalid prefix, excluded location, or overlapping/invalid network ranges; the parameter name in the error says which check failed |
| Graph group step fails before any management group exists | Expected fail-fast behavior; nothing Azure-side was created. Confirm directory group-write privileges, or deploy with Azure CLI/PowerShell as described in security-groups.md |
| Hierarchy settings write denied | Requires `Microsoft.Management/managementGroups/settings/write` on the tenant root group (Owner at `/` includes it); or leave Configure Hierarchy Settings off and set them in the portal later |
| Invalid subscription ID | Replace example placeholders; use GUIDs, not names; optional shared platform IDs stay blank |
| InvalidTemplate reports subscription identifier `''` with nonproduction blank | Reopen the latest README deployment button. Earlier templates used the blank optional ID in a dependency even when that deployment was disabled. The corrected template keeps its scope valid without creating nonproduction resources. |
| MissingSubscriptionRegistration | Register Microsoft.Network in the supplied subscription and wait |
| Management group not found immediately after creation | Check nested deployment dependencies and propagation; retry unchanged deployment after Azure catches up |
| Initiative not found / DefinitionVersion error | Run online preflight against the intended public-cloud tenant; verify catalog and available major version; do not substitute a guessed ID |
| Graph AuthenticationFailed / Insufficient privileges | Confirm the deploying work/school account has directory group-write privileges as well as Azure rights. Root and child templates declare Graph for nested auth. If the portal still fails, use Azure CLI/PowerShell with the same template; see security-groups.md. |
| PrincipalNotFound immediately after group creation | Directory replication can lag. Verify the group ID exists and rerun the same deployment; group uniqueName and role assignment IDs are stable. |
| What-if fails or omits security groups | Microsoft Graph extensible resources do not support what-if. Review group/membership parameters and use target-tenant validation and acceptance tests. |
| Portal cannot download template | Reopen the updated README button, which uses a commit-pinned jsDelivr URL. The original GitHub raw endpoint was observed returning HTTP 503 despite having CORS enabled. If the CDN URL also fails, clone and use the CLI or paste the downloaded JSON into the portal template editor. |
| Deployment location immutable | Keep the original metadata location or choose a new deployment name |
| Workload networking fails | Scaffold denies traffic by design; add approved NSG rules, DNS, routes, and connectivity |
| No immediate compliance results | Evaluation is asynchronous; verify assignment scope and wait, then inspect policy state |

## Teardown

No automatic destroy command is included. Tenant-wide teardown must explicitly account for hosted resources, subscription moves, inherited access, and retention. Inventory first; move subscriptions to a reviewed parent, remove owned policy/RBAC artifacts, and delete empty child groups from leaves upward. Never delete the existing tenant root. Deleting a management group is not subscription cancellation and does not delete workload resources. Graph security groups are directory objects and must be separately reviewed and deleted through Entra/Graph after checking all their assignments and memberships; deleting a resource group or deployment does not delete them.
