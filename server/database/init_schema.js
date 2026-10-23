// ==============================================================================
// Anyplace Database Schema Initialization Script
// Domain: E-JUST Anyplace System
// Idempotent: safe to run on every deploy (createIndex is a no-op when present).
// ==============================================================================

// Respect the database selected on the mongosh command line.
db = db.getSiblingDB(db.getName());

const collections = [
  'users',
  'spaces',
  'campuses',
  'floorplans',
  'pois',
  'edges',
  'fingerprintsWifi',
  'accessPointsWifi',
  'cFingerprintTime',
  'heatmapWifi1',
  'heatmapWifi2',
  'heatmapWifi3',
  'heatmapWifiTimestamp1',
  'heatmapWifiTimestamp2',
  'heatmapWifiTimestamp3'
];

collections.forEach(col => {
  if (!db.getCollectionNames().includes(col)) {
    db.createCollection(col);
    print('Created collection: ' + col);
  }
});

// Indexes for Users
db.users.createIndex({ "username": 1 }, { unique: true, sparse: true });
db.users.createIndex({ "email": 1 }, { unique: true, sparse: true });
db.users.createIndex({ "owner_id": 1 }, { unique: true, sparse: true });
db.users.createIndex({ "user_id": 1 });
// Per-request auth lookup: without this every authenticated call scans users.
db.users.createIndex({ "access_token": 1 }, { unique: true, sparse: true });
// Single-admin invariant: partial unique index prevents concurrent first registrations minting two admins.
db.users.createIndex({ "type": 1 }, {
  unique: true,
  partialFilterExpression: { type: "admin" }
});

// Indexes for Spaces (Buildings / Vessels)
db.spaces.createIndex({ "buid": 1 }, { unique: true, sparse: true });
db.spaces.createIndex({ "owner_id": 1 });
db.spaces.createIndex({ "co_owners": 1 });
db.spaces.createIndex({ "is_published": 1 });
// Spatial lookups use the geometry field (see Space/Poi models), not location.
db.spaces.createIndex({ "geometry": "2dsphere" });

// Indexes for Campuses
db.campuses.createIndex({ "cuid": 1 }, { unique: true, sparse: true });
db.campuses.createIndex({ "owner_id": 1 });
db.campuses.createIndex({ "buids": 1 });

// Indexes for Floorplans
db.floorplans.createIndex({ "fuid": 1 }, { unique: true, sparse: true });
db.floorplans.createIndex({ "buid": 1, "floor_number": 1 });

// Indexes for POIs
db.pois.createIndex({ "puid": 1 }, { unique: true, sparse: true });
db.pois.createIndex({ "buid": 1, "floor_number": 1 });
db.pois.createIndex({ "buid": 1, "pois_type": 1 });
db.pois.createIndex({ "geometry": "2dsphere" });

// Indexes for Edges / Connections
db.edges.createIndex({ "buid": 1, "floor_a": 1 });
db.edges.createIndex({ "buid": 1, "is_published": 1 });
db.edges.createIndex({ "pois_a": 1, "pois_b": 1 });
// Campus routing: outdoor/stair/elevator edges by buid_a/buid_b.
db.edges.createIndex({ "edge_type": 1, "buid_a": 1, "buid_b": 1 });
db.edges.createIndex({ "cuid": 1 }, { unique: true, sparse: true });

// Indexes for Fingerprints
db.fingerprintsWifi.createIndex({ "buid": 1, "floor": 1 });
db.fingerprintsWifi.createIndex({ "MAC": 1, "rss": 1 });
db.fingerprintsWifi.createIndex({ "geometry": "2dsphere" });

print('Anyplace schema baseline initialized successfully.');
