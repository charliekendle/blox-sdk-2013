#!/usr/bin/env python3
"""
Builds Build/BloxSDK2013.rbxm (binary) and Build/BloxSDK2013.rbxmx (XML) from the repo.

    python3 Tools/build_rbxm.py

Layout -> instances
    ReplicatedStorage/...                  -> BloxSDK2013/ReplicatedStorage/...
    ServerScriptService/...                -> BloxSDK2013/ServerScriptService/...
    StarterPlayer/StarterPlayerScripts/... -> BloxSDK2013/StarterPlayerScripts/...
    folders -> Folder, *.server.luau -> Script, *.client.luau -> LocalScript, *.luau -> ModuleScript

No dependencies. The binary writer emits uncompressed chunks (allowed by the format).
"""
from __future__ import annotations

import os
import struct
import sys
from dataclasses import dataclass, field
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Build")
MODEL_NAME = "BloxSDK2013"

SOURCES = [
    ("ReplicatedStorage", "ReplicatedStorage"),
    ("ServerScriptService", "ServerScriptService"),
    (os.path.join("StarterPlayer", "StarterPlayerScripts"), "StarterPlayerScripts"),
]

INSTALL_NOTE = """--[[
	BloxSDK 2013 - install

	Move each folder's contents into the matching service:
	  BloxSDK2013.ReplicatedStorage.BloxSDK                -> ReplicatedStorage
	  BloxSDK2013.ServerScriptService.BloxSDKServer        -> ServerScriptService
	  BloxSDK2013.StarterPlayerScripts.BloxSDKClient       -> StarterPlayer.StarterPlayerScripts

	Or paste this in the command bar with the model selected in Workspace:

	local m = workspace.BloxSDK2013
	m.ReplicatedStorage.BloxSDK.Parent = game.ReplicatedStorage
	m.ServerScriptService.BloxSDKServer.Parent = game.ServerScriptService
	m.StarterPlayerScripts.BloxSDKClient.Parent = game.StarterPlayer.StarterPlayerScripts
	m:Destroy()
]]
return nil
"""


@dataclass
class Inst:
    class_name: str
    name: str
    source: str | None = None
    children: list["Inst"] = field(default_factory=list)
    referent: int = -1


def build_tree() -> Inst:
    root = Inst("Folder", MODEL_NAME)
    root.children.append(Inst("ModuleScript", "README_INSTALL", INSTALL_NOTE))
    for rel, name in SOURCES:
        path = os.path.join(ROOT, rel)
        if not os.path.isdir(path):
            continue
        folder = Inst("Folder", name)
        add_dir(folder, path)
        root.children.append(folder)
    return root


def add_dir(parent: Inst, path: str) -> None:
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if entry.startswith("."):
            continue
        if os.path.isdir(full):
            folder = Inst("Folder", entry)
            add_dir(folder, full)
            parent.children.append(folder)
        elif entry.endswith(".luau") or entry.endswith(".lua"):
            base = entry.rsplit(".", 1)[0]
            if base.endswith(".server"):
                cls, name = "Script", base[: -len(".server")]
            elif base.endswith(".client"):
                cls, name = "LocalScript", base[: -len(".client")]
            else:
                cls, name = "ModuleScript", base
            with open(full, encoding="utf-8") as fh:
                source = fh.read()
            parent.children.append(Inst(cls, name, source))


def flatten(root: Inst) -> list[Inst]:
    out: list[Inst] = []

    def walk(i: Inst) -> None:
        i.referent = len(out)
        out.append(i)
        for c in i.children:
            walk(c)

    walk(root)
    return out


# ---------------------------------------------------------------------------
# XML (.rbxmx)
# ---------------------------------------------------------------------------

