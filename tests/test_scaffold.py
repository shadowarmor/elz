import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('preflight', ROOT / 'scripts/preflight.py')
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)

TEMPLATES = ('azuredeploy.json', 'application.azuredeploy.json')
# Resource types that are allowed only behind an opt-in parameter (default false).
OPT_IN_TYPES = {
    'Microsoft.Management/managementGroups/settings': 'configureHierarchySettings',
    'Microsoft.OperationalInsights/workspaces': 'enableActivityLogCollection',
    'Microsoft.Insights/diagnosticSettings': 'enableActivityLogCollection',
}


def load(filename):
    return json.loads((ROOT / filename).read_text(encoding='utf-8-sig'))


def direct_resources(template):
    declared = template.get('resources', [])
    return list(declared.values()) if isinstance(declared, dict) else declared


def resources(template, conditions=()):
    """Yield (resource, inherited conditions) for every resource, descending into nested templates."""
    for resource in direct_resources(template):
        own = conditions + ((resource['condition'],) if 'condition' in resource else ())
        yield resource, own
        nested = resource.get('properties', {}).get('template')
        if nested:
            yield from resources(nested, own)


class ScaffoldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = load('azuredeploy.json')
        cls.templates = {name: load(name) for name in TEMPLATES}
        cls.resources = [r for r, _ in resources(cls.template)]
        cls.all_resources = {name: list(resources(t)) for name, t in cls.templates.items()}

    def test_tenant_entry_and_no_remote_module_dependencies(self):
        self.assertIn('tenantDeploymentTemplate.json', self.template['$schema'])
        self.assertIn('subscriptionDeploymentTemplate.json', self.templates['application.azuredeploy.json']['$schema'])
        for name, entries in self.all_resources.items():
            for resource, _ in entries:
                self.assertNotIn('templateLink', resource.get('properties', {}), name)

    def test_no_chargeable_services_or_scripts(self):
        allowed = {'Microsoft.Resources/deployments', 'Microsoft.Management/managementGroups',
                   'Microsoft.Management/managementGroups/subscriptions', 'Microsoft.Resources/resourceGroups',
                   'Microsoft.Network/virtualNetworks', 'Microsoft.Network/networkSecurityGroups',
                   'Microsoft.Authorization/policyDefinitions', 'Microsoft.Authorization/policyAssignments',
                   'Microsoft.Authorization/roleAssignments', 'Microsoft.Graph/groups@v1.0'} | set(OPT_IN_TYPES)
        for name, entries in self.all_resources.items():
            with self.subTest(template=name):
                self.assertTrue(entries)
                self.assertEqual({r['type'] for r, _ in entries} - allowed, set())

    def test_optional_features_default_off_and_gated(self):
        for parameter in set(OPT_IN_TYPES.values()):
            self.assertIs(self.template['parameters'][parameter]['defaultValue'], False, parameter)
        seen = set()
        for name, entries in self.all_resources.items():
            for resource, conditions in entries:
                gate = OPT_IN_TYPES.get(resource['type'])
                if gate:
                    seen.add(resource['type'])
                    # The gate may sit on the resource or on an ancestor nested deployment.
                    self.assertTrue(conditions, f'{name}: {resource["type"]} is not conditional')
                    self.assertTrue(any(gate in c or 'deployLogAnalytics' in c for c in conditions),
                                    f'{name}: {resource["type"]} gated by {conditions}')
        self.assertEqual(seen, set(OPT_IN_TYPES))

    def test_networks_are_isolated(self):
        for name, entries in self.all_resources.items():
            with self.subTest(template=name):
                networks = [r for r, _ in entries if r['type'] == 'Microsoft.Network/virtualNetworks']
                self.assertTrue(networks)
                for network in networks:
                    subnets = network['properties']['copy'][0]['input']['properties']
                    self.assertIs(subnets['defaultOutboundAccess'], False)
                    self.assertEqual(subnets['privateEndpointNetworkPolicies'], 'Enabled')
                    self.assertIn('networkSecurityGroup', subnets)
                nsgs = [r for r, _ in entries if r['type'] == 'Microsoft.Network/networkSecurityGroups']
                self.assertTrue(nsgs)
                for nsg in nsgs:
                    rules = nsg['properties']['securityRules']
                    self.assertEqual({x['properties']['direction'] for x in rules}, {'Inbound', 'Outbound'})
                    self.assertTrue(all(x['properties']['access'] == 'Deny' for x in rules))

    def test_compliance_cannot_automatically_remediate(self):
        compliance = [r for r in self.resources if r['type'] == 'Microsoft.Authorization/policyAssignments'
                      and r['properties'].get('enforcementMode') == 'DoNotEnforce']
        self.assertEqual(len(compliance), 1)  # A loop assigns the three enabled initiatives.
        self.assertIn('definitionVersion', compliance[0]['properties'])
        for name, entries in self.all_resources.items():
            for role in (r for r, _ in entries if r['type'] == 'Microsoft.Authorization/roleAssignments'):
                self.assertEqual(role['properties']['principalType'], 'Group', name)

    def test_catalog_contains_requested_standards(self):
        catalog = json.loads((ROOT / 'infra/policy-catalog.json').read_text())
        self.assertEqual({x['key'] for x in catalog['initiatives']}, {'mcsb', 'cis', 'nis2'})
        longest_prefix = self.template['parameters']['organizationPrefix']['maxLength']
        for entry in catalog['initiatives']:
            self.assertTrue(preflight.valid_guid(entry['id']))
            # Management-group-scope assignment names are limited to 24 characters: <prefix>-<suffix>.
            self.assertLessEqual(longest_prefix + 1 + len(entry['assignmentSuffix']), 24, entry['key'])

    def test_policy_names_use_prefix_not_fixed_elz(self):
        policy_types = {'Microsoft.Authorization/policyDefinitions', 'Microsoft.Authorization/policyAssignments'}
        names = [r['name'] for r in self.resources if r['type'] in policy_types]
        self.assertTrue(names)
        for name in names:
            self.assertIn("parameters('prefix')", name)
            self.assertNotIn("'elz-", name)

    def test_validation_precedes_hierarchy_and_placement(self):
        root = direct_resources(self.template)
        validation = next(r for r in root if 'validate-inputs' in r['name'])
        hierarchy = next(r for r in root if "{0}-hierarchy'" in r['name'])
        self.assertTrue(any('validate-inputs' in d or d == 'inputValidation' for d in hierarchy['dependsOn']))
        for p in validation['properties']['template']['parameters'].values():
            self.assertEqual(p['allowedValues'], [True])
        placement = next(r for r in root if r.get('copy', {}).get('name') == 'placement')
        self.assertTrue(any('hierarchy' in d for d in placement['dependsOn']))

    def test_graph_group_creation_precedes_any_azure_mutation(self):
        # A Graph permission failure (for example in the portal) must stop before management groups exist.
        root = self.template['resources']
        self.assertIn('securityGroups', root['hierarchy']['dependsOn'])
        self.assertIn('inputValidation', root['securityGroups']['dependsOn'])
        for name in ('placement', 'platform', 'application', 'nonproduction', 'governance', 'corpGuardrails', 'platformRbac'):
            self.assertTrue(root[name].get('dependsOn'), name)

    def test_identifier_validation_covers_every_optional_id(self):
        root = self.template['resources']
        check = root['inputValidation']['properties']['parameters']['identifiersAreGuids']['value']
        self.assertIn("variables('identifiers')", check)
        variables = self.template['variables']
        covered = json.dumps(variables['optionalIdentifiers']) + json.dumps(variables['identifiers'])
        for parameter in preflight.SUBSCRIPTIONS + preflight.GROUPS + ('securityGroupOwnerObjectIds',):
            self.assertIn(f"parameters('{parameter}')", covered, parameter)
        self.assertIn("securityGroupMembers", json.dumps(variables['memberIdentifiers']))
        self.assertIn("split(", check)  # split() never throws on short input, unlike substring().
        self.assertNotIn('substring(', check)

    def test_disabled_nonproduction_has_valid_scope_and_dependency_ids(self):
        # ARM validates dependency resource IDs even when the target deployment's condition is false.
        root = direct_resources(self.template)
        nonproduction = next(r for r in root if "{0}-application-nonprod'" in r['name'])
        self.assertEqual(nonproduction['condition'], "[not(empty(parameters('nonproductionSubscriptionId')))]")
        self.assertEqual(nonproduction['subscriptionId'], "[variables('nonproductionDeploymentSubscriptionId')]")
        self.assertEqual(
            self.template['variables']['nonproductionDeploymentSubscriptionId'],
            "[if(empty(parameters('nonproductionSubscriptionId')), parameters('applicationSubscriptionId'), parameters('nonproductionSubscriptionId'))]",
        )
        governance = next(r for r in root if "{0}-governance'" in r['name'])
        dependency = next(d for d in governance['dependsOn'] if 'application-nonprod' in d or d == 'nonproduction')
        if dependency != 'nonproduction':
            self.assertIn("subscriptionResourceId(variables('nonproductionDeploymentSubscriptionId')", dependency)
        self.assertNotIn("subscriptionResourceId(parameters('nonproductionSubscriptionId')", json.dumps(self.template))

    def test_graph_auth_import_is_present_in_each_entry_point(self):
        for filename, template in self.templates.items():
            with self.subTest(filename=filename):
                self.assertEqual(template['imports']['microsoftGraphV1'], {'provider': 'MicrosoftGraph', 'version': '1.0.0'})
                self.assertIs(template['parameters']['createSecurityGroups']['defaultValue'], True)

    def test_security_groups_are_static_nonmail_and_preserve_members(self):
        for name, entries in self.all_resources.items():
            groups = [r for r, _ in entries if r['type'] == 'Microsoft.Graph/groups@v1.0']
            self.assertTrue(groups, name)
            for group in groups:
                props = group['properties']
                self.assertIs(props['securityEnabled'], True)
                self.assertIs(props['mailEnabled'], False)
                self.assertNotIn('isAssignableToRole', props)
                self.assertNotIn('membershipRule', props)
                self.assertIn('uniqueName', props)
                self.assertEqual(props['owners']['relationshipSemantics'], 'append')
                self.assertEqual(props['members']['relationshipSemantics'], 'append')
                self.assertIn('empty(parameters(', group['condition'])  # Never modify groups supplied by ID.

    def test_groups_wire_to_separate_production_and_nonproduction_roles(self):
        root = self.template['resources']
        group_defs = self.template['variables']['groupDefinitions']
        self.assertEqual([g['key'] for g in group_defs], ['platformAdmins', 'securityReaders', 'applicationProd', 'applicationNonprod'])
        self.assertIs(group_defs[2]['enabled'], True)
        self.assertIn("nonproductionSubscriptionId", group_defs[3]['enabled'])
        for module, parameter, index in [('application', 'applicationTeamGroupObjectId', 2), ('nonproduction', 'applicationTeamGroupObjectId', 3), ('governance', 'securityReadersGroupObjectId', 1), ('platformRbac', 'principalId', 0)]:
            value = root[module]['properties']['parameters'][parameter]['value']
            self.assertIn(f"format('securityGroups[{{0}}]', {index})", value)
        self.assertFalse(root['application']['properties']['parameters']['createSecurityGroups']['value'])
        self.assertFalse(root['nonproduction']['properties']['parameters']['createSecurityGroups']['value'])
        self.assertEqual(set(self.template['outputs']['securityGroupObjectIds']['value']), {'platformAdmins', 'securityReaders', 'applicationProd', 'applicationNonprod'})

    def test_activity_log_covers_every_placed_subscription(self):
        root = self.template['resources']
        activity = root['activityLogs']
        self.assertEqual(activity['copy']['count'], "[length(variables('placements'))]")
        self.assertIn('enableActivityLogCollection', activity['condition'])
        self.assertIn("variables('placements')[copyIndex()].subscriptionId", activity['subscriptionId'])
        self.assertIn("reference('platform')", activity['properties']['parameters']['workspaceId']['value'])
        nested = activity['properties']['template']
        setting = next(r for r in direct_resources(nested) if r['type'] == 'Microsoft.Insights/diagnosticSettings')
        self.assertIn("parameters('workspaceId')", setting['properties']['workspaceId'])
        # The category list is a Bicep loop over a template variable; it compiles to a property copy block.
        logs_copy = next(c for c in setting['properties']['copy'] if c['name'] == 'logs')
        self.assertIn("variables('categories')", logs_copy['count'])
        self.assertIs(logs_copy['input']['enabled'], True)
        self.assertEqual(nested['variables']['categories'], ['Administrative', 'Security', 'ServiceHealth', 'Alert', 'Recommendation', 'Policy', 'Autoscale', 'ResourceHealth'])

    def test_hierarchy_settings_target_sandbox_and_require_authorization(self):
        nested = self.template['resources']['hierarchy']['properties']['template']
        setting = next(r for r in direct_resources(nested) if r['type'] == 'Microsoft.Management/managementGroups/settings')
        self.assertIn("parameters('configureHierarchySettings')", setting['condition'])
        self.assertTrue(setting['name'].endswith("'default')]"))
        self.assertIn("variables('topGroups')[2]", setting['properties']['defaultManagementGroup'])
        self.assertEqual(nested['variables']['topGroups'][2]['suffix'], 'sandbox')
        self.assertIs(setting['properties']['requireAuthorizationForGroupCreation'], True)
        self.assertTrue(any('topGroups' in d for d in setting['dependsOn']))  # Sandbox exists before it becomes the default.


