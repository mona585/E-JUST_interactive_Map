// Demo seed (staging/test only): idempotent, wipes only fixed demo ids; never run in production.
// Usage: mongosh "mongodb://127.0.0.1:27017/anyplace" server/database/seed_demo_campus.js
// Demo rows use owner_id "seed"; reassign buid_eng/buid_lib to staff owner_id after seeding.
// Acceptance: campus/get cuid_ejust_demo -> 2 spaces; route puid_eng_entrance->puid_eng_lab -> 2 pois.
// Acceptance: route/campus cuid_ejust_demo puid_eng_entrance->puid_lib_entrance -> 2 pois.
// Product rule: spaces need is_published:"true" for space/public; campus/get does not.

db = db.getSiblingDB('anyplace');

db.campuses.deleteMany({cuid: "cuid_ejust_demo"});
db.spaces.deleteMany({buid: {$in: ["buid_eng", "buid_lib"]}});
db.pois.deleteMany({puid: {$in: ["puid_eng_entrance", "puid_eng_lab", "puid_lib_entrance"]}});
db.edges.deleteMany({cuid: {$in: ["conn_puid_eng_entrance_puid_eng_lab",
  "conn_puid_eng_entrance_puid_lib_entrance"]}});

db.campuses.insertOne({cuid: "cuid_ejust_demo", name: "E-JUST Demo Campus",
  description: "outdoor pilot", greeklish: "false",
  buids: ["buid_eng", "buid_lib"], owner_id: "seed"});

db.spaces.insertMany([
  {buid: "buid_eng", name: "Engineering Building", description: "demo",
    owner_id: "seed", is_published: "true",
    coordinates_lat: "30.9501", coordinates_lon: "29.7501"},
  {buid: "buid_lib", name: "Central Library", description: "demo",
    owner_id: "seed", is_published: "true",
    coordinates_lat: "30.9510", coordinates_lon: "29.7510"}
]);

db.pois.insertMany([
  {puid: "puid_eng_entrance", buid: "buid_eng", floor_number: "0",
    name: "Main Entrance", coordinates_lat: "30.9501",
    coordinates_lon: "29.7501", pois_type: "Entrance",
    is_building_entrance: "true"},
  {puid: "puid_eng_lab", buid: "buid_eng", floor_number: "0",
    name: "Lab 101", coordinates_lat: "30.9502", coordinates_lon: "29.7502",
    pois_type: "Room", is_building_entrance: "false"},
  {puid: "puid_lib_entrance", buid: "buid_lib", floor_number: "0",
    name: "Library Entrance", coordinates_lat: "30.9510",
    coordinates_lon: "29.7510", pois_type: "Entrance",
    is_building_entrance: "true"}
]);

db.edges.insertMany([
  {cuid: "conn_puid_eng_entrance_puid_eng_lab",
    pois_a: "puid_eng_entrance", pois_b: "puid_eng_lab",
    buid_a: "buid_eng", buid_b: "buid_eng", floor_a: "0", floor_b: "0",
    buid: "buid_eng", edge_type: "hallway", weight: "12.5",
    is_published: "true"},
  {cuid: "conn_puid_eng_entrance_puid_lib_entrance",
    pois_a: "puid_eng_entrance", pois_b: "puid_lib_entrance",
    buid_a: "buid_eng", buid_b: "buid_lib", floor_a: "0", floor_b: "0",
    buid: "buid_eng", edge_type: "outdoor", weight: "180.0",
    is_published: "true"}
]);

print("demo seed done: campuses=" + db.campuses.countDocuments({cuid: "cuid_ejust_demo"})
  + " spaces=" + db.spaces.countDocuments({buid: {$in: ["buid_eng", "buid_lib"]}})
  + " pois=" + db.pois.countDocuments({buid: {$in: ["buid_eng", "buid_lib"]}})
  + " edges=" + db.edges.countDocuments({buid: "buid_eng"}));
