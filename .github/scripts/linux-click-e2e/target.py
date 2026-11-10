#!/usr/bin/python3
"""Record actual X11 button events delivered to a disposable target window."""
import pathlib
import sys
import tkinter as tk

count_path = pathlib.Path(sys.argv[1])
events_path = pathlib.Path(sys.argv[2])
root = tk.Tk()
root.title('Auto Clicker isolated test target')
root.geometry('200x200+1050+800')
count = 0
count_path.write_text('0')

def clicked(event):
    global count
    count += 1
    count_path.write_text(str(count))
    with events_path.open('a') as events:
        events.write(f'{event.x_root},{event.y_root}\n')

root.bind('<ButtonPress-1>', clicked)
root.mainloop()
