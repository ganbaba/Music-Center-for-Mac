#!/usr/bin/env python3
"""Build the production help-menu windows with an isolated temporary library."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
stage = Path(tempfile.mkdtemp(prefix='music-center-information-host-'))
for name in ['Sources', 'Resources', 'MusicCenterForMac.xcodeproj']:
    shutil.copytree(root / name, stage / name)
(stage / 'Sources/PreviewApp.swift').write_text('\n'.join((root / 'Tests' / name).read_text() for name in
    ['InformationQAApp.swift', 'InformationSmoke.swift']))
project = stage / 'MusicCenterForMac.xcodeproj/project.pbxproj'
project.write_text(project.read_text()
    .replace('local.musiccenter.uirecreation', 'local.musiccenter.uirecreation.informationqa')
    .replace('PRODUCT_NAME = "Music Center for Mac";', 'PRODUCT_NAME = "Music Center Information QA";'))
print('QA_STAGE=' + str(stage), flush=True)
subprocess.run(['xcodebuild', '-project', str(stage / 'MusicCenterForMac.xcodeproj'),
    '-scheme', 'MusicCenterForMac', '-configuration', 'Release',
    '-derivedDataPath', str(stage / 'Build'), 'CODE_SIGNING_ALLOWED=NO', 'build'], check=True)
print('QA_APP=' + str(stage / 'Build/Build/Products/Release/Music Center Information QA.app'), flush=True)