class InputTests(unittest.TestCase):
    def setUp(self):
        self.values = preflight.parameters(ROOT / 'examples/compact.parameters.json')
        self.values['platformSubscriptionId'] = '11111111-1111-4111-8111-111111111111'
        self.values['applicationSubscriptionId'] = '22222222-2222-4222-8222-222222222222'

    def test_compact(self):
        self.assertEqual(preflight.validate(self.values), [])

    def test_split_platform(self):
        for i, key in enumerate(preflight.SUBSCRIPTIONS[2:], 3):
            self.values[key] = f'{i:08d}-1111-4111-8111-111111111111'
        self.assertEqual(preflight.validate(self.values), [])

    def test_duplicate_subscriptions_case_insensitive(self):
        self.values['managementSubscriptionId'] = self.values['platformSubscriptionId'].upper()
        self.assertTrue(any('distinct' in x for x in preflight.validate(self.values)))

    def test_overlapping_networks(self):
        self.values['applicationAddressPrefix'] = '10.0.1.0/24'
        self.assertTrue(any('overlaps' in x for x in preflight.validate(self.values)))

    def test_rejects_invalid_networks(self):
        for invalid in ('10.10.0.0/27', '10.10.1.1/16', '8.8.0.0/16', 'fd00::/64'):
            with self.subTest(invalid=invalid):
                values = copy.deepcopy(self.values)
                values['applicationAddressPrefix'] = invalid
                self.assertTrue(preflight.validate(values))

    def test_rejects_placeholder_and_missing_subscription(self):
        self.values['platformSubscriptionId'] = '00000000-0000-0000-0000-000000000000'
        self.values.pop('applicationSubscriptionId')
        self.assertEqual(len(preflight.validate(self.values)), 2)

    def test_region_and_prefix(self):
        self.values['allowedLocations'] = ['eastus']
        self.values['organizationPrefix'] = '../outside'
        self.assertEqual(len(preflight.validate(self.values)), 2)

    def test_security_group_member_inputs(self):
        self.values['securityGroupOwnerObjectIds'] = ['33333333-3333-4333-8333-333333333333']
        self.values['securityGroupMembers'] = {'applicationProd': ['44444444-4444-4444-8444-444444444444']}
        self.assertEqual(preflight.validate(self.values), [])
        self.values['securityGroupMembers']['applicationProd'] = ['/subscriptions/not-an-object-id']
        self.assertTrue(any('applicationProd' in error for error in preflight.validate(self.values)))

    def test_security_group_inputs_reject_unknown_keys_and_wrong_types(self):
        self.values['securityGroupMembers'] = {'platfromAdmins': []}
        self.assertTrue(any('Unknown' in error for error in preflight.validate(self.values)))
        self.values['securityGroupMembers'] = {'platformAdmins': 'not-an-array'}
        self.assertTrue(any('array' in error for error in preflight.validate(self.values)))
        self.values['securityGroupOwnerObjectIds'] = ['not-a-guid']
        self.assertTrue(any('securityGroupOwnerObjectIds' in error for error in preflight.validate(self.values)))

    def test_optional_feature_switches_must_be_boolean(self):
        for key in ('configureHierarchySettings', 'enableActivityLogCollection'):
            with self.subTest(key=key):
                values = copy.deepcopy(self.values)
                self.assertIs(values[key], False)  # template default
                values[key] = 'yes'
                self.assertTrue(any(key in error for error in preflight.validate(values)))


if __name__ == '__main__':
    unittest.main()
