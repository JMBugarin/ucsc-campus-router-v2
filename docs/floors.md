# Classroom floors

A room shows a floor only when someone walked it (`floor` in `data/rooms.json`) or a published UCSC source puts it there (`data/floors.json`, with the source). Nothing is filled in from the room number or the campus map level. Both were tried and both were wrong:

- The campus map's classroom layer gives McHenry 1340 and 1350 level `L3`, and their numbers start `13`. The library's own floor plan has both on the **1st floor**, one floor below the main entrance (the 2nd floor, with the service desk and café).
- Merrill numbers its ground-level classrooms 2 and 3, and puts 102, 130 and 132 on the **2nd floor**, so "the first digit is the floor" fails there too.

## Sources (read 2026-11-19)

| Source | What it shows | Rooms |
|---|---|---|
| [UCSC Library: McHenry floor plans](https://guides.library.ucsc.edu/mchenry-library/floor-plans) and [McHenry classrooms](https://guides.library.ucsc.edu/mchenry-library/classrooms) | 1st-floor plan with 1340 and 1350; directions from the library elevator | McHenry 1340, 1350 (floor 1, below the entrance) |
| [Cowell College map](https://maps.ucsc.edu/printable-maps/cowell_9-17.pdf) | "Classrooms 216, 222, 223 … on 2nd floor"; 113, 131, 134 on the plan | Cowell 113, 131, 134 (1); 216, 222, 223 (2) |
| [Crown College map](https://maps.ucsc.edu/printable-maps/Crown_College.pdf) | "Classrooms 201, 202, 203, and 208 upstairs" | Crown 104, 105 (1); 201, 202, 203, 208 (2) |
| [Merrill College map](https://maps.ucsc.edu/printable-maps/Merrill_College010215.pdf) | Classroom 2 and 3 on the plan, "Classroom 102 on 2nd floor", 130 and 132 "on 2nd floor" | Merrill 002, 003 (1); 102, 130, 132 (2) |
| [Oakes College map](https://maps.ucsc.edu/printable-maps/Oakes_College.pdf) | 101–106 on the plan, "222 upstairs" | Oakes 101, 102, 103, 105, 106 (1); 222 (2) |
| [Porter College map](https://maps.ucsc.edu/printable-maps/Porter_College_2015.pdf) | 144 and 148 on the plan, "Classrooms 241-250 (upstairs)" | Porter 144, 148 (1); 241, 246, 249, 250 (2) |
| [Rachel Carson College map](https://maps.ucsc.edu/printable-maps/rachel_carson_college_3-18.pdf) | 240, 242, 250–256 at the north end, level with the north parking, stairs and elevator down to the plaza | Rachel Carson 240, 242, 250, 252 (2, entrance level from the north) |
| [Stevenson College map](https://maps.ucsc.edu/printable-maps/stevenson_9-17.pdf) | 150, 151, 152 and 175 on the plan | Stevenson 150, 151, 152, 175 (1) |
| [Science & Engineering Library map](https://maps.ucsc.edu/printable-maps/Science_And_Engineering_Library.pdf) | "The Science & Engineering library is on the second floor level." | S&E Library 206 (2) |
| [UCSC News, Engineering 2 dedication](https://news.ucsc.edu/2004/10/media-advisory-media-tours-and-interviews-available-prior-to-dedication-ceremonies-for-engineering-2-building/) | "Simularium Hall, Engineering 2 (first floor, enter from the courtyard)", which is E2 180 | Engineering 2 192, 194 (1) |

## Not confirmed yet (45 rooms, no floor shown)

No public plan or map found for these. The Baskin Engineering floor plans are behind a UCSC login, and the PPDO seismic reports that name each building's floors are no longer online. Record the floor as signed when you walk them (see [room guides](room-guides.md)).

- Classroom Unit 001, 002
- Earth & Marine Sciences B206, B210, B214
- Humanities Lecture Hall 206; Humanities and Social Sciences 250, 350
- Jack Baskin Auditorium 101; Jack Baskin Engineering 152, 156, 165, 169, 372
- Kresge College Academic Building 3101, 3105, 3201, 3301
- Media Theater M110
- Natural Sciences 2 Annex 101, 102, 103
- Physical Sciences Building 110, 114, 130, 136, 140
- Social Sciences 1 110, 145, 149, 153, 161; Social Sciences 2 071, 075, 137, 141, 159, 165, 167, 171, 179, 363
- Thimann Labs 101; Thimann Lecture Hall 001, 003

## Adding one

Add the room to `rooms` in `data/floors.json` with the floor as signed (`"1"`, `"2"`, `"G"`), `where` if the source says (`entrance`, `upstairs`, or `below` the main entrance) and a key into `sources` (name, https URL, date read). `npm run data` in `web/` rejects unknown rooms, missing sources and anything that is not a signed floor; then run `scripts/sync_app_data.sh` for the phone app.
