# Room audit

The 20 classrooms most likely to send someone to the wrong side, floor or door, ranked by `web/scripts/room-audit.mjs` (regenerate with `npm run rooms:audit` in `web/`; checked rooms drop off the list).

Walk each one from the outside, the way a student would arrive. Open the room on your phone with the link, add `?audit` to fill in the guide on the spot, then paste the copied JSON into `data/rooms.json` and run `npm run data`. Write only what you saw; leave a field out rather than guess. See [room guides](room-guides.md) for what each field means.

| # | Room | Why it is on the list |
|---|---|---|
| 1 | [Jack Baskin Engineering 152](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-152?audit) | mixed-use building; nearest mapped door 29 m away; floor not confirmed by any published source |
| 2 | [Earth & Marine Sciences B206](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/earth-marine-sciences-b206?audit) | mixed-use building; floor not confirmed by any published source; main entrance 45 m farther than the nearest door |
| 3 | [Earth & Marine Sciences B210](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/earth-marine-sciences-b210?audit) | mixed-use building; floor not confirmed by any published source; main entrance 44 m farther than the nearest door |
| 4 | [Earth & Marine Sciences B214](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/earth-marine-sciences-b214?audit) | mixed-use building; floor not confirmed by any published source; main entrance 41 m farther than the nearest door |
| 5 | [Jack Baskin Engineering 165](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-165?audit) | mixed-use building; floor not confirmed by any published source; main entrance 28 m farther than the nearest door |
| 6 | [Jack Baskin Engineering 169](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-169?audit) | mixed-use building; floor not confirmed by any published source; main entrance 32 m farther than the nearest door |
| 7 | [Jack Baskin Engineering 372](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-372?audit) | mixed-use building; floor not confirmed by any published source; main entrance 30 m farther than the nearest door |
| 8 | [McHenry Library 1340](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/mchenry-library-1340?audit) | mixed-use building; nearest mapped door 41 m away; not on the entrance level |
| 9 | [McHenry Library 1350](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/mchenry-library-1350?audit) | mixed-use building; nearest mapped door 53 m away; not on the entrance level |
| 10 | [Physical Sciences Building 140](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/physical-sciences-140?audit) | mixed-use building; floor not confirmed by any published source; main entrance 26 m farther than the nearest door |
| 11 | [Thimann Labs 101](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/thimann-labs-101?audit) | mixed-use building; floor not confirmed by any published source; main entrance 67 m farther than the nearest door |
| 12 | [Engineering 2 194](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/engineering-2-194?audit) | mixed-use building; nearest mapped door 33 m away |
| 13 | [Jack Baskin Auditorium 101](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-auditorium-101?audit) | mixed-use building; floor not confirmed by any published source |
| 14 | [Jack Baskin Engineering 156](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/baskin-engineering-156?audit) | mixed-use building; floor not confirmed by any published source |
| 15 | [Kresge College Academic Building 3101](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/kresge-academic-3101?audit) | nearest mapped door 46 m away; floor not confirmed by any published source; only one mapped door |
| 16 | [Kresge College Academic Building 3201](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/kresge-academic-3201?audit) | nearest mapped door 34 m away; floor not confirmed by any published source; only one mapped door |
| 17 | [Physical Sciences Building 110](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/physical-sciences-110?audit) | mixed-use building; floor not confirmed by any published source |
| 18 | [Physical Sciences Building 114](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/physical-sciences-114?audit) | mixed-use building; floor not confirmed by any published source |
| 19 | [Physical Sciences Building 130](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/physical-sciences-130?audit) | mixed-use building; floor not confirmed by any published source |
| 20 | [Physical Sciences Building 136](https://jmbugarin.github.io/ucsc-campus-router-v2/#/p/physical-sciences-136?audit) | mixed-use building; floor not confirmed by any published source |

## 1. Jack Baskin Engineering 152

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 29 m, room is south-west of it; 34 m, room is north-west of it (OSM main entrance); 54 m, room is west of it; 56 m, room is west of it (OSM main entrance).
- Other rooms here: 156, 165, 169, 372.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 2. Earth & Marine Sciences B206

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 9 m, room is north-west of it; 14 m, room is north-west of it; 30 m, room is north-west of it; 36 m, room is north-west of it; 47 m, room is south-west of it; 54 m, room is north of it; 55 m, room is south-west of it; 56 m, room is north-west of it; 62 m, room is north-west of it; 68 m, room is north-west of it.
- Other rooms here: B210, B214.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 3. Earth & Marine Sciences B210

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 8 m, room is north-east of it; 13 m, room is north-east of it; 18 m, room is north-west of it; 24 m, room is north-west of it; 37 m, room is south-west of it; 43 m, room is south-west of it; 48 m, room is north-west of it; 52 m, room is north of it; 54 m, room is north-west of it; 59 m, room is north-west of it.
- Other rooms here: B206, B214.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 4. Earth & Marine Sciences B214

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 14 m, room is north of it; 17 m, room is north of it; 21 m, room is east of it; 23 m, room is north-east of it; 30 m, room is south of it; 34 m, room is south-west of it; 43 m, room is north of it; 49 m, room is north of it; 52 m, room is north-west of it; 55 m, room is north of it.
- Other rooms here: B206, B210.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 5. Jack Baskin Engineering 165

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 13 m, room is east of it; 19 m, room is west of it; 33 m, room is north-west of it (OSM main entrance); 41 m, room is north of it (OSM main entrance).
- Other rooms here: 152, 156, 169, 372.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 6. Jack Baskin Engineering 169

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 12 m, room is west of it; 19 m, room is east of it; 30 m, room is north-west of it (OSM main entrance); 44 m, room is north of it (OSM main entrance).
- Other rooms here: 152, 156, 165, 372.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 7. Jack Baskin Engineering 372

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 9 m, room is west of it; 22 m, room is north-west of it (OSM main entrance); 24 m, room is east of it; 39 m, room is north-east of it (OSM main entrance).
- Other rooms here: 152, 156, 165, 169.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 8. McHenry Library 1340

- Floor: 1 (below), from UCSC Library: McHenry floor plans and classroom directions.
- Mapped doors, nearest first: 41 m, room is south-east of it; 50 m, room is south of it (OSM main entrance); 60 m, room is south-west of it; 73 m, room is south of it (OSM main entrance).
- Other rooms here: 1350.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 9. McHenry Library 1350

- Floor: 1 (below), from UCSC Library: McHenry floor plans and classroom directions.
- Mapped doors, nearest first: 53 m, room is south-east of it; 58 m, room is south-east of it (OSM main entrance); 59 m, room is south of it; 80 m, room is south-east of it (OSM main entrance).
- Other rooms here: 1340.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 10. Physical Sciences Building 140

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 7 m, room is north-east of it; 9 m, room is north of it; 11 m, room is north-east of it; 20 m, room is north-west of it; 27 m, room is north-west of it; 33 m, room is west of it (OSM main entrance); 34 m, room is north-west of it; 39 m, room is east of it.
- Other rooms here: 110, 114, 130, 136.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 11. Thimann Labs 101

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 5 m, room is south of it; 32 m, room is south-east of it; 72 m, room is east of it.
- Other rooms here: none.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 12. Engineering 2 194

- Floor: 1, from UCSC News: Engineering 2 dedication advisory.
- Mapped doors, nearest first: 33 m, room is east of it; 35 m, room is west of it; 38 m, room is south-east of it; 80 m, room is east of it.
- Other rooms here: 192.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 13. Jack Baskin Auditorium 101

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 13 m, room is north-east of it; 17 m, room is south-east of it.
- Other rooms here: none.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 14. Jack Baskin Engineering 156

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 23 m, room is south-west of it; 29 m, room is north-west of it (OSM main entrance); 46 m, room is west of it; 48 m, room is west of it (OSM main entrance).
- Other rooms here: 152, 165, 169, 372.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 15. Kresge College Academic Building 3101

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 46 m, room is south of it.
- Other rooms here: 3105, 3201, 3301.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 16. Kresge College Academic Building 3201

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 34 m, room is south-east of it.
- Other rooms here: 3101, 3105, 3301.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 17. Physical Sciences Building 110

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 11 m, room is east of it; 14 m, room is south-east of it; 21 m, room is south-east of it; 26 m, room is south of it (OSM main entrance); 40 m, room is east of it; 41 m, room is east of it; 46 m, room is east of it; 79 m, room is south-east of it.
- Other rooms here: 114, 130, 136, 140.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 18. Physical Sciences Building 114

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 12 m, room is east of it; 13 m, room is south of it (OSM main entrance); 18 m, room is east of it; 19 m, room is north-east of it; 39 m, room is east of it; 39 m, room is east of it; 44 m, room is east of it; 75 m, room is east of it.
- Other rooms here: 110, 130, 136, 140.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 19. Physical Sciences Building 130

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 9 m, room is north of it; 16 m, room is north-west of it; 18 m, room is west of it (OSM main entrance); 19 m, room is east of it; 20 m, room is north-east of it; 24 m, room is east of it; 26 m, room is north-west of it; 53 m, room is east of it.
- Other rooms here: 110, 114, 136, 140.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.

## 20. Physical Sciences Building 136

- Floor: not confirmed; record the floor as signed.
- Mapped doors, nearest first: 12 m, room is north-east of it; 13 m, room is north-east of it; 14 m, room is north-west of it; 17 m, room is north-east of it; 21 m, room is north-west of it; 26 m, room is west of it (OSM main entrance); 30 m, room is north-west of it; 45 m, room is east of it.
- Other rooms here: 110, 114, 130, 140.
- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.