def cdata(text: str) -> str:
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def write_xml(root: Inst, path: str) -> None:
    lines = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
             'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
             'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
             "\t<External>null</External>",
             "\t<External>nil</External>"]

    def emit(i: Inst, depth: int) -> None:
        pad = "\t" * depth
        lines.append(f'{pad}<Item class="{i.class_name}" referent="RBX{i.referent:08X}">')
        lines.append(f"{pad}\t<Properties>")
        lines.append(f'{pad}\t\t<string name="Name">{escape(i.name)}</string>')
        if i.source is not None:
            lines.append(f'{pad}\t\t<ProtectedString name="Source">{cdata(i.source)}</ProtectedString>')
        lines.append(f"{pad}\t</Properties>")
        for c in i.children:
            emit(c, depth + 1)
        lines.append(f"{pad}</Item>")

    emit(root, 1)
    lines.append("</roblox>")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# Binary (.rbxm)
# ---------------------------------------------------------------------------

def rbx_string(s: str | bytes) -> bytes:
    b = s.encode("utf-8") if isinstance(s, str) else s
    return struct.pack("<I", len(b)) + b


def zigzag32(x: int) -> int:
    return ((x << 1) ^ (x >> 31)) & 0xFFFFFFFF


def interleave_i32(values: list[int]) -> bytes:
    raw = [struct.pack(">I", zigzag32(v)) for v in values]
    return bytes(raw[j][i] for i in range(4) for j in range(len(raw)))


def referents(values: list[int]) -> bytes:
    deltas, last = [], 0
    for v in values:
        deltas.append(v - last)
        last = v
    return interleave_i32(deltas)


def chunk(name: bytes, data: bytes) -> bytes:
    assert len(name) == 4
    # compressed length 0 = stored uncompressed
    return name + struct.pack("<III", 0, len(data), 0) + data


def write_binary(root: Inst, path: str) -> None:
    insts = flatten(root)
    class_names = sorted({i.class_name for i in insts})
    class_ids = {c: n for n, c in enumerate(class_names)}
    by_class: dict[str, list[Inst]] = {c: [] for c in class_names}
    for i in insts:
        by_class[i.class_name].append(i)

    out = bytearray()
    out += b"<roblox!" + b"\x89\xff\x0d\x0a\x1a\x0a"
    out += struct.pack("<H", 0)                       # version
    out += struct.pack("<i", len(class_names))        # class count
    out += struct.pack("<i", len(insts))              # instance count
    out += b"\x00" * 8                                # reserved

    for c in class_names:
        members = by_class[c]
        data = struct.pack("<I", class_ids[c]) + rbx_string(c) + b"\x00"
        data += struct.pack("<I", len(members)) + referents([m.referent for m in members])
        out += chunk(b"INST", data)

    STRING = 0x01
    for c in class_names:
        members = by_class[c]
        data = struct.pack("<I", class_ids[c]) + rbx_string("Name") + bytes([STRING])
        data += b"".join(rbx_string(m.name) for m in members)
        out += chunk(b"PROP", data)
        if c in ("Script", "LocalScript", "ModuleScript"):
            data = struct.pack("<I", class_ids[c]) + rbx_string("Source") + bytes([STRING])
            data += b"".join(rbx_string(m.source or "") for m in members)
            out += chunk(b"PROP", data)

    parents: dict[int, int] = {}
    for i in insts:
        for ch in i.children:
            parents[ch.referent] = i.referent
    kids = [i.referent for i in insts]
    pars = [parents.get(r, -1) for r in kids]
    data = b"\x00" + struct.pack("<I", len(kids)) + referents(kids) + referents(pars)
    out += chunk(b"PRNT", data)

    out += chunk(b"END\x00", b"</roblox>")

    with open(path, "wb") as fh:
        fh.write(out)


# ---------------------------------------------------------------------------
# Reader (self-check)
# ---------------------------------------------------------------------------

