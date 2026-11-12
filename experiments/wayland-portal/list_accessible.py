#!/usr/bin/python3
"""Read-only dump of isolated desktop accessibility names."""
import pyatspi

def walk(node, depth=0):
    if node is None or depth > 25:
        return
    try:
        name = node.name or ''
        role = node.getRoleName()
        if name:
            print('  ' * depth + role + ': ' + name, flush=True)
        for child in node:
            walk(child, depth + 1)
    except (AttributeError, LookupError, RuntimeError, NotImplementedError):
        pass

for app in pyatspi.Registry.getDesktop(0):
    walk(app)
