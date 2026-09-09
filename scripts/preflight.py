"""Read-only input and optional Azure checks. Python standard library only."""
import argparse
import ipaddress
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
SUBSCRIPTIONS = (
    'platformSubscriptionId', 'applicationSubscriptionId', 'managementSubscriptionId',
    'identitySubscriptionId', 'securitySubscriptionId', 'nonproductionSubscriptionId',
)
GROUPS = ('platformAdminsGroupObjectId', 'securityReadersGroupObjectId', 'applicationTeamGroupObjectId', 'nonproductionApplicationTeamGroupObjectId')
MEMBER_KEYS = ('platformAdmins', 'securityReaders', 'applicationProd', 'applicationNonprod')


def parameters(path):
    template = json.loads((ROOT / 'azuredeploy.json').read_text(encoding='utf-8-sig'))
    result = {k: v['defaultValue'] for k, v in template['parameters'].items() if 'defaultValue' in v}
    supplied = json.loads(Path(path).read_text(encoding='utf-8-sig'))['parameters']
    for key, value in supplied.items():
        if key not in template['parameters']:
            raise ValueError(f'Unknown parameter: {key}')
        result[key] = value['value']
    return result


def valid_guid(value):
    try:
        return str(uuid.UUID(value)) == value.lower() and uuid.UUID(value).int != 0
    except (ValueError, AttributeError, TypeError):
        return False


