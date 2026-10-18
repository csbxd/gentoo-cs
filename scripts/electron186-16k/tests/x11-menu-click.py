import ctypes,sys,time
class XButtonEvent(ctypes.Structure):
    _fields_=[('type',ctypes.c_int),('serial',ctypes.c_ulong),('send_event',ctypes.c_int),('display',ctypes.c_void_p),('window',ctypes.c_ulong),('root',ctypes.c_ulong),('subwindow',ctypes.c_ulong),('time',ctypes.c_ulong),('x',ctypes.c_int),('y',ctypes.c_int),('x_root',ctypes.c_int),('y_root',ctypes.c_int),('state',ctypes.c_uint),('button',ctypes.c_uint),('same_screen',ctypes.c_int)]
class XEvent(ctypes.Union):
    _fields_=[('button',XButtonEvent),('pad',ctypes.c_long*24)]
x11=ctypes.CDLL('libX11.so.6');x11.XOpenDisplay.argtypes=[ctypes.c_char_p];x11.XOpenDisplay.restype=ctypes.c_void_p;x11.XDefaultRootWindow.argtypes=[ctypes.c_void_p];x11.XDefaultRootWindow.restype=ctypes.c_ulong;x11.XSendEvent.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.c_int,ctypes.c_long,ctypes.POINTER(XEvent)];x11.XSync.argtypes=[ctypes.c_void_p,ctypes.c_int];x11.XCloseDisplay.argtypes=[ctypes.c_void_p]
display=x11.XOpenDisplay(b':0');window=int(sys.argv[1],0);px,py,rootx,rooty=map(int,sys.argv[2:6])
try:
 for kind,mask in [(4,1<<2),(5,1<<3)]:
  event=XEvent();event.button=XButtonEvent(kind,0,1,display,window,x11.XDefaultRootWindow(display),0,0,px,py,rootx,rooty,0,1,1)
  result=x11.XSendEvent(display,window,0,mask,ctypes.byref(event));x11.XSync(display,0);print('Own menu event',kind,'sent',result);time.sleep(.1)
finally:x11.XCloseDisplay(display)
