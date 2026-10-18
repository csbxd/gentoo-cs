import json, os, pathlib, resource, subprocess, sys, time
root = pathlib.Path(__file__).resolve().parent
runtime = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root.parent / 'snapshot-test/runtime'
run_dir = root / ('run-' + str(time.time_ns()))
run_dir.mkdir()
env = os.environ.copy()
for name in ('data', 'config', 'cache'):
    (run_dir / name).mkdir(exist_ok=True)
env.update(ELECTRON_RUN_AS_NODE='1', THUNDER_RUNTIME=str(runtime),
           SDK_TEST_ROOT=str(run_dir), LD_LIBRARY_PATH=str(runtime),
           XDG_DATA_HOME=str(run_dir/'data'), XDG_CONFIG_HOME=str(run_dir/'config'),
           XDG_CACHE_HOME=str(run_dir/'cache'))
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
with (root/'download-test.log').open('w') as log:
    try:
        result = subprocess.run([str(runtime/'thunder'), str(root/'download-test.js')],
                                env=env, stdout=log, stderr=subprocess.STDOUT, timeout=40)
        status = {'exitCode': result.returncode}
    except subprocess.TimeoutExpired:
        status = {'timedOut': True}
status.update(runtime=str(runtime), runDirectory=str(run_dir), pageSize=os.sysconf('SC_PAGE_SIZE'))
for line in (root/'download-test.log').read_text(errors='replace').splitlines():
    if line.startswith('RESULT '):
        status.update(json.loads(line[7:]))
(root/'result.json').write_text(json.dumps(status, indent=2))
print(json.dumps(status))