def validate(values):
    errors = []
    configured = []
    for key in SUBSCRIPTIONS:
        value = values.get(key, '')
        if key in SUBSCRIPTIONS[:2] or value:
            if not valid_guid(value):
                errors.append(f'{key}: supply a real, nonzero subscription GUID.')
            else:
                configured.append(value.lower())
    if len(configured) != len(set(configured)):
        errors.append('Every explicit subscription ID must be distinct. Leave optional platform IDs blank to share.')
    for key in GROUPS:
        if values.get(key) and not valid_guid(values[key]):
            errors.append(f'{key}: supply an Entra group OBJECT ID, not its display name or application ID.')
    owners = values.get('securityGroupOwnerObjectIds', [])
    if not isinstance(owners, list) or len(owners) > 100 or any(not valid_guid(x) for x in owners):
        errors.append('securityGroupOwnerObjectIds: supply an array of at most 100 user/service-principal object GUIDs.')
    members = values.get('securityGroupMembers', {})
    if not isinstance(members, dict):
        errors.append('securityGroupMembers: supply an object containing member arrays.')
    else:
        for key, ids in members.items():
            if key not in MEMBER_KEYS:
                errors.append(f'Unknown securityGroupMembers key: {key}')
            if not isinstance(ids, list) or any(not valid_guid(x) for x in ids):
                errors.append(f'securityGroupMembers.{key}: supply an array of directory object GUIDs, not ARM resource IDs.')
    if not re.fullmatch(r'[a-z][a-z0-9-]{1,11}', values.get('organizationPrefix', '')):
        errors.append('organizationPrefix: use 2-12 lowercase letters/digits/hyphens, starting with a letter.')
    if values.get('applicationArchetype') not in ('corp', 'online'):
        errors.append('applicationArchetype: choose corp or online.')
    if values.get('guardrailEffect') not in ('Audit', 'Deny'):
        errors.append('guardrailEffect: choose Audit or Deny.')
    for key in ('owner', 'costCenter', 'organizationName', 'location'):
        if not isinstance(values.get(key), str) or not values[key].strip():
            errors.append(f'{key}: must not be blank.')
    for key in ('enableMicrosoftCloudSecurityBenchmark', 'enableCis', 'enableNis2', 'createSecurityGroups',
                'configureHierarchySettings', 'enableActivityLogCollection'):
        if not isinstance(values.get(key), bool):
            errors.append(f'{key}: must be a boolean.')
    allowed = values.get('allowedLocations', [])
    if not isinstance(allowed, list) or any(not isinstance(x, str) for x in allowed):
        errors.append('allowedLocations: must be an array of Azure region names.')
    elif allowed and values.get('location') not in allowed:
        errors.append('allowedLocations must include location.')
    networks = []
    rfc1918 = [ipaddress.ip_network(c) for c in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')]
    keys = ['hubAddressPrefix', 'applicationAddressPrefix']
    if values.get('nonproductionSubscriptionId'):
        keys.append('nonproductionAddressPrefix')
    for key in keys:
        try:
            network = ipaddress.ip_network(values[key], strict=True)
            if network.version != 4 or not 16 <= network.prefixlen <= 24:
                raise ValueError('requires IPv4 /16 to /24')
            if not any(network.subnet_of(private) for private in rfc1918):
                raise ValueError('requires RFC1918 private space')
            for previous_key, previous in networks:
                if network.overlaps(previous):
                    errors.append(f'{key} overlaps {previous_key}.')
            networks.append((key, network))
        except (ValueError, KeyError, TypeError) as error:
            errors.append(f'{key}: invalid network ({error}).')
    return errors


def az(*args):
    executable = shutil.which('az')
    if not executable:
        raise ValueError('Azure CLI is required for --online.')
    result = subprocess.run([executable, *args, '--output', 'json', '--only-show-errors'],
                            text=True, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f'Azure read check failed ({" ".join(args[:3])}): {result.stderr.strip()}')
    return json.loads(result.stdout or 'null')


def online(values, tenant_id):
    if az('cloud', 'show')['name'] != 'AzureCloud':
        raise ValueError('This catalog is verified for Azure public cloud (AzureCloud) only.')
    account = az('account', 'show')
    if account['tenantId'].lower() != tenant_id.lower():
        raise ValueError('Current Azure CLI tenant differs from --tenant-id. Log into the target tenant first.')
    locations = {x['name'] for x in az('account', 'list-locations')}
    for location in [values['location'], *values['allowedLocations']]:
        if location not in locations:
            raise ValueError(f'Unknown Azure region: {location}')
    def require_provider(key, namespace):
        provider = az('provider', 'show', '--namespace', namespace, '--subscription', values[key])
        if provider['registrationState'] != 'Registered':
            raise ValueError(f'{key}: register {namespace} before deployment (see docs/bootstrap.md).')

    for key in SUBSCRIPTIONS:
        if not values.get(key):
            continue
        account = az('account', 'show', '--subscription', values[key])
        if account['tenantId'].lower() != tenant_id.lower() or account['state'] != 'Enabled':
            raise ValueError(f'{key} must be enabled in the target tenant.')
        resources = az('resource', 'list', '--subscription', values[key])
        groups = az('group', 'list', '--subscription', values[key])
        if resources or groups:
            raise ValueError(f'{key} contains {len(resources)} resources and {len(groups)} resource groups. Use empty subscriptions for initial deployment; review existing ELZ changes with what-if instead.')
        require_provider(key, 'Microsoft.Network')
        if values['enableActivityLogCollection']:
            require_provider(key, 'Microsoft.Insights')
    if values['enableActivityLogCollection']:
        # The workspace lands in the management scaffold, which shares the platform subscription when blank.
        require_provider('managementSubscriptionId' if values.get('managementSubscriptionId') else 'platformSubscriptionId', 'Microsoft.OperationalInsights')
    for key in GROUPS:
        if values.get(key):
            group = az('ad', 'group', 'show', '--group', values[key])
            if not group.get('securityEnabled'):
                raise ValueError(f'{key}: the supplied group is not security-enabled.')
    if values['createSecurityGroups']:
        # Read-only authentication check, not proof of group-write privileges.
        az('rest', '--method', 'get', '--url', 'https://graph.microsoft.com/v1.0/groups?$top=1&$select=id')
        for object_id in values['securityGroupOwnerObjectIds']:
            directory_object = az('rest', '--method', 'get', '--url', f'https://graph.microsoft.com/v1.0/directoryObjects/{object_id}')
            if directory_object.get('@odata.type') not in ('#microsoft.graph.user', '#microsoft.graph.servicePrincipal'):
                raise ValueError('Group owners must be user or service-principal object IDs.')
        member_ids = {object_id for ids in values['securityGroupMembers'].values() for object_id in ids}
        for object_id in member_ids:
            az('rest', '--method', 'get', '--url', f'https://graph.microsoft.com/v1.0/directoryObjects/{object_id}')
    catalog = json.loads((ROOT / 'infra/policy-catalog.json').read_text())
    enabled = {'mcsb': values['enableMicrosoftCloudSecurityBenchmark'], 'cis': values['enableCis'], 'nis2': values['enableNis2']}
    for initiative in catalog['initiatives']:
        if not enabled[initiative['key']]:
            continue
        definition = az('policy', 'set-definition', 'show', '--name', initiative['id'])
        properties = definition.get('properties', definition)
        required = [k for k, v in properties.get('parameters', {}).items() if 'defaultValue' not in v]
        if required:
            raise ValueError(f'{initiative["displayName"]} now requires parameters: {required}')
    print('Azure/Graph read checks passed. They do not prove write privileges. Run tenant validate; Graph resources are not supported by what-if.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parameters', required=True, help='ARM parameter JSON file')
    parser.add_argument('--online', action='store_true', help='Also read target Azure subscriptions, groups and policy catalog')
    parser.add_argument('--tenant-id', help='Required with --online to prevent checking the wrong tenant')
    args = parser.parse_args()
    try:
        values = parameters(args.parameters)
        errors = validate(values)
        if errors:
            raise ValueError('\n'.join(errors))
        if args.online:
            if not valid_guid(args.tenant_id):
                raise ValueError('--online requires a real --tenant-id GUID.')
            online(values, args.tenant_id)
        print('ELZ preflight passed.')
    except (ValueError, KeyError, OSError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
