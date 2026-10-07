"use strict";

const WALK_SPEED_M_PER_S = 1.3;
const MARGIN_DEG = 0.002; // how far outside the graph's area a point may be
const ALGOS = [
  { key: "dijkstra", color: getVar("--dijkstra") },
  { key: "astar", color: getVar("--astar") },
];

const statusEl = document.getElementById("status");
const playBtn = document.getElementById("play");
let bounds = null; // [[south, west], [north, east]]
let start = null; // [lat, lon]
let startIsGps = false;
let gpsAccuracy = null; // meters
let end = null;
let result = null; // last route response: dijkstra, astar and, for a class, room
let syncing = true; // off until both maps have their first view
let animation = 0;

function getVar(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

function setStatus(text, isError = false) {
  statusEl.textContent = text;
  statusEl.classList.toggle("error", isError);
}

/* ---- maps ------------------------------------------------------------ */

for (const a of ALGOS) {
  a.map = L.map(`map-${a.key}`, { preferCanvas: true });
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: "&copy; OpenStreetMap contributors",
  }).addTo(a.map);
  a.explored = L.layerGroup().addTo(a.map);
  a.route = L.layerGroup().addTo(a.map);
  a.markers = L.layerGroup().addTo(a.map);
  a.map.on("click", (e) => onMapClick(e.latlng));
}

// Leaflet caches the container size; re-measure whenever the layout changes
// (otherwise a map that was 0 px wide at load fits routes at a silly zoom).
let needsFit = false; // set if the maps had no size (page loaded hidden) when they first tried to fit
const resizer = new ResizeObserver(() => {
  ALGOS.forEach((a) => a.map.invalidateSize({ animate: false }));
  if (needsFit && bounds && ALGOS[0].map.getSize().x > 0) {
    needsFit = false;
    ALGOS.forEach((a) => a.map.fitBounds(bounds, { animate: false }));
  }
});
for (const a of ALGOS) resizer.observe(document.getElementById(`map-${a.key}`));

// Keep the two maps panned and zoomed together so the searches line up.
for (const a of ALGOS) {
  a.map.on("move", () => {
    if (syncing) return;
    syncing = true;
    for (const b of ALGOS) {
      if (b !== a) b.map.setView(a.map.getCenter(), a.map.getZoom(), { animate: false });
    }
    syncing = false;
  });
}

async function init() {
  try {
    const meta = await (await fetch("/api/meta")).json();
    const [west, south, east, north] = meta.bbox;
    bounds = [[south, west], [north, east]];
    ALGOS.forEach((a) => {
      a.map.invalidateSize({ animate: false });
      a.map.fitBounds(bounds, { animate: false });
    });
    syncing = false;
    needsFit = ALGOS[0].map.getSize().x === 0;
    setStatus(`Graph: ${meta.nodes} nodes, ${meta.edges} edges. Enter your class (leave From blank to start from where you are), or click the map to set a start point.`);
  } catch (err) {
    setStatus("Could not reach the server. Is server/server.py running?", true);
  }
}

function onCampus([lat, lon]) {
  const [[south, west], [north, east]] = bounds;
  return lat >= south - MARGIN_DEG && lat <= north + MARGIN_DEG &&
         lon >= west - MARGIN_DEG && lon <= east + MARGIN_DEG;
}

/* ---- picking points -------------------------------------------------- */

function onMapClick(latlng) {
  if (start && end) clearAll();
  const point = [latlng.lat, latlng.lng];
  if (!start) {
    start = point;
    startIsGps = false;
    drawMarkers();
    setStatus("Now click the end point.");
  } else {
    end = point;
    drawMarkers();
    loadRoute("route", { start: start.join(","), end: end.join(",") });
  }
}

