# Policy design

ELZ assigns policies at the organization intermediate root, so both platform and application subscriptions inherit the selected compliance initiatives. The tenant root is untouched. Sandbox also inherits root-level compliance assessment and basic guardrails; it is not a policy exemption. Corp gets the additional public-IP guardrail.

## Verified built-in catalog

Verified from Microsoft's `Azure/azure-policy` repository on **2026-09-09**. [Machine-readable catalog](../infra/policy-catalog.json) records the source commit, exact identifiers, observed versions, and paths.

| Initiative | Definition GUID | Observed version | Assigned version |
| --- | --- | --- | --- |
| Microsoft cloud security benchmark | `1f3afdf9-d0c9-4c3d-847f-89da613e70a8` | 57.58.0 | `57.*.*` |
| CIS Azure Foundations v3.0.0 | `470a962c-86a0-433b-803a-3c176b5ce79c` | 1.3.0 | `1.*.*` |
| NIS2 | `32ff9e30-4725-4ca7-ba3a-904a7721ee87` | 1.2.0 | `1.*.*` |

The benchmark is the established Microsoft cloud security benchmark initiative, successor to Azure Security Benchmark. Microsoft also publishes a separate **MCSB v2** initiative; this scaffold deliberately uses the established ID above, rather than silently switching initiative families. Review a catalog change before adopting v2.

All three initiatives had defaults for every parameter at verification time. No display-name discovery or guessed GUID occurs at deployment. Major versions are pinned; minor/patch updates flow within that major. The catalog is verified for **Azure public cloud**. Sovereign-cloud catalogs and availability need separate validation and portal endpoints.

Sources: [built-in initiative index](https://learn.microsoft.com/azure/governance/policy/samples/built-in-initiatives), [benchmark source](https://github.com/Azure/azure-policy/blob/ff2ae5a6d762b10944f6abc16a9e48b68cdedcaf/built-in-policies/policySetDefinitions/Security%20Center/AzureSecurityCenter.json), [CIS source](https://github.com/Azure/azure-policy/blob/ff2ae5a6d762b10944f6abc16a9e48b68cdedcaf/built-in-policies/policySetDefinitions/Regulatory%20Compliance/CIS_Azure_Foundations_v3.0.0.json), [NIS2 source](https://github.com/Azure/azure-policy/blob/ff2ae5a6d762b10944f6abc16a9e48b68cdedcaf/built-in-policies/policySetDefinitions/Regulatory%20Compliance/NIS2.json).

## Assessment versus enforcement

Compliance assignments always use **DoNotEnforce**. They evaluate compliance without enforcing deny/modify/deploy effects during resource changes. This is different from setting each policy's effect to Audit: the initiative's original effect and control semantics remain intact. System-assigned identities exist because constituent policies may require them, but they receive **no Azure RBAC grants**, and no remediation tasks are created.

DoNotEnforce alone does not prohibit an administrator from later creating a manual remediation task. Enabling remediation requires an explicit design change: review effects, prerequisites, identity permissions, chargeable services, exclusions, deployment ordering, and test results. Do not simply grant Contributor to the assignment identities. [Assignment enforcement and identity behavior](https://learn.microsoft.com/azure/governance/policy/concepts/assignment-structure).

| Custom guardrail | Scope | Default behavior |
| --- | --- | --- |
| Restrict classic resource providers | Intermediate root | Deny classic compute, network, and storage types |
| Allowed resource locations | Intermediate root | Only assigned when list is nonempty; Deny outside list; Indexed mode exempts global and B2C directory resources |
| Resource group tags | Intermediate root | Audit missing or empty Owner, CostCenter, Environment |
| Restrict public IPs and prefixes | Corp | Deny public IP address and public IP prefix resources |

`guardrailEffect=Audit` makes the first, second, and fourth rules audit. It does not change compliance assignment enforcement. The Corp public-IP rule does **not** cover public PaaS endpoints, DNS exposure, or all managed-service ingress. Add service-specific controls as workloads are designed. The location rule evaluates regional Indexed resources; it does not enforce RG metadata residency or constrain every global/extension resource.

Governance is deployed after initial platform/application resources. This avoids policy propagation races during bootstrap; input checks ensure selected resource location agrees with the optional location allowlist. Azure's inherited policy state is eventually consistent. Existing upstream policies still apply during deployment.

## What compliance reports mean

Azure Policy initiative assignments cover a subset of technical controls. They do not certify the organization or establish compliance with legislation. NIS2 obligations depend on applicable national law, organizational scope, governance, and evidence beyond Azure resources. CIS also includes identity, host, and operational configuration this scaffold does not implement.

Examples of work outside this scaffold: MFA and break-glass procedures, Conditional Access/PIM licensing and configuration, vulnerability management, guest configuration, logging and retention, backup and restore exercises, incident reporting, supply-chain controls, staff training, and manual control attestations.

Use **Azure Policy → Compliance**, scoped to the intermediate root, to inspect results. Initial evaluation is asynchronous and might take hours; empty subscriptions do not produce meaningful pass scores. Some built-ins depend on Defender, extensions, or resources that are intentionally absent. Regulatory-compliance dashboards and advanced Defender features may require paid plans; ELZ does not enable those plans. [Regulatory compliance in Azure Policy](https://learn.microsoft.com/azure/governance/policy/concepts/regulatory-compliance).

For exceptions, use a reviewed policy exemption at the narrowest scope with an owner, justification, and expiry. Do not weaken the whole hierarchy to accommodate a single workload. An initiative switch set to false stops declaring that resource; **incremental ARM deployment does not delete the previous assignment**. Remove obsolete assignments explicitly after reviewing the impact.
