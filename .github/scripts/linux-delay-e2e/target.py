#!/usr/bin/python3
"""Log actual delivered mouse events with monotonic timestamps on Xvfb."""
import pathlib
import sys
import time
import tkinter as tk

events = pathlib.Path(sys.argv[1])
events.write_text('')
root = tk.Tk()
root.title('Isolated start delay test target')
root.geometry('200x200+1050+800')

def clicked(_event):
    with events.open('a') as stream:
        stream.write(f'{time.monotonic()}\n')

root.bind('<ButtonPress-1>', clicked)
root.mainloop()
