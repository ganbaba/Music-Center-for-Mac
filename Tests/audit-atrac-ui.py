#!/usr/bin/env python3
"""Capture actual ATRAC wizard routes in an isolated QA host.
Usage: python3 Tests/audit-atrac-ui.py CONTROL_DIRECTORY QA_ROOT OUTPUT_DIRECTORY
Requires a running ATRACQAApp, a freshly generated QA_ROOT, Accessibility/Screen
Recording access, and a compiled WizardsQAControl.swift named `control`.
Only generated QA audio and libraries are modified; never pass a production root.
"""
import subprocess, pathlib, sys, time, re, json, sqlite3, hashlib, os
os.environ["MUSIC_CENTER_QA_KIND"] = "atrac"
qa=pathlib.Path(sys.argv[1]); area=pathlib.Path(sys.argv[2]); out=pathlib.Path(sys.argv[3])
ctl=qa/'control'
assert (area/'qa-result.txt').read_text().startswith('PASS'), 'requires a completed isolated QA host'
assert (area/'atrac-smoke/PASS.txt').is_file(), 'requires real ATRAC regression fixtures'
assert area.name.startswith('music-center-'), 'requires a dedicated temporary QA root'
assert str(area.resolve()).startswith(('/private/tmp/', '/private/var/folders/')), 'QA root must be temporary'
out.mkdir(exist_ok=True)
states=[]; last_box=None
def run(*args):
    return subprocess.check_output([str(x) for x in args],text=True).strip()
def action(*args):
    for attempt in range(4):
        try: return run(ctl,*args)
        except subprocess.CalledProcessError as error:
            if error.returncode != 5 or attempt == 3: raise
            run(ctl,'activate')
            time.sleep(.2)
def press(label):
    for _ in range(6):
        try: return action('press',label)
        except subprocess.CalledProcessError: time.sleep(.25)
    raise AssertionError('cannot press '+label)
def visible(label):
    for _ in range(100):
        found=action('find',label)
        if label in found: return found
        time.sleep(.2)
    raise AssertionError('missing '+label)
def disabled(label):
    assert 'AXButton off '+label in action('find',label), label
def key(code,flags=0): action('key',str(code),str(flags))
def capture(name,wizard,reference=None):
    global last_box
    wid=action('window')
    raw=out/(name+'-raw.png')
    run('/usr/sbin/screencapture','-x','-o','-l'+wid,raw)
    try: box=list(map(float,action('panel',wizard+'向导').split())); last_box=box
    except subprocess.CalledProcessError:
        assert last_box
        box=last_box
    x,y,w,h,window_width=box
    pixel_width=int(re.search(r'pixelWidth: (\d+)',run('/usr/bin/sips','-g','pixelWidth',raw)).group(1))
    scale=pixel_width/window_width
    cropped=out/(name+'-panel.png')
    run('/usr/bin/sips','-c',str(round(h*scale)),str(round(w*scale)),
        '--cropOffset',str(round(y*scale)),str(round(x*scale)),raw,'--out',cropped)
    image=out/(name+'.jpg')
    run('/usr/bin/sips','-s','format','jpeg','-s','formatOptions','85',cropped,'--out',image)
    states.append(dict(file=image.name,state=name,reference=reference,
        method='production QA window capture; panel crop; JPEG quality 85',
        sha256=hashlib.sha256(image.read_bytes()).hexdigest()))
    print('CAPTURE',name,flush=True)
def open_wizard(name):
    for attempt in range(5):
        try:
            if 'AXButton on 工具' not in action('find','工具'):
                press('主菜单')
            press('工具')
            press(name)
            return
        except (AssertionError,subprocess.CalledProcessError):
            if attempt == 4: raise
            run(ctl,'activate')
            time.sleep(.4)
def choose_directory(location,label='浏览…'):
    press(label); time.sleep(.4); key(5,1179648); action('set',str(location))
    key(36); time.sleep(.5); press('选择'); visible(str(location))
def save_manifest(): (out/'captures.json').write_text(json.dumps(states,ensure_ascii=False,indent=2)+'\n')

