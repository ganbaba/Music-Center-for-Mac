#!/usr/bin/env python3
"""Capture real wizard routes in an isolated QA host.
Usage: python3 Tests/audit-wizards-ui.py CONTROL_DIRECTORY QA_ROOT OUTPUT_DIRECTORY
Requires a running WizardsQAApp, a freshly generated QA_ROOT, Accessibility/Screen
Recording access, and a compiled WizardsQAControl.swift named `control`.
Only temporary QA databases are locked or modified; never pass a production root.
"""
import subprocess, pathlib, sys, time, re, json, sqlite3, hashlib
qa=pathlib.Path(sys.argv[1]); area=pathlib.Path(sys.argv[2]); out=pathlib.Path(sys.argv[3])
ctl=qa/'control'
assert (area/'qa-result.txt').read_text().startswith('PASS'), 'requires a completed isolated QA host'
assert (area/'property-smoke/PASS.txt').is_file(), 'requires generated smoke fixtures'
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
    for _ in range(14):
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
def lock_database(tag):
    marker=out/(tag+'.ready')
    child=subprocess.Popen([sys.executable,'-c',
        "import sqlite3,time,pathlib,sys; c=sqlite3.connect(sys.argv[1]); c.execute('BEGIN EXCLUSIVE'); pathlib.Path(sys.argv[2]).touch(); time.sleep(2.2); c.rollback(); c.close()",
        str(area/'ui-library/Library.sqlite'),str(marker)])
    for _ in range(60):
        if marker.exists(): return child
        time.sleep(.02)
    raise AssertionError('could not acquire test database lock')
def select_backup(location):
    press('浏览…');time.sleep(.4);key(5,1179648);action('set',str(location.parent))
    key(36);time.sleep(.5);visible(location.name);action('hit',location.name);time.sleep(.2);press('选择')
def save_manifest(): (out/'captures.json').write_text(json.dumps(states,ensure_ascii=False,indent=2)+'\n')

try:
    good=area/'backup-good';bad=area/'backup-bad';good.mkdir(exist_ok=True);bad.mkdir(exist_ok=True)
    open_wizard('数据备份')
    capture('backup-introduction','数据备份','tools/01-backup/01-entry.jpg')
    key(53); assert 'AXButton on 主菜单' in action('find','主菜单'), 'Escape closes idle wizard'
    open_wizard('数据备份')
    lock=lock_database('search')
    press('下一步');visible('正在搜索备份数据')
    capture('backup-searching','数据备份')
    lock.wait();visible('备份数据搜索已完成');disabled('下一步')
    capture('backup-empty','数据备份','tools/01-backup/03-options-empty.jpg')
    action('fill','备份数据名称','x'*33);disabled('下一步');visible('最多为 32')
    action('fill','备份数据名称','Visual QA')
    action('fill','备注','视觉验收\n保留全部曲库记录')
    choose_directory(good)
    capture('backup-filled','数据备份','tools/01-backup/04-options-filled.jpg')
    press('下一步');visible('备份数据保存准备已完成')
    key(36);visible('备份数据保存准备已完成')
    capture('backup-confirm','数据备份','tools/01-backup/05-ready-to-start.jpg')
    lock=lock_database('write')
    press('开始');visible('正在备份数据')
    key(53);visible('正在备份数据')
    capture('backup-writing','数据备份','tools/01-backup/15-backup-progress-100-unfilled.jpg')
    lock.wait();visible('备份已完成')
    capture('backup-complete','数据备份','tools/01-backup/06-completed.jpg')
    archive=good/'Visual QA.musiccenterbackup'
    with sqlite3.connect(archive.as_uri()+'?mode=ro',uri=True) as db:
        assert db.execute('select count(*) from tracks').fetchone()==(3,)
        assert db.execute('select notes from music_center_backup_details').fetchone()[0]=='视觉验收\n保留全部曲库记录'
    press('确定')
    open_wizard('数据备份');press('下一步');visible('备份数据搜索已完成')
    choose_directory(bad);action('fill','备份数据名称','Runtime QA');press('下一步')
    visible(str(bad/'Runtime QA.musiccenterbackup'))
    bad.rmdir();bad.write_text('protected test obstruction')
    press('开始');visible('无法写入指定文件夹')
    capture('backup-write-error','数据备份','tools/01-backup/13-runtime-write-failed.jpg')
    key(36);visible('备份数据搜索已完成')
    assert bad.read_text()=='protected test obstruction'
    press('取消')
    open_wizard('恢复备份数据')
    capture('restore-introduction','恢复备份数据','tools/02-restore/01-entry.jpg')
    press('下一步');disabled('下一步')
    capture('restore-empty','恢复备份数据','tools/02-restore/02-select-backup-empty.jpg')
    select_backup(area/'property-smoke/corrupt.musiccenterbackup')
    visible('无法读取此备份');disabled('下一步')
    capture('restore-invalid','恢复备份数据','tools/02-restore/03-invalid-backup-directory.jpg')
    select_backup(archive);visible('视觉验收')
    capture('restore-selected','恢复备份数据','tools/02-restore/04-valid-backup-metadata.jpg')
    press('下一步');visible('已准备恢复备份数据');key(36);visible('已准备恢复备份数据')
    capture('restore-confirm','恢复备份数据','tools/02-restore/05-ready-to-start.jpg')
    lock=lock_database('restore')
    press('开始')
    visible('正在保存恢复前备份')
    key(53);visible('正在保存恢复前备份')
    disabled('停止')
    capture('restore-working','恢复备份数据','restore/01-progress-72.png')
    lock.wait();visible('恢复已完成')
    capture('restore-complete','恢复备份数据','restore/02-completed.png')
    with sqlite3.connect((area/'ui-library/Library.sqlite').as_uri()+'?mode=ro',uri=True) as db:
        assert db.execute('select count(*) from tracks').fetchone()==(3,)
    press('确定')
    open_wizard('恢复备份数据');press('下一步');select_backup(archive);visible('视觉验收')
    press('恢复到指定文件夹')
    dest=area/'restore-audio';dest.mkdir()
    choose_directory(dest,'浏览恢复文件夹')
    capture('restore-custom','恢复备份数据','old/restore-custom-destination.jpg')
    press('下一步');visible(str(dest/'Music Center'))
    capture('restore-custom-confirm','恢复备份数据','tools/02-restore/05-ready-to-start.jpg')
    (dest/'Music Center').write_text('protected destination')
    press('开始');visible('已有 Music Center 项目')
    capture('restore-runtime-error','恢复备份数据','restore/03-runtime-write-failed.png')
    key(36);visible('请重新选择备份后重试')
    assert (dest/'Music Center').read_text()=='protected destination'
    press('取消');press('紧凑窗口')
    open_wizard('数据备份');press('下一步');visible('备份数据搜索已完成')
    capture('backup-compact','数据备份','tools/01-backup/03-options-empty.jpg')
    key(53);assert 'AXButton on 主菜单' in action('find','主菜单')
    open_wizard('恢复备份数据');press('下一步')
    capture('restore-compact','恢复备份数据','tools/02-restore/02-select-backup-empty.jpg')
    key(53);assert 'AXButton on 主菜单' in action('find','主菜单')
    print('PASS: all captured states are production routes; form validation, Return protection, Escape behavior, real write/restore and file preservation verified.',flush=True)
finally:
    save_manifest()
