# Writes the iPhone and iPad app's icons: Lucide's outlines (ISC, version 0.469.0, the desktop's), as template vector
# image sets in StudyStash/Resources/Icons.xcassets, drawn the desktop's way (a 1.5 stroke, round caps and joins, in a
# 24-unit box). One name table: the desktop's own (NAMES and SOLID in engine/tools/icons/lucide.py, read here and never
# changed from the phone side) plus PHONE_NAMES below for the few the phone needs that the desktop doesn't have.
#
#   mkdir <empty folder> && cd <it> && npm pack lucide-static@0.469.0 && tar -xzf lucide-static-0.469.0.tgz
#   python3 -I ios/tools/icons.py <that folder>/package/icons
#
# Each name becomes an image set of that name ("home", "event_upcoming"); a solid one (SOLID) gets "<name>-filled" too.
# The path data is made exactly as the desktop's IconPaths.cs is (a rect, circle or line becomes the same path), and
# checked against it, so the two apps draw the same icon. Image sets for names no longer in the table are removed.
import ast, json, os, re, shutil, sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.dirname(HERE)
REPO = os.path.dirname(IOS)
DESKTOP_TABLE = os.path.join(REPO, "engine/tools/icons/lucide.py")
DESKTOP_PATHS = os.path.join(REPO, "engine/src/StudyStash.App/IconPaths.cs")
CATALOG = os.path.join(IOS, "StudyStash/Resources/Icons.xcassets")
NAMES_SWIFT = os.path.join(IOS, "StudyStash/Design/IconNames.swift")

# The phone's own names -> Lucide's: only what the desktop's NAMES lacks. Material-style names, as the desktop's are.
PHONE_NAMES = {
    "mic_off": "mic-off",                     # can't record
    "document_scanner": "scan-text",          # scan pages
    "qr_code_scanner": "scan-qr-code",        # pairing: scan the QR code
    "cancel": "circle-x",                     # a wrong answer
    "undo": "undo-2",                         # flashcards: again
    "page_add": "file-plus",                  # a notebook: add a page
    "page_remove": "file-minus",              # a notebook: delete this page
    "cloud_upload": "cloud-upload",           # a notebook: save to the library
    "flashcards": "gallery-vertical-end",     # study: flashcards and a quiz
    "work": "briefcase",                      # what it's for: work
    "science": "flask-conical",               # what it's for: research
    "person": "user",                         # what it's for: personal
    "redo": "redo-2",                         # a notebook: redo
    "grid_view": "layout-grid",               # a notebook: its pages
    "pan_tool": "hand",                       # a notebook: draw with a finger
    "arrow_downward": "arrow-down",           # a notebook: move a page later
    "history": "history",                     # Ask: the chats before
    "edit_square": "square-pen",              # Ask: a new chat
    "photo_camera": "camera",                 # Whiteboard photos: the camera
}


def desktop_table():
    """NAMES and SOLID from the desktop's generator, read as data (the file is never run or changed)."""
    tree = ast.parse(open(DESKTOP_TABLE).read())
    found = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id in ("NAMES", "SOLID"):
                found[node.targets[0].id] = ast.literal_eval(node.value)
    return found["NAMES"], found["SOLID"]


# --- the desktop's conversion (engine/tools/icons/lucide.py), so the path data is the same ---

def num(v):
    s = f"{float(v):.3f}".rstrip("0").rstrip(".")
    return s if s else "0"

NUMBER = r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?"

def absolute_start(d):
    if not d.startswith("m"):
        return d
    m = re.match(rf"m\s*({NUMBER})[\s,]*({NUMBER})[\s,]*", d)
    rest = d[m.end():]
    return f"M{m.group(1)} {m.group(2)}" + (("l" + rest) if rest and (rest[0].isdigit() or rest[0] in "-+.") else rest)

