import ctypes
import sys
import time

x11 = ctypes.CDLL('libX11.so.6')
xtst = ctypes.CDLL('libXtst.so.6')
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XFlush.argtypes = [ctypes.c_void_p]
x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
display_name = sys.argv[3] if len(sys.argv) > 3 else ':159'
display = x11.XOpenDisplay(display_name.encode())
if not display:
    raise RuntimeError('Requested test display is not running')
try:
    x, y = map(int, sys.argv[1:3])
    xtst.XTestFakeMotionEvent(display, -1, x, y, 0)
    x11.XFlush(display)
    time.sleep(.1)
    xtst.XTestFakeButtonEvent(display, 1, 1, 0)
    xtst.XTestFakeButtonEvent(display, 1, 0, 0)
    x11.XFlush(display)
    print('Clicked test display coordinate', x, y)
finally:
    x11.XCloseDisplay(display)