function drawMarkers() {
  for (const a of ALGOS) {
    a.markers.clearLayers();
    if (start && startIsGps) {
      if (gpsAccuracy) {
        L.circle(start, { radius: gpsAccuracy, stroke: false, fillColor: "#1f6feb", fillOpacity: 0.12 }).addTo(a.markers);
      }
      L.circleMarker(start, { radius: 8, color: "#fff", weight: 3, fillColor: "#1f6feb", fillOpacity: 1 }).addTo(a.markers);
    } else if (start) {
      L.circleMarker(start, { radius: 8, color: "#fff", weight: 2, fillColor: "#2da44e", fillOpacity: 1 }).addTo(a.markers);
    }
    if (end) {
      L.circleMarker(end, { radius: 8, color: "#fff", weight: 2, fillColor: "#d1453b", fillOpacity: 1 }).addTo(a.markers);
    }
  }
}

function clearAll() {
  cancelAnimationFrame(animation);
  start = end = result = null;
  startIsGps = false;
  gpsAccuracy = null;
  playBtn.disabled = true;
  for (const a of ALGOS) {
    a.explored.clearLayers();
    a.route.clearLayers();
    a.markers.clearLayers();
    document.getElementById(`stats-${a.key}`).replaceChildren();
  }
  setStatus("Click the map to set a start point.");
}

/* ---- my location ----------------------------------------------------- */

function getMyLocation() {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error("This browser can't share your location. Type a starting room, or click the map."));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({ point: [pos.coords.latitude, pos.coords.longitude], accuracy: pos.coords.accuracy }),
      (err) => reject(new Error(
        err.code === err.PERMISSION_DENIED
          ? "Location is blocked for this page. Allow it in the browser, type a starting room, or click the map."
          : "Couldn't get your location. Type a starting room, or click the map.")),
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 15000 }
    );
  });
}

/* ---- routing --------------------------------------------------------- */

// "that class is online" -> "That class is online."
function sentence(text) {
  return text.charAt(0).toUpperCase() + text.slice(1).replace(/[.?!]?$/, ".");
}

function didYouMean(body) {
  const names = body.candidate_names || body.candidates || [];
  return names.length ? ` Did you mean: ${names.join(", ")}?` : "";
}

async function api(path, params) {
  const res = await fetch(`/api/${path}?${new URLSearchParams(params)}`);
  const body = await res.json();
  if (!res.ok) throw new Error(sentence(body.error || res.statusText) + didYouMean(body));
  return body;
}

function minutes(meters) {
  return Math.max(1, Math.round(meters / WALK_SPEED_M_PER_S / 60));
}

// Fetch a route (point to point, or point to class) and show it on both maps.
async function loadRoute(path, params) {
  setStatus("Routing…");
  try {
    result = await api(path, params);
  } catch (err) {
    clearAll();
    setStatus(err.message, true);
    return;
  }
  if (result.room) end = [result.room.entrance.lat, result.room.entrance.lon];
  drawMarkers();
  showResult(false);
  fitToRoute();
  playBtn.disabled = false;
  describe();
}

// Zoom both maps (they are linked) so the whole route is in view.
function fitToRoute() {
  const path = result.astar.path;
  ALGOS.forEach((a) => a.map.invalidateSize({ animate: false }));
  if (path && path.length > 1) ALGOS[0].map.fitBounds(path, { padding: [40, 40], animate: false });
}

function describe() {
  const d = result.dijkstra, s = result.astar;
  if (!d.found) return setStatus("No walking route between those points.", true);
  const saved = Math.round(100 * (1 - s.nodes_explored / d.nodes_explored));
  const search = `A* searched ${saved}% fewer nodes than Dijkstra.`;
  if (!result.room) {
    return setStatus(`${Math.round(d.distance_m)} m, about ${minutes(d.distance_m)} min on foot. ${search} Click again to start over.`);
  }
  const r = result.room;
  const level = r.floor ? `, level ${r.floor}` : "";
  const inside = r.indoor_m >= 10 ? ` plus about ${Math.round(r.indoor_m)} m inside` : "";
  const from = startIsGps ? "from your location" : "from the start point";
  setStatus(`${r.raw} (${r.building_name}${level}): ${Math.round(d.distance_m)} m ${from} to the best door, about ${minutes(d.distance_m + r.indoor_m)} min${inside}. ${search}`);
}

