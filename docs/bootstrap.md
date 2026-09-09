# Bootstrap a greenfield tenant

This is a one-time administrative prerequisite, performed by an authorized tenant administrator. ELZ does not alter your current Azure tenant while you build or clone the repository.

## 1. Establish billing and subscriptions

Create or associate **at least two enabled Azure subscriptions** with the target Entra tenant: shared platform and application. Use empty subscriptions. For separated platform ownership, create additional management, identity, and security subscriptions, plus nonproduction if needed. Every explicit ID in the form is distinct; leave optional platform IDs blank to share.

Azure subscription creation varies across Enterprise Agreement, Microsoft Customer Agreement, CSP, and other offers. A tenant template cannot universally establish a billing account or create subscriptions without that offer's permissions. This is why ELZ accepts existing subscription IDs instead of assuming a billing scope. [Microsoft subscription creation guidance](https://learn.microsoft.com/azure/cost-management-billing/manage/programmatically-create-subscription).

Initialize management groups if this directory has never used them: open **Management groups** in Azure Portal and allow Azure to provision the tenant root group. Check that the subscriptions appear in this directory and review any existing inherited policies. Use a unique organization prefix; reusing an existing management group ID can reparent that group.

## 2. Grant tenant deployment access

Entra Global Administrator and Azure RBAC Owner are different permissions. Being Global Administrator or Owner of only the Tenant Root **management group** does not grant tenant-scope deployment access at `/`.

Microsoft's documented bootstrap is:

1. Sign into the target directory as an authorized Global Administrator.
2. In **Microsoft Entra ID → Properties → Access management for Azure resources**, enable elevated access. This grants that administrator User Access Administrator at `/`.
3. Grant the intended deployment principal the Azure **Owner** role at `/` for bootstrap. That covers nested management group/subscription deployments, policy, subscription placement, and optional RBAC.
4. Refresh the deployment principal's sign-in before deploying.

Example commands for an interactive deployment user, after elevation:

```powershell
az login --tenant '<target-tenant-guid>'
az account show --query '{tenant:tenantId,subscription:id}'
$deployerObjectId = az ad signed-in-user show --query id --output tsv
# Tenant-wide Owner is broad. Record this assignment ID so it can be removed precisely later.
az role assignment create --assignee-object-id $deployerObjectId --assignee-principal-type User --role '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' --scope / --query id --output tsv
```

Your organization may instead implement a reviewed custom deployment role plus appropriately scoped role-assignment permissions. Ensure it includes tenant `Microsoft.Resources/deployments/*`, management-group create/move operations, subscription association permissions at old/new parents, policy writes, and every nested resource operation. ELZ does not automatically grant permanent Owner or invent a custom deployment role.

[Tenant Bicep permissions](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-tenant#required-access) · [Elevate Azure resource access](https://learn.microsoft.com/azure/role-based-access-control/elevate-access-global-admin) · [Move subscription requirements](https://learn.microsoft.com/azure/governance/management-groups/manage#move-subscriptions).

## 3. Register resource providers

Ensure `Microsoft.Network` is registered in each supplied subscription before submitting the portal template. Registration is a subscription control-plane operation and does not provision network services. ELZ avoids a paid deployment-script resource for this bootstrap step.

```powershell
$subscriptionIds = @('<platform-subscription-guid>', '<application-subscription-guid>')
# Add any supplied management, identity, security, and nonproduction subscription IDs.
foreach ($subscriptionId in $subscriptionIds) {
    az provider register --namespace Microsoft.Network --subscription $subscriptionId --wait
    if ($LASTEXITCODE -ne 0) { throw "Provider registration failed: $subscriptionId" }
}
```

Confirm Microsoft.Authorization, Microsoft.Resources, and Microsoft.Management operations are available in the target environment. The read-only preflight checks subscription state, network registration, region names, selected group IDs, and enabled initiative availability. Provider registration can take several minutes. [Resource providers](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types).

## 4. Security groups and directory permissions

ELZ now creates the required security groups by default using the Microsoft Graph Bicep extension. Leave **Create Security Groups = true** and the existing-group fields blank. To reuse your organization's groups, supply their **object IDs**; the template will not modify those groups' membership or properties. With `createSecurityGroups=false`, blank fields skip those groups and their RBAC assignments.

The deployment principal needs both the Azure permissions above and permission to create/update Entra security groups. For interactive deployment, use a work/school account with the required group-management privileges; **Groups Administrator** is the documented role when tenant settings restrict group creation. Microsoft Graph Bicep group upserts require delegated `Group.ReadWrite.All`; Azure CLI and Azure PowerShell are Microsoft's documented supported interactive clients. For app-only automation, grant the deployment service principal the documented `Group.ReadWrite.All` application permission with administrator consent, separately from Azure RBAC. ELZ does not grant itself Graph permissions. [Group deployment permissions](https://learn.microsoft.com/graph/templates/bicep/reference/groups?view=graph-bicep-1.0) · [Interactive and app-only permissions](https://learn.microsoft.com/graph/templates/bicep/concept-permissions-and-privileges).

`securityGroupOwnerObjectIds` optionally supplies trusted user/service-principal owners. `securityGroupMembers` optionally supplies member arrays. Both default to empty: no person is automatically made a member, and an administrator is not automatically made an owner of a security group. A tenant group administrator can manage empty groups later. **The `owner` parameter used for resource tags is only a label, not a group owner or member.** [Configuration examples](security-groups.md).

| Group | Assignment |
| --- | --- |
| Platform administrators | Contributor at the Platform management group, inherited by its subscriptions |
| Security readers | Reader and Security Reader at the organization intermediate root |
| Production application contributors | Contributor at the production **workload** resource group; no control over network resource groups |
| Nonproduction application contributors | Separate group, created only when nonproduction is enabled; Contributor at its **workload** resource group |

Application teams will need narrowly scoped network permissions or a platform-managed deployment path to attach NICs, private endpoints, or services to subnets. No automatic Network Contributor assignment is made. The groups are ordinary security groups for Azure RBAC, not Entra directory-role-assignable groups; Conditional Access, PIM, dynamic membership, and Entra directory role assignments are not enabled.

## 5. Deploy, verify, then remove temporary bootstrap privileges

Complete the portal flow or CLI what-if/create. Record outputs, check policy evaluation, and establish the approved ongoing deployment identity. Then remove only the temporary assignment created in step 2, using its exact recorded ID:

```powershell
az role assignment delete --ids '<recorded-temporary-role-assignment-resource-id>'
```

Return **Access management for Azure resources** to **No** for the administrator who elevated. Preserve required operational access before removing temporary access. Subsequent tenant deployments need their own approved tenant-scope permissions.
