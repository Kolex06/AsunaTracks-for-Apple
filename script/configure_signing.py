#!/usr/bin/env python3
"""Configure a source checkout for your Apple team; --check never changes files."""
import argparse
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parent.parent
PROJECT = Path('AsunaTracks.xcodeproj/project.pbxproj')
ENTITLEMENTS = [Path('AsunaTracks/AsunaTracks.entitlements'), Path('AsunaTracks/macOS/AsunaTracksMac.entitlements'), Path('AsunaTracks/macOS/AsunaTracksMacWidgets.entitlements')]
CACHE = Path('AsunaTracks/Shared/ProgressSnapshot.swift')
API = Path('AsunaTracks/iOS/APIClient.swift')

def prepare(root, team=None, bundle=None):
    paths = [PROJECT, *ENTITLEMENTS, CACHE, API]
    original = {p: (root / p).read_text() for p in paths}
    updated = dict(original)
    project = original[PROJECT]
    bases = re.findall(r'"ASUNATRACKS_APP_BUNDLE_ID" = "([^"]+)";', project)
    teams = re.findall(r'"DEVELOPMENT_TEAM" = "([^"]+)";', project)
    if len(bases) != 2 or len(set(bases)) != 1 or len(teams) != 12 or len(set(teams)) != 1:
        raise ValueError('Project identifiers or teams differ between targets/configurations. Start from a fresh source checkout or resolve the overrides first.')
    old_base, old_team = bases[0], teams[0]
    # Verify target expressions rather than silently overwriting manual target overrides.
    expressions = re.findall(r'"PRODUCT_BUNDLE_IDENTIFIER" = "([^"]+)";', project)
    expected = {'$(ASUNATRACKS_APP_BUNDLE_ID)' + suffix for suffix in ['', '.widgets', '.watchkitapp', '.watchkitapp.widgets', '.mac', '.mac.widgets']}
    if len(expressions) != 12 or any(expressions.count(value) != 2 for value in expected):
        raise ValueError('A target Bundle Identifier was overridden. Restore the shared expressions before configuring signing.')
    companions = re.findall(r'"INFOPLIST_KEY_WKCompanionAppBundleIdentifier" = "([^"]+)";', project)
    if companions != ['$(ASUNATRACKS_APP_BUNDLE_ID)'] * 2:
        raise ValueError('Watch companion ID must use $(ASUNATRACKS_APP_BUNDLE_ID) in Debug and Release.')
    groups = [plistlib.loads(original[p].encode())['com.apple.security.application-groups'] for p in ENTITLEMENTS]
    if any(len(group) != 1 for group in groups) or groups[1] != groups[2]:
        raise ValueError('App and widget App Groups must match.')
    mobile, mac = groups[0][0], groups[1][0]
    cached = re.findall(r'static let group = "([^"]+)"', original[CACHE])
    if cached != [mac, mobile]:
        raise ValueError('Runtime widget cache groups do not match the entitlements.')
    session_groups = re.findall(r'result\[kSecAttrAccessGroup as String\] = "([^"]+)"', original[API])
    if len(session_groups) != 2 or session_groups[1] != mobile or not session_groups[0].startswith(old_team + '.'):
        raise ValueError('Session sharing groups do not match the app configuration.')
    if not mobile.startswith('group.') or not mac.startswith(old_team + '.'):
        raise ValueError('App Groups are not configured for the selected team.')
    if team is None:
        return original, updated, (old_team, old_base, mobile, mac)
    new_mobile, new_mac = 'group.' + bundle, team + '.' + bundle
    updated[PROJECT] = project.replace('"ASUNATRACKS_APP_BUNDLE_ID" = "' + old_base + '";', '"ASUNATRACKS_APP_BUNDLE_ID" = "' + bundle + '";').replace('"DEVELOPMENT_TEAM" = "' + old_team + '";', '"DEVELOPMENT_TEAM" = "' + team + '";')
    for path, group, new_group in zip(ENTITLEMENTS, [mobile, mac, mac], [new_mobile, new_mac, new_mac]):
        updated[path] = original[path].replace('<string>' + group + '</string>', '<string>' + new_group + '</string>')
    updated[CACHE] = original[CACHE].replace('"' + mac + '"', '"' + new_mac + '"').replace('"' + mobile + '"', '"' + new_mobile + '"')
    # Preserve the publisher's existing session group when the base ID stays the same.
    new_session = team + session_groups[0][len(old_team):] if bundle == old_base else team + '.' + bundle + '.widget-session'
    updated[API] = original[API].replace('"' + session_groups[0] + '"', '"' + new_session + '"').replace('"' + mobile + '"', '"' + new_mobile + '"')
    return original, updated, (team, bundle, new_mobile, new_mac)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Validate the current checkout without editing files')
    parser.add_argument('--team', help='Your 10-character Apple team ID')
    parser.add_argument('--bundle-id', help='Your unique base bundle ID, e.g. com.example.asunatracks')
    args = parser.parse_args()
    if args.check and (args.team or args.bundle_id):
        parser.error('--check validates the current checkout; omit --team and --bundle-id')
    if not args.check:
        if not args.team or not re.fullmatch(r'[A-Z0-9]{10}', args.team):
            parser.error('--team must be your 10-character Apple team ID')
        if not args.bundle_id or not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', args.bundle_id):
            parser.error('--bundle-id must be a reverse-DNS identifier')
    try:
        original, updated, values = prepare(ROOT, args.team, args.bundle_id)
        for path, content in updated.items():
            if content != original[path]:
                (ROOT / path).write_text(content)
        print(('Checked' if args.check else 'Configured') + ': team=' + values[0] + ', base=' + values[1])
        print('Mobile/Watch App Group: ' + values[2])
        print('Mac App Group: ' + values[3])
        print('App, Watch companion, widget IDs and runtime sharing groups are consistent.')
        if not args.check:
            print('Choose this team in Xcode and provision these App Groups for its app/extension IDs. This tool does not create Apple portal capabilities or profiles.')
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, 'Setup check failed: ' + str(error) + '\n')

if __name__ == '__main__':
    main()
