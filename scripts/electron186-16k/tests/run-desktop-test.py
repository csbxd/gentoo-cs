import json, os, pathlib, re, resource, signal, socket, subprocess, sys, time
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
root=pathlib.Path(__file__).resolve().parent
workspace=root.parent.parent
runtime=workspace/'outputs/thunder-electron186-16k'
run=root/(sys.argv[1] if len(sys.argv)>1 else 'desktop-final');run.mkdir(exist_ok=True)
for name in ['data','config','cache','profile']:(run/name).mkdir(exist_ok=True)
env=os.environ.copy();env.update(DISPLAY=':0',XDG_DATA_HOME=str(run/'data'),XDG_CONFIG_HOME=str(run/'config'),XDG_CACHE_HOME=str(run/'cache'))
with socket.socket() as listener:
 listener.bind(('127.0.0.1',0));port=listener.getsockname()[1]
cmd=[str(runtime/'run-thunder.sh'),'--enable-logging','--v=1','--user-data-dir='+str(run/'profile'),'--remote-debugging-address=127.0.0.1','--remote-debugging-port='+str(port)]
app_log=open(run/'app.log','w');observer_log=open(run/'cdp-observer.log','w')
observer=subprocess.Popen(['node',str(root/'cdp-observe.mjs'),str(port),str(run),'170000'],stdout=observer_log,stderr=subprocess.STDOUT,start_new_session=True)
app=subprocess.Popen(cmd,env=env,stdout=app_log,stderr=subprocess.STDOUT,start_new_session=True)
result={'pid':app.pid,'port':port,'command':cmd,'default_gpu_flags':True,'desktop_display':':0','app_window_screenshots':[]}
(run/'live.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
try:
 for second in range(1,301):
  time.sleep(1)
  if app.poll() is not None:
   result['exit_code']=app.returncode;result['exited_after_seconds']=second;break
  if second in [10,15]:
   inventory=subprocess.check_output(['xwininfo','-display',':0','-root','-tree'],text=True)
   app_lines=[line for line in inventory.splitlines() if 'com.xunlei.download' in line]
   (run/('app-windows-%02d.txt'%second)).write_text('\n'.join(app_lines)+'\n')
   for index,line in enumerate(app_lines):
    match=re.search(r'0x[0-9a-f]+',line)
    if not match:continue
    image=run/('app-window-%02d-%d.png'%(second,index))
    subprocess.run(['import','-display',':0','-window',match.group(),str(image)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5)
    result['app_window_screenshots'].append(str(image))
 result['running_at_observation_end']=app.poll() is None
finally:
 if observer.poll() is None:
  observer.send_signal(signal.SIGTERM)
  try:observer.wait(timeout=4)
  except subprocess.TimeoutExpired:observer.kill();observer.wait()
 result['observer_exit_code']=observer.returncode
 (run/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2),flush=True)
 if app.poll() is None:
  result['test_cleanup_required']=True
  os.killpg(app.pid,signal.SIGTERM)
  try:app.wait(timeout=3)
  except subprocess.TimeoutExpired:os.killpg(app.pid,signal.SIGKILL);app.wait()
 app_log.close();observer_log.close()