try:
    wizard='批量转化ATRAC'
    refs='tools/03-atrac/'
    if '--decoder-only' not in sys.argv[4:]:
        open_wizard(wizard)
        capture('introduction',wizard,refs+'05-entry-with-sample.jpg')
        key(53);assert 'AXButton on 主菜单' in action('find','主菜单')
        open_wizard(wizard);press('下一页');visible('选择要转换的文件类型');disabled('下一页')
        capture('options-empty',wizard,refs+'06-files-found-options-empty.jpg')
        press('AAC: 优先考虑文件大小');press('勿移出原始文件夹')
        capture('aac-keep',wizard,refs+'07-aac-keep-original.jpg')
        press('下一页');visible('计算已完成');key(36);visible('计算已完成')
        capture('aac-ready',wizard,refs+'11-space-check-ready-to-start.jpg')
        press('开始');visible('正在转换文件')
        key(53);visible('正在转换文件')
        capture('aac-progress',wizard,refs+'16-flac-progress-100-unfilled.jpg')
        visible('文件转换完成')
        capture('aac-complete',wizard,refs+'12-aac-completed.jpg')
        press('确定');open_wizard(wizard);press('下一页');visible('无法在我的音乐库中找到')
        capture('no-atrac',wizard,'old/atrac-scan-result.jpg')
        press('确定');press('加入 ATRAC');time.sleep(.7)
        open_wizard(wizard);press('下一页');visible('选择要转换的文件类型')
        press('FLAC: 优先考虑声音质量');press('移动至指定文件夹');disabled('下一页')
        capture('move-empty',wizard,refs+'09-move-original-controls-enabled.jpg')
        original_folder=area/'moved-originals';original_folder.mkdir()
        choose_directory(original_folder)
        capture('flac-move-selected',wizard,refs+'09-move-original-controls-enabled.jpg')
        press('下一页');visible('计算已完成')
        capture('flac-ready',wizard,refs+'14-flac-ready-to-start.jpg')
        press('开始');visible('正在转换文件')
        capture('flac-progress',wizard,refs+'16-flac-progress-100-unfilled.jpg')
        visible('文件转换完成')
        capture('flac-complete',wizard,refs+'15-flac-completed.jpg')
        assert len(list(original_folder.glob('*.oma')))==1
        with sqlite3.connect((area/'ui-library/Library.sqlite').as_uri()+'?mode=ro',uri=True) as db:
            paths=[r[0] for r in db.execute('select path from tracks')]
            assert len(paths)==2 and {pathlib.Path(p).suffix for p in paths}=={'.m4a','.flac'}
        press('确定');press('加入 ATRAC');time.sleep(.7)
        open_wizard(wizard);press('下一页');visible('选择要转换的文件类型')
        press('FLAC: 优先考虑声音质量');press('勿移出原始文件夹')
        capture('flac-keep',wizard,refs+'08-flac-keep-original.jpg')
        press('下一页');visible('计算已完成');press('开始');visible('正在转换文件');press('停止')
        visible('文件转换已停止')
        capture('stopped',wizard)
        press('确定');press('加入损坏文件');time.sleep(.5)
        open_wizard(wizard);press('下一页');visible('选择要转换的文件类型')
        press('FLAC: 优先考虑声音质量');press('勿移出原始文件夹');press('下一页');visible('计算已完成');press('开始')
        visible('部分文件未能完成转换')
        capture('partial-failure',wizard)
        press('显示详情');visible('invalid.oma')
        capture('failure-details',wizard)
        assert (area/'invalid.oma').read_text()=='invalid ATRAC'
        press('确定');press('紧凑窗口');open_wizard(wizard);press('下一页');visible('选择要转换的文件类型')
        capture('compact',wizard,refs+'06-files-found-options-empty.jpg')
        key(53);assert 'AXButton on 主菜单' in action('find','主菜单')
        press('紧凑窗口');press('提供解码器')
        open_wizard(wizard);press('下一页');visible('选择要转换的文件类型')
        press('AAC: 优先考虑文件大小');press('勿移出原始文件夹');press('下一页')
    else:
        states=json.loads((out/'captures.json').read_text())
        assert len(states)==17, 'supplement requires the 17 captured states'
        for item in states:
            assert hashlib.sha256((out/item['file']).read_bytes()).hexdigest()==item['sha256']
        press('加入损坏文件');time.sleep(.5)
        press('提供解码器')
        open_wizard(wizard);press('下一页');visible('选择要转换的文件类型')
        press('AAC: 优先考虑文件大小');press('勿移出原始文件夹');press('下一页')
    visible('转换 ATRAC 需要本机 FFmpeg');key(53);visible('选择要转换的文件类型')
    last_box=list(map(float,action('panel',wizard+'向导').split()))
    press('下一页');visible('转换 ATRAC 需要本机 FFmpeg')
    key(5,1179648);action('set',str(area));key(36);time.sleep(.5)
    action('hit','invalid.oma');press('选择');visible('所选文件不能执行')
    capture('decoder-error',wizard)
    key(36);visible('选择要转换的文件类型');press('取消')
    print(('SUPPLEMENT: decoder-only checks; 17 existing screenshots retained. ' if '--decoder-only' in sys.argv[4:] else '')+'PASS: actual ATRAC routes, AAC/FLAC completion, empty scan, move controls, Return/Escape protection, real cancellation, partial failure, details, compact and missing-decoder selection validated.',flush=True)
finally:
    save_manifest()
