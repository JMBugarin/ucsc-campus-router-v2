# Room audit

The 20 classrooms most likely to send someone to the wrong side, floor or door, ranked by `web/scripts/room-audit.mjs` (regenerate with `npm run rooms:audit` in `web/`; checked rooms drop off the list).

Walk each one from the outside, the way a student would arrive. Open the room on your phone with the link, add `?audit` to fill in the guide on the spot, then paste the copied JSON into `data/rooms.json` and run `npm run data`. Write only what you saw; leave a field out rather than guess. See [room guides](room-guides.md) for what each field means.

| # | Room | Why it is on the list |
|---|---|---|
| 1 | [McHenry Library 1340](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/mchenry-library-1340?audit) | mixed-use building; nearest mapped door 41 m away; not on floor 1 |
| 2 | [McHenry Library 1350](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/mchenry-library-1350?audit) | mixed-use building; nearest mapped door 53 m away; not on floor 1 |
| 3 | [Science & Engineering Library 206](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/science-engineering-library-206?audit) | mixed-use building; nearest mapped door 27 m away; not on floor 1 |
| 4 | [Earth & Marine Sciences B206](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/earth-marine-sciences-b206?audit) | mixed-use building; not on floor 1; main entrance 45 m farther than the nearest door |
| 5 | [Earth & Marine Sciences B210](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/earth-marine-sciences-b210?audit) | mixed-use building; not on floor 1; main entrance 44 m farther than the nearest door |
| 6 | [Earth & Marine Sciences B214](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/earth-marine-sciences-b214?audit) | mixed-use building; not on floor 1; main entrance 41 m farther than the nearest door |
| 7 | [Engineering 2 194](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/engineering-2-194?audit) | mixed-use building; nearest mapped door 33 m away |
| 8 | [Jack Baskin Engineering 152](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-152?audit) | mixed-use building; nearest mapped door 29 m away |
| 9 | [Jack Baskin Engineering 372](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-372?audit) | mixed-use building; not on floor 1; main entrance 30 m farther than the nearest door |
| 10 | [Jack Baskin Engineering 165](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-165?audit) | mixed-use building; main entrance 28 m farther than the nearest door |
| 11 | [Jack Baskin Engineering 169](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-169?audit) | mixed-use building; main entrance 32 m farther than the nearest door |
| 12 | [Kresge College Academic Building 3201](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/kresge-academic-3201?audit) | nearest mapped door 34 m away; not on floor 1; only one mapped door |
| 13 | [Physical Sciences Building 140](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/physical-sciences-140?audit) | mixed-use building; main entrance 26 m farther than the nearest door |
| 14 | [Social Sciences 2 075](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/social-sciences-2-075?audit) | nearest mapped door 31 m away; not on floor 1; only one mapped door |
| 15 | [Thimann Labs 101](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/thimann-labs-101?audit) | mixed-use building; main entrance 67 m farther than the nearest door |
| 16 | [Classroom Unit 002](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/classroom-unit-002?audit) | floor not confirmed by the room number; not on floor 1 |
| 17 | [Engineering 2 192](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/engineering-2-192?audit) | mixed-use building |
| 18 | [Jack Baskin Auditorium 101](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-auditorium-101?audit) | mixed-use building |
| 19 | [Jack Baskin Engineering 156](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-156?audit) | mixed-use building |
| 20 | [Kresge College Academic Building 3101](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/kresge-academic-3101?audit) | nearest mapped door 46 m away; only one mapped door |

## 1. McHenry Library 1340

- Campus map: floor 3 (matches the room number).
- Mapped doors, nearest first: 41 m, room is south-east of it; 50 m, room is south of it (OSM main entrance); 60 m, room is south-west of it; 73 m, room is south of it (OSM main entrance).
- Other rooms here: 1350.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 2. McHenry Library 1350

- Campus map: floor 3 (matches the room number).
- Mapped doors, nearest first: 53 m, room is south-east of it; 58 m, room is south-east of it (OSM main entrance); 59 m, room is south of it; 80 m, room is south-east of it (OSM main entrance).
- Other rooms here: 1340.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 3. Science & Engineering Library 206

- Campus map: floor 2 (matches the room number).
- Mapped doors, nearest first: 27 m, room is north of it (OSM main entrance); 34 m, room is north of it.
- Other rooms here: none.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 4. Earth & Marine Sciences B206

