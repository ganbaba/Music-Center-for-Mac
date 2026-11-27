#!/usr/bin/env python3
"""Build an isolated host; launch with QA_ROOT ATRAC_SAMPLE FFMPEG SLOW_FFMPEG."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
stage = Path(tempfile.mkdtemp(prefix='music-center-atrac-qa-'))
for name in ['Sources', 'Resources', 'MusicCenterForMac.xcodeproj']:
    shutil.copytree(root / name, stage / name)
(stage / 'Sources/PreviewApp.swift').write_text('\n'.join(
    (root / 'Tests' / name).read_text()
    for name in ['ATRACQAApp.swift', 'ATRACSmoke.swift', 'PropertiesSmoke.swift']))
project = stage / 'MusicCenterForMac.xcodeproj/project.pbxproj'
project.write_text(project.read_text()
    .replace('local.musiccenter.uirecreation', 'local.musiccenter.uirecreation.atracqa')
    .replace('PRODUCT_NAME = "Music Center for Mac";', 'PRODUCT_NAME = "Music Center ATRAC QA";'))
print('QA_STAGE=' + str(stage), flush=True)
subprocess.run(['xcodebuild', '-project', str(stage / 'MusicCenterForMac.xcodeproj'),
    '-scheme', 'MusicCenterForMac', '-configuration', 'Release',
    '-derivedDataPath', str(stage / 'Build'), 'CODE_SIGNING_ALLOWED=NO', 'build'], check=True)
app = stage / 'Build/Build/Products/Release/Music Center ATRAC QA.app'
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
print('QA_APP=' + str(app), flush=True)
