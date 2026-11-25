#!/usr/bin/env python3
"""Build an isolated host: production property views plus real SQLite/audio smoke checks."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
stage = Path(tempfile.mkdtemp(prefix='music-center-properties-qa-'))
for name in ['Sources', 'Resources', 'MusicCenterUIRecreation.xcodeproj']:
    shutil.copytree(root / name, stage / name)
(stage / 'Sources/PreviewApp.swift').write_text(
    (root / 'Tests/PropertiesQAApp.swift').read_text() + '\n' +
    (root / 'Tests/PropertiesSmoke.swift').read_text())
project = stage / 'MusicCenterUIRecreation.xcodeproj/project.pbxproj'
project.write_text(project.read_text()
    .replace('local.musiccenter.uirecreation', 'local.musiccenter.uirecreation.propertiesqa')
    .replace('PRODUCT_NAME = "Music Center UI Preview";', 'PRODUCT_NAME = "Music Center Properties QA";'))
print('QA_STAGE=' + str(stage), flush=True)
subprocess.run(['xcodebuild', '-project', str(stage / 'MusicCenterUIRecreation.xcodeproj'),
    '-scheme', 'MusicCenterUIRecreation', '-configuration', 'Release',
    '-derivedDataPath', str(stage / 'Build'), 'CODE_SIGNING_ALLOWED=NO', 'build'], check=True)
print('QA_APP=' + str(stage / 'Build/Build/Products/Release/Music Center Properties QA.app'), flush=True)
