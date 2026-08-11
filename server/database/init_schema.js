// ==============================================================================
// Anyplace Database Schema Initialization Script
// Domain: E-JUST Anyplace System
// ==============================================================================

db = db.getSiblingDB('anyplace');

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
db.users.createIndex({ "owner_id": 1 });
db.users.createIndex({ "user_id": 1 });

// Indexes for Spaces (Buildings / Vessels)
db.spaces.createIndex({ "buid": 1 }, { unique: true, sparse: true });
db.spaces.createIndex({ "owner_id": 1 });
db.spaces.createIndex({ "is_published": 1 });
db.spaces.createIndex({ "location": "2dsphere" });

// Indexes for Campuses
db.campuses.createIndex({ "cuid": 1 }, { unique: true, sparse: true });
db.campuses.createIndex({ "owner_id": 1 });

// Indexes for Floorplans
db.floorplans.createIndex({ "fuid": 1 }, { unique: true, sparse: true });
db.floorplans.createIndex({ "buid": 1, "floor_number": 1 });

// Indexes for POIs
db.pois.createIndex({ "puid": 1 }, { unique: true, sparse: true });
db.pois.createIndex({ "buid": 1, "floor_number": 1 });
db.pois.createIndex({ "location": "2dsphere" });

// Indexes for Edges / Connections
db.edges.createIndex({ "buid": 1, "floor_a": 1 });
db.edges.createIndex({ "pois_a": 1, "pois_b": 1 });

// Indexes for Fingerprints
db.fingerprintsWifi.createIndex({ "buid": 1, "floor": 1 });
db.fingerprintsWifi.createIndex({ "location": "2dsphere" });

print('Anyplace schema baseline initialized successfully.');