def shape(el):
    tag = el.tag.split("}")[-1]
    a = el.attrib
    if tag == "path":
        return absolute_start(re.sub(r"\s+", " ", a["d"].strip()))
    if tag == "line":
        return f"M{num(a['x1'])} {num(a['y1'])}L{num(a['x2'])} {num(a['y2'])}"
    if tag in ("polyline", "polygon"):
        pts = re.split(r"[\s,]+", a["points"].strip())
        pairs = [f"{num(pts[i])} {num(pts[i + 1])}" for i in range(0, len(pts), 2)]
        return "M" + "L".join(pairs) + ("Z" if tag == "polygon" else "")
    if tag in ("circle", "ellipse"):
        cx, cy = float(a.get("cx", 0)), float(a.get("cy", 0))
        rx = float(a.get("r", a.get("rx", 0))); ry = float(a.get("r", a.get("ry", rx)))
        return f"M{num(cx - rx)} {num(cy)}A{num(rx)} {num(ry)} 0 1 0 {num(cx + rx)} {num(cy)}A{num(rx)} {num(ry)} 0 1 0 {num(cx - rx)} {num(cy)}Z"
    if tag == "rect":
        x, y, w, h = float(a.get("x", 0)), float(a.get("y", 0)), float(a["width"]), float(a["height"])
        rx = float(a.get("rx", a.get("ry", 0))); ry = float(a.get("ry", rx))
        rx, ry = min(rx, w / 2), min(ry, h / 2)
        if rx == 0 and ry == 0:
            return f"M{num(x)} {num(y)}H{num(x + w)}V{num(y + h)}H{num(x)}Z"
        return (f"M{num(x + rx)} {num(y)}H{num(x + w - rx)}A{num(rx)} {num(ry)} 0 0 1 {num(x + w)} {num(y + ry)}V{num(y + h - ry)}"
                f"A{num(rx)} {num(ry)} 0 0 1 {num(x + w - rx)} {num(y + h)}H{num(x + rx)}A{num(rx)} {num(ry)} 0 0 1 {num(x)} {num(y + h - ry)}"
                f"V{num(y + ry)}A{num(rx)} {num(ry)} 0 0 1 {num(x + rx)} {num(y)}Z")
    raise ValueError(f"unknown element {tag}")


def svg(d, filled):
    # Black on clear: the catalog marks it a template, so it's drawn in the text's colour.
    fill = "#000000" if filled else "none"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
            f'<path d="{d}" fill="{fill}" stroke="#000000" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'
            f'</svg>\n')


def write_set(name, d, filled):
    folder = os.path.join(CATALOG, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    open(os.path.join(folder, f"{name}.svg"), "w").write(svg(d, filled))
    contents = {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }
    open(os.path.join(folder, "Contents.json"), "w").write(json.dumps(contents, indent=2) + "\n")


def main():
    icons_dir = sys.argv[1]
    names, solid = desktop_table()
    clash = sorted(set(PHONE_NAMES) & set(names))
    if clash:
        sys.exit(f"the desktop has these names already; drop them from PHONE_NAMES: {clash}")
    table = {**names, **PHONE_NAMES}
    desktop_paths = dict(re.findall(r'\["([a-z_0-9]+)"\] = "([^"]*)"', open(DESKTOP_PATHS).read()))

    os.makedirs(CATALOG, exist_ok=True)
    open(os.path.join(CATALOG, "Contents.json"), "w").write(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    made, missing, differ = set(), [], []
    for name in sorted(table):
        try:
            root = ET.parse(os.path.join(icons_dir, f"{table[name]}.svg")).getroot()
        except FileNotFoundError:
            missing.append((name, table[name]))
            continue
        d = " ".join(shape(el) for el in root)
        if name in desktop_paths and desktop_paths[name] != d:
            differ.append(name)
        write_set(name, d, filled=False)
        made.add(f"{name}.imageset")
        if name in solid:
            write_set(f"{name}-filled", d, filled=True)
            made.add(f"{name}-filled.imageset")
    if missing:
        sys.exit(f"not in Lucide: {missing}")
    if differ:
        sys.exit(f"not the desktop's drawing (another Lucide version?): {differ}")
    for entry in os.listdir(CATALOG):
        if entry.endswith(".imageset") and entry not in made:
            shutil.rmtree(os.path.join(CATALOG, entry))
    listed = ",\n".join(f'        "{n}"' for n in sorted(table))
    solid_listed = ", ".join(f'"{n}"' for n in sorted(solid))
    open(NAMES_SWIFT, "w").write(f'''// Made by ios/tools/icons.py: don't edit.

/// Every icon the app has (Resources/Icons.xcassets), by the desktop's names, and those with a solid one too
/// (`Image(icon: name, filled: true)`).
enum IconNames {{
    static let all: [String] = [
{listed},
    ]
    static let solid: Set<String> = [{solid_listed}]
}}
''')
    print(f"{len(table)} icons ({len(names)} the desktop's, {len(PHONE_NAMES)} the phone's own), {len(made)} image sets")


main()
