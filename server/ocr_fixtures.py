"""Test helper: lay out a MyUCSC-style "Class Schedule" table as OCR word boxes.

The geometry (column positions, line spacing, two-line wrapped cells, a menu down the left, a
footer) was measured from a real screenshot, but the courses here are made up, so no one's
schedule is in the repository. Mistakes OCR really makes can be injected with `noise`.
"""

LINE = 14          # distance between the two lines of a wrapped cell
ROW_PITCH = 34     # distance between class rows
CHAR_W = 6
COL = {"nbr": 323, "section": 373, "component": 411, "days": 486, "room": 596,
       "instructor": 689, "dates": 796}


def word(text, x, y, h=9):
    return {"text": text, "x0": x, "y0": y, "x1": x + CHAR_W * len(text), "y1": y + h}


def row(nbr, section, component, days, t1, t2, room, instructor, d1="09/24/2026", d2="12/04/2026"):
    return dict(nbr=nbr, section=section, component=component, days=days, t1=t1, t2=t2, room=room,
                instructor=instructor, d1=d1, d2=d2)


def course(code, title, rows, status="Enrolled"):
    return dict(code=code, title=title, rows=rows, status=status)


SAMPLE = [
    course("XYZ 10", "Sample Calculus", [
        row("20001", "01A", "Discussion", "Mo", "8:00AM", "9:05AM", "Cowell Acad 113", "To be Announced"),
        row("20002", "01", "Lecture", "MoWeFr", "2:40PM", "3:45PM", "Kresge Acad 3201", "Alex Example"),
    ]),
    course("ABC 20", "Sample Systems", [
        row("20003", "01A", "Discussion", "Th", "8:30AM", "9:35AM", "J Baskin Engr 156", "To be Announced"),
        row("20004", "01", "Lecture", "TuTh", "9:50AM", "11:25AM", "Earth&Marine B206", "Pat Example"),
    ]),
]


def render(courses, noise=None, scale=1.0, top=441):
    """Word boxes for a page: menu on the left, one table per course, a footer. `noise` maps
    (field, row nbr) to replacement text, e.g. {("section", "20003"): "O01A"}."""
    noise = noise or {}
    words = []
    for i, label in enumerate(["Enrollment", "Class Search", "Enrollment: Add Classes", "Edit a Class"]):
        for j, part in enumerate(label.split()):  # the page's menu, with a word "Class" in it
            words.append(word(part, 35 + 45 * j, 260 + 50 * i))
    y = top
    for c in courses:
        for k, part in enumerate(f"{c['code']} {c['title']}".split()):
            words.append(word(part, 317 + 38 * k, y))
        for text, x in (("Status", 317), ("Units", 499), ("Grading", 530), ("Grade", 679), ("Deadlines", 774)):
            words.append(word(text, x, y + 29))
        words += [word(c["status"], 316, y + 50), word("5.00", 454, y + 50), word("Graded", 530, y + 50)]
        hy = y + 82
        words += [word("Class", 321, hy - 7), word("Nbr", 327, hy + 6), word("Section", 364, hy),
                  word("Component", 410, hy), word("Days", 485, hy), word("&", 514, hy), word("Times", 524, hy),
                  word("Room", 595, hy), word("Instructor", 688, hy), word("Start/End", 796, hy), word("Date", 846, hy)]
        for k, r in enumerate(c["rows"]):
            top_y = y + 107 + k * ROW_PITCH
            n = lambda field, text: noise.get((field, r["nbr"]), text)  # noqa: E731
            words.append(word(n("nbr", r["nbr"]), COL["nbr"], top_y + 7))
            words.append(word(n("section", r["section"]), COL["section"], top_y + 7))
            words.append(word(n("component", r["component"]), COL["component"], top_y + 7))
            words += [word(n("days", r["days"]), COL["days"], top_y), word(n("t1", r["t1"]), COL["days"] + 46, top_y),
                      word("-", COL["days"] + 100, top_y + 5, 2), word(n("t2", r["t2"]), COL["days"], top_y + LINE)]
            room_words = n("room", r["room"]).split()
            x = COL["room"]
            for part in room_words[:-1]:
                words.append(word(part, x, top_y))
                x += CHAR_W * len(part) + 4
            words.append(word(room_words[-1], COL["room"], top_y + LINE))  # the number wraps to line two
            inst = r["instructor"].split()
            words += [word(" ".join(inst[:-1]) or inst[0], COL["instructor"], top_y)]
            if len(inst) > 1:
                words.append(word(inst[-1], COL["instructor"], top_y + LINE))
            words += [word(n("d1", r["d1"]), COL["dates"] - 1, top_y), word("-", COL["dates"] + 62, top_y + 5, 2),
                      word(n("d2", r["d2"]), COL["dates"], top_y + LINE)]
        y += 107 + len(c["rows"]) * ROW_PITCH + 20
    for k, part in enumerate(["Printer", "Friendly", "Page"]):
        words.append(word(part, 810 + 45 * k, y + 20))
    if scale != 1.0:
        words = [{"text": w["text"], **{k: round(w[k] * scale) for k in ("x0", "y0", "x1", "y1")}} for w in words]
    return words
