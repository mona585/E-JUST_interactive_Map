// E-JUST outdoor-pilot demo seed — EXECUTED 2026-10-09 against Mongo 6.0,
// verified end to end: campus/get, space/public, pois/space, navigation/route.
// Idempotent: wipes only the fixed demo ids, leaves everything else alone.
// NEVER run against production: fixed demo ids (buid_eng/buid_lib/...) would
// collide with real mapping. Staging/test databases only.
// Usage (staging, after init_database.sh):
//   mongosh "mongodb://127.0.0.1:27017/anyplace" server/database/seed_demo_campus.js
// Ownership: demo rows belong to owner_id "seed" (nonexistent user), so only
// admins pass the floorplan space-access gate on them. After seeding, assign
// the buildings to real staff via Architect (space co-owners) or:
//   db.spaces.updateMany({buid:{$in:["buid_eng","buid_lib"]}},{$set:{owner_id:"<staff_owner_id>"}})
// Then walk the acceptance test:
//   POST /api/mapping/campus/get {"cuid":"cuid_ejust_demo"} -> 2 spaces
//   POST /api/navigation/route {"pois_from":"puid_eng_entrance","pois_to":"puid_eng_lab"}
//     -> num_of_pois 2, "Plotted navigation."
//   POST /api/navigation/route/campus {"cuid":"cuid_ejust_demo",
//     "pois_from":"puid_eng_entrance","pois_to":"puid_lib_entrance"}
//     -> num_of_pois 2, "Plotted campus navigation."
// Product rule this seed documents: spaces need is_published:"true" to appear
// in space/public (getAllBuildings filters on it); campus/get does not.

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
    owner_id: "seed", is_published: "true"},
  {buid: "buid_lib", name: "Central Library", description: "demo",
    owner_id: "seed", is_published: "true"}
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
