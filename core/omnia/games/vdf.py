"""Lector mínimo del formato VDF/ACF de Valve (texto con comillas y llaves)."""
import re

_TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])')


def parse_vdf(text: str) -> dict:
    stack = [{}]
    pending = None
    for m in _TOKEN.finditer(text):
        s, brace = m.group(1), m.group(2)
        if s is not None:
            s = s.replace('\\"', '"').replace("\\\\", "\\")
            if pending is None:
                pending = s
            else:
                stack[-1][pending] = s
                pending = None
        elif brace == "{":
            child = {}
            if pending is not None:
                stack[-1][pending] = child
            stack.append(child)
            pending = None
        elif brace == "}" and len(stack) > 1:
            stack.pop()
    return stack[0]
