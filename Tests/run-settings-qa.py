#!/usr/bin/env python3
"""Build an isolated settings host and preference smoke checks using production views."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
stage = Path(tempfile.mkdtemp(prefix='music-center-settings-qa-'))
for name in ['Sources', 'Resources', 'MusicCenterForMac.xcodeproj']:
    shutil.copytree(root / name, stage / name)
(stage / 'Sources/PreviewApp.swift').write_text(
    (root / 'Tests/SettingsQAApp.swift').read_text() + '\n' +
    (root / 'Tests/SettingsPreferencesSmoke.swift').read_text())
project = stage / 'MusicCenterForMac.xcodeproj/project.pbxproj'
project.write_text(project.read_text()
    .replace('local.musiccenter.uirecreation', 'local.musiccenter.uirecreation.settingsqa')
    .replace('PRODUCT_NAME = "Music Center for Mac";', 'PRODUCT_NAME = "Music Center Settings QA";'))
subprocess.run(['xcodebuild', '-project', str(stage / 'MusicCenterForMac.xcodeproj'),
    '-scheme', 'MusicCenterForMac', '-configuration', 'Release',
    '-derivedDataPath', str(stage / 'Build'), 'CODE_SIGNING_ALLOWED=NO', 'build'], check=True)
print('Open this isolated host to run its startup smoke checks and inspect all settings:')
print(stage / 'Build/Build/Products/Release/Music Center Settings QA.app')
