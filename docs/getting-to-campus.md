# Getting to campus from off campus

Many students live off campus, and this app does not pretend to route buses. Instead it does two things.

**1. It tells you when to be on campus.** When the phone is off campus, Today shows "Be at *Rachel Carson College bus stop* by *3:34 PM*" for each class still to come: the class start, minus the walk on campus paths from that entry point to the room (climbs and stairs included, the same walk time Today uses elsewhere), minus 10 minutes to spare. Leave-now reminders for those classes use the same time: a heads-up 30 minutes before it and a reminder 10 minutes before it (the app can't know how long your trip takes, so these lead times are fixed guesses). On campus, nothing changes.

The entry points are 13 campus bus stops and 2 parking areas taken from OpenStreetMap ([`data/entry_points.json`](../data/README.md)), each checked to sit on the walking graph. The suggested one is the nearest to you among those within 10 minutes of the shortest walk to your room; **Change entry point** lists them all with their walk to the room, and your last pick is remembered on the phone.

**2. It hands the first leg to Transit.** **Get to campus with Transit** opens `transit://directions?to=<latitude>,<longitude>` for the entry point. That follows Transit's [developer page](https://www.transitapp.com/apis): `to` takes a latitude-longitude pair or a place, and leaving out a parameter uses the user's current location, so the app leaves `from` out and does not give Transit where you are. The page shows no example with coordinates, and the link has not been opened with Transit installed. If Transit isn't installed (the app checks, which is why `transit` is declared in `Info.plist`), the same trip opens in Apple Maps and a **Get Transit** button links to its App Store page. **Open in Apple Maps** also offers walking, biking, driving and public transit to the same point, using Apple's [unified Maps URLs](https://developer.apple.com/documentation/mapkit/unified-map-urls) (`/directions?destination=…&mode=…`, documented for iOS 18.4 and later; older iOS is untested). On Android the same buttons use Google Maps links.

**What the app contacts, and what it does not.** Your server, for walking times from entry points to your rooms; the map tile server; and Transit or Apple Maps only when you tap them. Where you are is never sent to the server when you are off campus: the phone decides it is off campus itself, and the server is only asked about a room, never a position. No bus or timetable data is bundled, and no transit API or key is used.

**Limits.**
- No live bus information: arrival times, delays and routes are Transit's. The times here are walking times from entry points, a 10-minute cushion and the reminder leads above.
- The walking graph covers the core campus only (roughly north of 36.986° N), so the Main Entrance and Lower Campus stops are not entry points. OpenStreetMap's gates and entrances are unnamed, so none are included.
- A dropped pin can't be planned from off campus (only rooms and buildings), and a server older than this feature answers `/api/entry_walks` with 404, which the app reports as "This server can't plan a trip to campus yet".
- Not tried on a physical device, with Transit installed, or on Android.
