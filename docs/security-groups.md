# Security groups and access

The tenant template creates the groups below by default and passes their actual Graph object IDs to the Azure RBAC modules. The Azure **Owner** and **CostCenter** tags are descriptive labels; they do not identify group owners or members.

| Default name (prefix `elz`) | Azure access | Creation condition |
| --- | --- | --- |
| `sg-elz-platform-admins` | Contributor on `elz-platform`, inherited by all platform subscriptions | No existing platform group ID supplied |
| `sg-elz-security-readers` | Reader and Security Reader on the organization intermediate root | No existing security reader group ID supplied |
| `sg-elz-application-prod-contributors` | Contributor on `rg-elz-prod-workload` only | No existing production group ID supplied |
| `sg-elz-application-nonprod-contributors` | Contributor on `rg-elz-nonprod-workload` only | Nonproduction subscription enabled and no existing nonproduction group ID supplied |

`createSecurityGroups` defaults to `true`. With it set to `false`, only supplied group IDs receive assignments; blank fields skip delegation. The standalone application template creates its own environment-specific contributor group by default and exposes `applicationSecurityGroupObjectId`. The tenant template exposes all four keys in `securityGroupObjectIds` (nonproduction is blank when disabled).

## Type, owners, and members

Groups are security-enabled, non-mail-enabled, static-membership groups. They have no Entra directory roles, dynamic membership, or PIM configuration. Standard Azure RBAC group assignment does not require setting `isAssignableToRole`; that property is omitted, avoiding the extra privilege/licensing associated with directory-role-assignable groups.

Creation supplies an immutable `uniqueName` equal to the group name. Repeating deployment with the same prefix targets the same group. Display names are not reliable identity keys: if a manually created group already has that display name, supply its object ID to reuse it. Otherwise Graph can create a second group with the same display name and a different uniqueName.

Owner and member arrays default to empty. No individual is automatically granted membership. Security-group creators are not automatically owners in this configuration; a tenant group administrator can assign ownership afterward, or supply trusted user/service-principal owner object IDs at deployment. Owners can control membership and consequently grant the group's Azure access. Use separate group administrators or your approved identity governance process where environment separation requires it.

`securityGroupOwnerObjectIds` applies to all ELZ-managed groups. `securityGroupMembers` has four optional array keys. Relationships use **append** semantics: repeated deployment adds listed principals and preserves existing members/owners. Removing a principal from a parameter file does not remove them from the group; revoke access explicitly through the identity process. Existing groups supplied by ID are never changed by the Graph module, including their membership and ownership.

Example additions inside an ARM parameter file's `parameters` object; replace every sample GUID with an actual directory **object ID** before use:

```json
{
  "createSecurityGroups": { "value": true },
  "securityGroupOwnerObjectIds": {
    "value": ["11111111-1111-4111-8111-111111111111"]
  },
  "securityGroupMembers": {
    "value": {
      "platformAdmins": ["22222222-2222-4222-8222-222222222222"],
      "securityReaders": ["33333333-3333-4333-8333-333333333333"],
      "applicationProd": ["44444444-4444-4444-8444-444444444444"],
      "applicationNonprod": []
    }
  }
}
```

For an existing group, use `platformAdminsGroupObjectId`, `securityReadersGroupObjectId`, `applicationTeamGroupObjectId` (production), or `nonproductionApplicationTeamGroupObjectId`. To intentionally share the application group across environments, explicitly supply the same existing group ID in both application fields; the default creates separate groups.

The standalone application button accepts `securityGroupOwnerObjectIds` and `applicationTeamMemberObjectIds`, rather than the tenant template's membership object. It follows the same append/reuse rules. It does not grant application contributors network permissions; subnet use needs a reviewed platform-managed deployment path or narrowly scoped additional assignment.

## Authentication and portal behavior

The template uses Microsoft's stable Graph v1.0 Bicep extension package **1.0.0** with Bicep **0.47.16**. Graph creation requires a work/school deployment account, Entra group-management privileges, and appropriate Graph permissions in addition to Azure RBAC. The resource reference lists **Group.ReadWrite.All** for both delegated and application group upserts. Groups Administrator is the documented interactive role when group creation is restricted. Adding owners or members requires permission to resolve and manage those relationships. ELZ does not assign directory roles or grant Graph consent to its deployer.

Both root entry points and Graph child modules declare the extension. This applies the Microsoft Bicep team's documented workaround for Graph authentication through nested deployments. However, Microsoft's supported interactive clients are Azure CLI and Azure PowerShell, and portal/Template Spec authentication has had reported limitations. The updated portal path has **not** been acceptance-tested in a target tenant. If the portal reports Graph `AuthenticationFailed` or `Insufficient privileges`, use `az login --tenant <tenant-id>` and the repository's CLI deployment script with the same parameters, after confirming directory privileges. Do not grant broader permissions merely to work around a client authentication problem.

Microsoft Graph resources do not support ARM what-if, and portal deployment history may not show Graph resources normally. Verify the actual groups in Entra using the output object IDs. Replication delays can affect immediate RBAC assignment; if a new group's ID is not yet visible, retry the unchanged deployment after replication. No paid wait/deployment-script service is included.

Sources: [group quickstart](https://learn.microsoft.com/graph/templates/bicep/quickstart-create-bicep-interactive-mode), [group resource and permissions](https://learn.microsoft.com/graph/templates/bicep/reference/groups?view=graph-bicep-1.0), [deployment permissions](https://learn.microsoft.com/graph/templates/bicep/concept-permissions-and-privileges), [root import workaround](https://github.com/Azure/bicep/issues/19207), [portal support discussion](https://github.com/microsoftgraph/msgraph-bicep-types/issues/294), [Graph limitations](https://learn.microsoft.com/graph/templates/bicep/limitations).
