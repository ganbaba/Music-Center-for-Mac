#!/usr/bin/env python3
"""Run menus/dialogs against the production app and an isolated generated library."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
stage = Path(tempfile.mkdtemp(prefix='music-center-menus-qa-'))
for name in ['Sources', 'Resources', 'MusicCenterForMac.xcodeproj']:
    shutil.copytree(root / name, stage / name)
(stage / 'Sources/PreviewApp.swift').write_text('\n'.join((root / 'Tests' / name).read_text() for name in
    ['MenusQAApp.swift', 'MenusSmoke.swift', 'PropertiesSmoke.swift', 'SettingsPreferencesSmoke.swift']))
project = stage / 'MusicCenterForMac.xcodeproj/project.pbxproj'
project.write_text(project.read_text()
    .replace('local.musiccenter.uirecreation', 'local.musiccenter.uirecreation.menusqa')
    .replace('PRODUCT_NAME = "Music Center for Mac";', 'PRODUCT_NAME = "Music Center Menus QA";'))
print('QA_STAGE=' + str(stage), flush=True)
subprocess.run(['xcodebuild', '-project', str(stage / 'MusicCenterForMac.xcodeproj'),
    '-scheme', 'MusicCenterForMac', '-configuration', 'Release',
    '-derivedDataPath', str(stage / 'Build'), 'CODE_SIGNING_ALLOWED=NO', 'build'], check=True)
print('QA_APP=' + str(stage / 'Build/Build/Products/Release/Music Center Menus QA.app'), flush=True)