def read_binary(path: str) -> list[tuple[str, str, int, str | None]]:
    buf = open(path, "rb").read()
    assert buf[:14] == b"<roblox!\x89\xff\x0d\x0a\x1a\x0a", "bad magic"
    (n_classes, n_insts) = struct.unpack_from("<ii", buf, 16)
    pos = 32
    classes: dict[int, tuple[str, list[int]]] = {}
    props: dict[tuple[int, str], list[str]] = {}
    parents: dict[int, int] = {}

    def un_i32(data: bytes, count: int, at: int) -> tuple[list[int], int]:
        raw = data[at: at + 4 * count]
        vals = []
        for j in range(count):
            b = bytes(raw[i * count + j] for i in range(4))
            u = struct.unpack(">I", b)[0]
            vals.append((u >> 1) ^ -(u & 1))
        return vals, at + 4 * count

    def un_ref(data: bytes, count: int, at: int) -> tuple[list[int], int]:
        vals, at = un_i32(data, count, at)
        acc, out = 0, []
        for v in vals:
            acc += v
            out.append(acc)
        return out, at

    def rd_str(data: bytes, at: int) -> tuple[str, int]:
        (ln,) = struct.unpack_from("<I", data, at)
        return data[at + 4: at + 4 + ln].decode("utf-8"), at + 4 + ln

    while True:
        name = buf[pos: pos + 4]
        comp, uncomp, _ = struct.unpack_from("<III", buf, pos + 4)
        assert comp == 0
        data = buf[pos + 16: pos + 16 + uncomp]
        pos += 16 + uncomp
        if name == b"INST":
            cid = struct.unpack_from("<I", data, 0)[0]
            cname, at = rd_str(data, 4)
            at += 1
            (cnt,) = struct.unpack_from("<I", data, at)
            refs, _ = un_ref(data, cnt, at + 4)
            classes[cid] = (cname, refs)
        elif name == b"PROP":
            cid = struct.unpack_from("<I", data, 0)[0]
            pname, at = rd_str(data, 4)
            assert data[at] == 1
            at += 1
            vals = []
            for _ in classes[cid][1]:
                v, at = rd_str(data, at)
                vals.append(v)
            assert at == len(data), "PROP length mismatch"
            props[(cid, pname)] = vals
        elif name == b"PRNT":
            (cnt,) = struct.unpack_from("<I", data, 1)
            ch, at = un_ref(data, cnt, 5)
            pa, at = un_ref(data, cnt, at)
            assert at == len(data)
            parents = dict(zip(ch, pa))
        elif name == b"END\x00":
            assert data == b"</roblox>"
            break
        else:
            raise AssertionError(f"unexpected chunk {name!r}")

    assert len(classes) == n_classes
    rows = []
    for cid, (cname, refs) in classes.items():
        names = props[(cid, "Name")]
        sources = props.get((cid, "Source"))
        for k, r in enumerate(refs):
            rows.append((cname, names[k], parents[r], sources[k] if sources else None, r))
    assert len(rows) == n_insts
    rows.sort(key=lambda t: t[4])
    return [(c, n, p, s) for c, n, p, s, _ in rows]


def main() -> int:
    root = build_tree()
    os.makedirs(OUT_DIR, exist_ok=True)
    rbxm = os.path.join(OUT_DIR, MODEL_NAME + ".rbxm")
    rbxmx = os.path.join(OUT_DIR, MODEL_NAME + ".rbxmx")
    write_binary(root, rbxm)
    write_xml(root, rbxmx)

    # verify the binary round-trips
    insts = flatten(root)
    rows = read_binary(rbxm)
    parent_of = {ch.referent: i.referent for i in insts for ch in i.children}
    for inst, (cname, name, parent, source) in zip(insts, rows):
        assert inst.class_name == cname and inst.name == name, (inst.name, name)
        assert parent == parent_of.get(inst.referent, -1)
        assert (inst.source or None) == (source or None) or inst.source == source

    def show(i: Inst, depth: int = 0) -> None:
        print("  " * depth + f"{i.name} [{i.class_name}]")
        for c in i.children:
            show(c, depth + 1)

    show(root)
    print(f"\nwrote {rbxm} ({os.path.getsize(rbxm)} bytes)")
    print(f"wrote {rbxmx} ({os.path.getsize(rbxmx)} bytes)")
    print(f"{len(insts)} instances, binary round-trip OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