function dot(a, latlng) {
  L.circleMarker(latlng, { radius: 2.5, stroke: false, fillColor: a.color, fillOpacity: 0.55 }).addTo(a.explored);
}

function drawRoute(a, data) {
  a.route.clearLayers();
  if (data.found) L.polyline(data.path, { color: "#1c2430", weight: 5, opacity: 0.9 }).addTo(a.route);
}

function showResult(animate) {
  cancelAnimationFrame(animation);
  for (const a of ALGOS) {
    a.explored.clearLayers();
    a.route.clearLayers();
    renderStats(a, result[a.key]);
  }
  if (!animate) {
    for (const a of ALGOS) {
      result[a.key].explored.forEach((p) => dot(a, p));
      drawRoute(a, result[a.key]);
    }
    return;
  }
  // Replay both searches in lockstep, a few hundred frames long at most.
  const longest = Math.max(...ALGOS.map((a) => result[a.key].explored.length));
  const perFrame = Math.max(1, Math.ceil(longest / 240));
  let i = 0;
  const step = () => {
    for (const a of ALGOS) {
      const pts = result[a.key].explored;
      for (let j = i; j < Math.min(i + perFrame, pts.length); j++) dot(a, pts[j]);
      if (i < pts.length && i + perFrame >= pts.length) drawRoute(a, result[a.key]);
    }
    i += perFrame;
    if (i < longest) animation = requestAnimationFrame(step);
  };
  animation = requestAnimationFrame(step);
}

function renderStats(a, data) {
  const dl = document.getElementById(`stats-${a.key}`);
  const items = data.found
    ? [
        ["Distance", `${Math.round(data.distance_m)} m`],
        ["Walk", `${minutes(data.distance_m)} min`],
        ["Nodes explored", data.nodes_explored.toLocaleString()],
        ["Engine time", `${data.time_us} µs`],
      ]
    : [["Result", "no path"]];
  dl.replaceChildren(
    ...items.map(([label, value]) => {
      const div = document.createElement("div");
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = label;
      dd.textContent = value;
      div.append(dt, dd);
      return div;
    })
  );
}

/* ---- route to a class ------------------------------------------------ */

// A starting room becomes the building's main door, as a plain point.
async function roomToPoint(text) {
  const r = await api("resolve", { q: text });
  if (r.kind !== "building" || !r.entrances.length) {
    throw new Error(`Couldn't place "${text}" (${r.kind}).${didYouMean(r)}`);
  }
  const door = r.entrances.find((e) => e.kind === "main") || r.entrances[0];
  return [door.lat, door.lon];
}

document.getElementById("lookup").addEventListener("submit", async (e) => {
  e.preventDefault();
  const from = document.getElementById("from-room").value.trim();
  const to = document.getElementById("to-room").value.trim();
  if (!to) return setStatus("Enter your class location, for example Kresge Acad 3201.", true);
  clearAll();
  try {
    if (from) {
      start = await roomToPoint(from);
      startIsGps = false;
    } else {
      setStatus("Getting your location…");
      const here = await getMyLocation();
      if (!onCampus(here.point)) {
        throw new Error("You appear to be off campus, outside the mapped area. Type a starting room, or click the map.");
      }
      start = here.point;
      startIsGps = true;
      gpsAccuracy = here.accuracy;
    }
  } catch (err) {
    clearAll();
    return setStatus(err.message, true);
  }
  drawMarkers();
  loadRoute("route_to_room", { start: start.join(","), room: to });
});

playBtn.addEventListener("click", () => result && showResult(true));
document.getElementById("reset").addEventListener("click", clearAll);

init();