- Campus map: floor 2 (matches the room number).
- Mapped doors, nearest first: 9 m, room is north-west of it; 14 m, room is north-west of it; 30 m, room is north-west of it; 36 m, room is north-west of it; 47 m, room is south-west of it; 54 m, room is north of it; 55 m, room is south-west of it; 56 m, room is north-west of it; 62 m, room is north-west of it; 68 m, room is north-west of it.
- Other rooms here: B210, B214.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 5. Earth & Marine Sciences B210

- Campus map: floor 2 (matches the room number).
- Mapped doors, nearest first: 8 m, room is north-east of it; 13 m, room is north-east of it; 18 m, room is north-west of it; 24 m, room is north-west of it; 37 m, room is south-west of it; 43 m, room is south-west of it; 48 m, room is north-west of it; 52 m, room is north of it; 54 m, room is north-west of it; 59 m, room is north-west of it.
- Other rooms here: B206, B214.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 6. Earth & Marine Sciences B214

- Campus map: floor 2 (matches the room number).
- Mapped doors, nearest first: 14 m, room is north of it; 17 m, room is north of it; 21 m, room is east of it; 23 m, room is north-east of it; 30 m, room is south of it; 34 m, room is south-west of it; 43 m, room is north of it; 49 m, room is north of it; 52 m, room is north-west of it; 55 m, room is north of it.
- Other rooms here: B206, B210.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 7. Engineering 2 194

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 33 m, room is east of it; 35 m, room is west of it; 38 m, room is south-east of it; 80 m, room is east of it.
- Other rooms here: 192.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 8. Jack Baskin Engineering 152

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 29 m, room is south-west of it; 34 m, room is north-west of it (OSM main entrance); 54 m, room is west of it; 56 m, room is west of it (OSM main entrance).
- Other rooms here: 156, 165, 169, 372.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 9. Jack Baskin Engineering 372

- Campus map: floor 3 (matches the room number).
- Mapped doors, nearest first: 9 m, room is west of it; 22 m, room is north-west of it (OSM main entrance); 24 m, room is east of it; 39 m, room is north-east of it (OSM main entrance).
- Other rooms here: 152, 156, 165, 169.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 10. Jack Baskin Engineering 165

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 13 m, room is east of it; 19 m, room is west of it; 33 m, room is north-west of it (OSM main entrance); 41 m, room is north of it (OSM main entrance).
- Other rooms here: 152, 156, 169, 372.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 11. Jack Baskin Engineering 169

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 12 m, room is west of it; 19 m, room is east of it; 30 m, room is north-west of it (OSM main entrance); 44 m, room is north of it (OSM main entrance).
- Other rooms here: 152, 156, 165, 372.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 12. Kresge College Academic Building 3201

- Campus map: floor 2 (matches the room number).
- Mapped doors, nearest first: 34 m, room is south-east of it.
- Other rooms here: 3101, 3105, 3301.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 13. Physical Sciences Building 140

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 7 m, room is north-east of it; 9 m, room is north of it; 11 m, room is north-east of it; 20 m, room is north-west of it; 27 m, room is north-west of it; 33 m, room is west of it (OSM main entrance); 34 m, room is north-west of it; 39 m, room is east of it.
- Other rooms here: 110, 114, 130, 136.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 14. Social Sciences 2 075

- Campus map: floor 0 (matches the room number).
- Mapped doors, nearest first: 31 m, room is north-west of it (OSM main entrance).
- Other rooms here: 071, 137, 141, 159, 165, 167, 171, 179, 363.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 15. Thimann Labs 101

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 5 m, room is south of it; 32 m, room is south-east of it; 72 m, room is east of it.
- Other rooms here: none.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 16. Classroom Unit 002

- Campus map: floor 2 (does not match the room number).
- Mapped doors, nearest first: 11 m, room is north-east of it (OSM main entrance); 14 m, room is north-west of it (OSM main entrance); 17 m, room is south-west of it.
- Other rooms here: 001.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 17. Engineering 2 192

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 23 m, room is east of it; 30 m, room is south-east of it; 45 m, room is west of it; 70 m, room is east of it.
- Other rooms here: 194.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 18. Jack Baskin Auditorium 101

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 13 m, room is north-east of it; 17 m, room is south-east of it.
- Other rooms here: none.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 19. Jack Baskin Engineering 156

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 23 m, room is south-west of it; 29 m, room is north-west of it (OSM main entrance); 46 m, room is west of it; 48 m, room is west of it (OSM main entrance).
- Other rooms here: 152, 165, 169, 372.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 20. Kresge College Academic Building 3101

- Campus map: floor 1 (matches the room number).
- Mapped doors, nearest first: 46 m, room is south of it.
- Other rooms here: 3105, 3201, 3301.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.
