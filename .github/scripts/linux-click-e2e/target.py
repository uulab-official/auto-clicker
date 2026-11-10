#!/usr/bin/python3
"""Record actual X11 button events delivered to a disposable target window."""
import pathlib
import sys
import tkinter as tk

count_path = pathlib.Path(sys.argv[1])
root = tk.Tk()
root.title('Auto Clicker isolated test target')
root.geometry('200x200+1050+800')
count = 0
count_path.write_text('0')

def clicked(_event):
    global count
    count += 1
    count_path.write_text(str(count))

root.bind('<ButtonPress-1>', clicked)
root.mainloop()
