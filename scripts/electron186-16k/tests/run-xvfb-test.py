import json
import os
import pathlib
import resource
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time

resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
root = pathlib.Path(__file__).resolve().parent
runtime = pathlib.Path(sys.argv[1]).resolve()
run = root / (sys.argv[2] if len(sys.argv) > 2 else 'run')
run.mkdir(exist_ok=True)
for name in ['data', 'config', 'cache', 'profile', 'runtime']:
    (run / name).mkdir(exist_ok=True)
os.chmod(run / 'runtime', 0o700)
env = os.environ.copy()
env.update(DISPLAY=':159', LD_LIBRARY_PATH=str(runtime), XDG_DATA_HOME=str(run / 'data'),
           XDG_CONFIG_HOME=str(run / 'config'), XDG_CACHE_HOME=str(run / 'cache'),
           XDG_RUNTIME_DIR=str(run / 'runtime'))
xvfb_log = open(run / 'xvfb.log', 'w')
app_log = open(run / 'app.log', 'w')
xvfb = subprocess.Popen(['Xvfb', ':159', '-screen', '0', '1280x900x24', '-nolisten', 'tcp'],
                        stdout=xvfb_log, stderr=subprocess.STDOUT, start_new_session=True)
app = None
observer = None
observer_log = None


def stop_observer():
    if observer is None:
        return
    if observer.poll() is None:
        observer.send_signal(signal.SIGTERM)
        try:
            observer.wait(timeout=4)
        except subprocess.TimeoutExpired:
            observer.kill()
            observer.wait(timeout=2)


try:
    for _ in range(30):
        if pathlib.Path('/tmp/.X11-unix/X159').exists():
            break
        if xvfb.poll() is not None:
            raise RuntimeError('Xvfb exited')
        time.sleep(.1)
    node_env = env.copy()
    node_env.update(ELECTRON_RUN_AS_NODE='1', THUNDER_RUNTIME=str(runtime))
    with open(run / 'native-addons.log', 'w') as handle:
        probe = subprocess.run([str(runtime / 'thunder'), str(root / 'probe-addons.js')],
                               env=node_env, stdout=handle, stderr=subprocess.STDOUT, timeout=15)
    (run / 'native-addons.exit').write_text(str(probe.returncode))
    cmd = ['dbus-run-session', '--', str(runtime / 'thunder'), '--no-sandbox', '--disable-gpu',
           '--enable-logging', '--v=1', '--user-data-dir=' + str(run / 'profile')]
    cmd.extend(shlex.split(os.environ.get('THUNDER_EXTRA_FLAGS', '')))
    result = {'runtime': str(runtime), 'frames': [], 'native_addons_exit_code': probe.returncode}
    if os.environ.get('THUNDER_CDP') == '1':
        node = shutil.which('node')
        if node is None:
            raise RuntimeError('THUNDER_CDP=1 requires Node.js with built-in WebSocket and fetch')
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
            listener.bind(('127.0.0.1', 0))
            cdp_port = listener.getsockname()[1]
        cmd.extend(['--remote-debugging-address=127.0.0.1', '--remote-debugging-port=' + str(cdp_port)])
        (run / 'cdp-port.txt').write_text(str(cdp_port) + '\n')
        observer_log = open(run / 'cdp-observer.log', 'w')
        observer = subprocess.Popen([node, str(root / 'cdp-observe.mjs'), str(cdp_port), str(run), '90000'],
                                    stdout=observer_log, stderr=subprocess.STDOUT, start_new_session=True)
        result.update(cdp_port=cdp_port, cdp_endpoint='http://127.0.0.1:' + str(cdp_port),
                      cdp_summary=str(run / 'cdp-pages.json'))
    if os.environ.get('THUNDER_APP_PREFIX'):
        cmd = cmd[:2] + shlex.split(os.environ['THUNDER_APP_PREFIX']) + cmd[2:]
    if os.environ.get('THUNDER_RENDERER_PREFIX'):
        cmd.append('--renderer-cmd-prefix=' + os.environ['THUNDER_RENDERER_PREFIX'])
    app = subprocess.Popen(cmd, env=env, stdout=app_log, stderr=subprocess.STDOUT, start_new_session=True)
    result.update(pid=app.pid, command=cmd)
    for second in range(1, 31):
        time.sleep(1)
        if app.poll() is not None:
            result.update(exit_code=app.returncode, exited_after_seconds=second)
            break
        if second in [5, 15, 30]:
            frame = run / ('screen-%02d.png' % second)
            subprocess.run(['import', '-display', ':159', '-window', 'root', str(frame)],
                           env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            result['frames'].append(str(frame))
            with open(run / ('windows-%02d.log' % second), 'w') as handle:
                subprocess.run(['xwininfo', '-display', ':159', '-root', '-tree'], env=env,
                               stdout=handle, stderr=subprocess.STDOUT, timeout=5)
    result['running_after_30_seconds'] = app.poll() is None
    if result['running_after_30_seconds'] and os.environ.get('THUNDER_GRACEFUL_EXIT') == '1':
        children = pathlib.Path('/proc/' + str(app.pid) + '/task/' + str(app.pid) + '/children')
        for candidate in children.read_text().split():
            try:
                if pathlib.Path('/proc/' + candidate + '/exe').resolve() == runtime / 'thunder':
                    os.kill(int(candidate), signal.SIGINT)
                    result['graceful_exit_signal_pid'] = int(candidate)
                    break
            except FileNotFoundError:
                pass
        try:
            result['graceful_exit_code'] = app.wait(timeout=15)
        except subprocess.TimeoutExpired:
            result['graceful_exit_timed_out'] = True
    stop_observer()
    if observer is not None:
        result['cdp_observer_exit_code'] = observer.returncode
        if (run / 'cdp-pages.json').exists():
            observed = json.loads((run / 'cdp-pages.json').read_text())
            result.update(cdp_page_count=observed['pageCount'],
                          cdp_javascript_exception_count=observed['javascriptExceptionCount'],
                          cdp_crash_or_detach_event_count=observed['crashOrDetachEventCount'])
    (run / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
finally:
    stop_observer()
    for process in [app, xvfb]:
        if process is None:
            continue
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            continue
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    if observer_log is not None:
        observer_log.close()
    app_log.close()
    xvfb_log.close()
