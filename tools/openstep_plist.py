#!/usr/bin/env python3
"""
A parser for the OpenStep property-list dialect used by Xcode's `project.pbxproj`.

Xcode refuses to open a project whose .pbxproj does not parse, so being able to parse it
here is the strongest check available without Xcode itself. It implements the real grammar:

    value   := dict | array | quoted-string | unquoted-string
    dict    := '{' ( key '=' value ';' )* '}'
    array   := '(' ( value (',' value)* ','? ) ')'
    quoted  := '"' ( char | escape )* '"'
    unquoted:= [A-Za-z0-9_$/:.-]+

Whitespace and /* comments */ are skipped. Comments are only recognised outside strings.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

PUNCT = set("{}()=;,")
# Xcode's OpenStep unquoted string charset. Note that '<' and '>' are NOT permitted,
# which is why `sourceTree = "<group>";` must be quoted.
BARE = re.compile(r"[A-Za-z0-9_$./-]+")


class ParseError(Exception):
    pass


def tokenize(text: str):
    i, n = 0, len(text)
    while i < n:
        char = text[i]

        if char in " \t\r\n":
            i += 1
            continue

        if char == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            if end == -1:
                raise ParseError(f"unterminated block comment at offset {i}")
            i = end + 2
            continue

        if char == "/" and i + 1 < n and text[i + 1] == "/":
            end = text.find("\n", i)
            i = n if end == -1 else end + 1
            continue

        if char == '"':
            j = i + 1
            buffer = []
            while j < n:
                if text[j] == "\\":
                    if j + 1 >= n:
                        raise ParseError("dangling escape in string")
                    buffer.append(text[j : j + 2])
                    j += 2
                    continue
                if text[j] == '"':
                    break
                buffer.append(text[j])
                j += 1
            if j >= n:
                raise ParseError("unterminated quoted string")
            yield ("str", "".join(buffer))
            i = j + 1
            continue

        if char in PUNCT:
            yield ("punct", char)
            i += 1
            continue

        match = BARE.match(text, i)
        if not match:
            snippet = text[i : i + 40].splitlines()[0]
            raise ParseError(f"unexpected character {char!r} near: {snippet!r}")
        yield ("bare", match.group(0))
        i = match.end()


class Parser:
    def __init__(self, tokens):
        self.tokens = list(tokens)
        self.position = 0

    def peek(self):
        return self.tokens[self.position] if self.position < len(self.tokens) else (None, None)

    def next(self):
        kind, value = self.peek()
        self.position += 1
        return kind, value

    def expect(self, expected):
        kind, value = self.next()
        if kind != "punct" or value != expected:
            raise ParseError(f"expected {expected!r}, found {value!r}")
        return value

    def parse_value(self):
        kind, value = self.next()
        if kind == "punct" and value == "{":
            return self.parse_dict()
        if kind == "punct" and value == "(":
            return self.parse_array()
        if kind in ("str", "bare"):
            return value
        raise ParseError(f"unexpected token {value!r}")

    def parse_key(self):
        kind, value = self.next()
        if kind in ("str", "bare"):
            return value
        raise ParseError(f"expected a key, found {value!r}")

    def parse_dict(self):
        result = {}
        while True:
            kind, value = self.peek()
            if kind == "punct" and value == "}":
                self.next()
                return result
            if kind is None:
                raise ParseError("unterminated dictionary")
            key = self.parse_key()
            self.expect("=")
            result[key] = self.parse_value()
            kind, value = self.peek()
            if kind == "punct" and value == ";":
                self.next()
                continue
            kind, value = self.peek()
            if kind == "punct" and value == "}":
                continue
            raise ParseError(f"expected ';' after key {key!r}, found {value!r}")

    def parse_array(self):
        result = []
        while True:
            kind, value = self.peek()
            if kind == "punct" and value == ")":
                self.next()
                return result
            if kind is None:
                raise ParseError("unterminated array")
            result.append(self.parse_value())
            kind, value = self.peek()
            if kind == "punct" and value == ",":
                self.next()
                continue
            kind, value = self.peek()
            if kind == "punct" and value == ")":
                continue
            raise ParseError(f"expected ',' in array, found {value!r}")


def parse(text: str):
    parser = Parser(tokenize(text))
    return parser.parse_value()


def parse_file(path: Path):
    return parse(path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("OPFCaptureBuilder.xcodeproj/project.pbxproj")
    try:
        document = parse_file(target)
    except ParseError as error:
        print(f"PARSE ERROR in {target}: {error}")
        raise SystemExit(1)
    print(f"OK: parsed {target} — {len(document)} top-level keys")
