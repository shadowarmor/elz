import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('preflight', ROOT / 'scripts/preflight.py')
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


def direct_resources(template):
    declared = template.get('resources', [])
    return list(declared.values()) if isinstance(declared, dict) else declared


def resources(template):
    for resource in direct_resources(template):
        yield resource
        nested = resource.get('properties', {}).get('template')
        if nested:
            yield from resources(nested)


class ScaffoldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = json.loads((ROOT / 'azuredeploy.json').read_text(encoding='utf-8-sig'))
        cls.resources = list(resources(cls.template))

    def test_tenant_entry_and_no_remote_module_dependencies(self):
        self.assertIn('tenantDeploymentTemplate.json', self.template['$schema'])
        for resource in self.resources:
            self.assertNotIn('templateLink', resource.get('properties', {}))

    def test_no_chargeable_services_or_scripts(self):
        allowed = {'Microsoft.Resources/deployments', 'Microsoft.Management/managementGroups',
                   'Microsoft.Management/managementGroups/subscriptions', 'Microsoft.Resources/resourceGroups',
                   'Microsoft.Network/virtualNetworks', 'Microsoft.Network/networkSecurityGroups',
                   'Microsoft.Authorization/policyDefinitions', 'Microsoft.Authorization/policyAssignments',
                   'Microsoft.Authorization/roleAssignments', 'Microsoft.Graph/groups@v1.0'}
        self.assertTrue(self.resources)
        self.assertEqual({r['type'] for r in self.resources} - allowed, set())

    def test_networks_are_isolated(self):
        networks = [r for r in self.resources if r['type'] == 'Microsoft.Network/virtualNetworks']
        self.assertGreater(len(networks), 1)
        for network in networks:
            subnets = network['properties']['copy'][0]['input']['properties']
            self.assertIs(subnets['defaultOutboundAccess'], False)
            self.assertEqual(subnets['privateEndpointNetworkPolicies'], 'Enabled')
            self.assertIn('networkSecurityGroup', subnets)
        for nsg in (r for r in self.resources if r['type'] == 'Microsoft.Network/networkSecurityGroups'):
            rules = nsg['properties']['securityRules']
            self.assertEqual({x['properties']['direction'] for x in rules}, {'Inbound', 'Outbound'})
            self.assertTrue(all(x['properties']['access'] == 'Deny' for x in rules))

    def test_compliance_cannot_automatically_remediate(self):
        compliance = [r for r in self.resources if r['type'] == 'Microsoft.Authorization/policyAssignments'
                      and r['properties'].get('enforcementMode') == 'DoNotEnforce']
        self.assertEqual(len(compliance), 1)  # A loop assigns the three enabled initiatives.
        self.assertIn('definitionVersion', compliance[0]['properties'])
        for role in (r for r in self.resources if r['type'] == 'Microsoft.Authorization/roleAssignments'):
            self.assertEqual(role['properties']['principalType'], 'Group')

    def test_catalog_contains_requested_standards(self):
        catalog = json.loads((ROOT / 'infra/policy-catalog.json').read_text())
        self.assertEqual({x['key'] for x in catalog['initiatives']}, {'mcsb', 'cis', 'nis2'})
        for entry in catalog['initiatives']:
            self.assertTrue(preflight.valid_guid(entry['id']))
            self.assertLessEqual(len(entry['assignmentName']), 24)

    def test_validation_precedes_hierarchy_and_placement(self):
        root = direct_resources(self.template)
        validation = next(r for r in root if 'validate-inputs' in r['name'])
        hierarchy = next(r for r in root if "{0}-hierarchy'" in r['name'])
        self.assertTrue(any('validate-inputs' in d or d == 'inputValidation' for d in hierarchy['dependsOn']))
        for p in validation['properties']['template']['parameters'].values():
            self.assertEqual(p['allowedValues'], [True])
        placement = next(r for r in root if r.get('copy', {}).get('name') == 'placement')
        self.assertTrue(any('hierarchy' in d for d in placement['dependsOn']))

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
        for filename in ('azuredeploy.json', 'application.azuredeploy.json'):
            with self.subTest(filename=filename):
                template = json.loads((ROOT / filename).read_text(encoding='utf-8-sig'))
                self.assertEqual(template['imports']['microsoftGraphV1'], {'provider': 'MicrosoftGraph', 'version': '1.0.0'})
                self.assertIs(template['parameters']['createSecurityGroups']['defaultValue'], True)

    def test_security_groups_are_static_nonmail_and_preserve_members(self):
        groups = [r for r in self.resources if r['type'] == 'Microsoft.Graph/groups@v1.0']
        self.assertTrue(groups)
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


if __name__ == '__main__':
    unittest.main()
