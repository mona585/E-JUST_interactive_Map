# Anyplace API
**Version:** 4.3.1

### A free and open Indoor Navigation Service with superb accuracy!

#### Authentication:
For `/api/auth` endpoints, the `access_token` must be put in the request headers.
In swagger you can use `Authenticate`.

Google sign in is supported. Anyplace specific key is provided for those cases as well.

##### API KEY (access_token):
Find your key from [/architect](../architect/#tab-user)

## Overview

- **Contact:** anyplace@cs.ucy.ac.cy
- **License:** [MIT License](https://opensource.org/licenses/MIT)

- **Schemes:** https, http
- **Base URL:** `https://api.anyplace.cs.ucy.ac.cy` *(assumed)*
- **Content-Type:** `application/json`

## Authentication

### api_key
- **Type:** apiKey
- **In:** header
- **Name:** `access_token`
- **Description:** Obtain the API key from [/architect](/architect/#tab-user).
A valid key ends with `ap`.


## Tags

- **User** — Anyplace account: local or a Google account.
- **User:Admin** — Priviledged tasks for `admin` or `moderators`
- **Space** — An indoor space: a `building` or a `vessel`.
- **Space:Floor** — A `floor` within a space.
- **Space:Floorplan** — Floorplan images and floor tiles
- **Space:POI** — A Point of Interest (POI) in a floor.
The POI type might be:
        - from a predefined list (e.g., elevator, stair, entrance)
        - any other custom type (from a string)
        - or the special `connector` type.

**Special POI `connector` type:**
A **connector** is essentially an edge on the **navigation map**.
A **navigation map** contains edges (either connectors or regular POIs), and vertices ([Space:Connection](#/Space%3AConnection)).

The non-connector POIs **must be leafs**. In simpler words, a non-connector POI can be either the beginning,
or the end of a **route**, but never in between. This was a design decision.

To create a **connector**, one must drag [this](/architect/build/images/edge-connector.png) icon from the architect.
- **Space:Connection** — Allows navigation between POIs.
That is the vertice between edges (POIs).
It does not contain a location, but instead the two POIs it links.
The POIs can be either a `connector` POI or a non-connector POI (regular POI).
Regular POIs are always at the beginning or at the end of a calculated route (see [Space:POI](#/Space%3APOI)).
- **Space:Campus** — A collection of spaces.
- **Radiomap** — Maps constructed from WiFi fingerprints.
- **AccessPoint** — Data related to access points, i.e., Wi-Fi routers.
- **Navigation** — Indoor navigation endpoints.
- **Position** — Acquiring a user's position.
- **Heatmap** — Heatmap visualization endpoints. These are cached in MongoDB, created on first request.
- **Misc** — Miscellaneous functionalities.

---

## AccessPoint

Data related to access points, i.e., Wi-Fi routers.

### Get access points location

```
POST /api/wifi/access_points/floor
```

**Operation ID:** `getAPs`

These are cached into the collection `accessPointsWifi`.
This endpoint is buggy. It fails to identify access points location.

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

**Body Schema:** `APs`

#### Responses

- **200** — Successful operation


### Get access point's manufacturer

```
POST /api/wifi/access_points/ids
```

**Operation ID:** `APsId`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

**Body Schema:** `APsId`

#### Responses

- **200** — Successful operation


---

## Heatmap

Heatmap visualization endpoints. These are cached in MongoDB, created on first request.

### Get heatmaps zoom 1

```
POST /api/heatmap/floor/average/1
```

**Operation ID:** `heatmapAvg1`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `Heatmap`

#### Responses

- **200** — Successful operation


### Get heatmaps zoom 2

```
POST /api/heatmap/floor/average/2
```

**Operation ID:** `heatmapAvg2`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `Heatmap`

#### Responses

- **200** — Successful operation


### Get heatmaps zoom 3

```
POST /api/heatmap/floor/average/3
```

**Operation ID:** `heatmapAvg3`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `Heatmap`

#### Responses

- **200** — Successful operation


### Get heatmaps tiles

```
POST /api/heatmap/floor/average/3/tiles
```

**Operation ID:** `heatmapAvgTiles`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `HeatmapTiles`

#### Responses

- **200** — Successful operation


### Get heatmaps with time zoom 1

```
POST /api/heatmap/floor/average/timestamp/1
```

**Operation ID:** `heatmapAvgTime1`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `HeatmapTime`

#### Responses

- **200** — Successful operation


### Get heatmaps with time zoom 2

```
POST /api/heatmap/floor/average/timestamp/2
```

**Operation ID:** `heatmapAvgTime2`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `HeatmapTime`

#### Responses

- **200** — Successful operation


### Get heatmaps with time zoom 3

```
POST /api/heatmap/floor/average/timestamp/3
```

**Operation ID:** `heatmapAvgTime3`

It is shown at WiFi Coverage at the highest zoom level, and a few levels before

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `HeatmapTime`

#### Responses

- **200** — Successful operation


### Get heatmaps tiles with time

```
POST /api/heatmap/floor/average/timestamp/tiles
```

**Operation ID:** `heatmapAvgTimeTiles`

Used by Fingerptints, at the highest zoom level

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `HeatmapTimeTiles`

#### Responses

- **200** — Successful operation


---

## Misc

Miscellaneous functionalities.

### Returns Anyplace Version

```
GET /api/version
```

**Operation ID:** `getVersion`

#### Responses

- **200** — success


---

## Navigation

Indoor navigation endpoints.

### Find fastest route

```
POST /api/navigation/route/coordinates
```

**Operation ID:** `routeXY`

Based on your current location, find the shortest route to a POI.

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `RouteXY`

#### Responses

- **200** — Successful operation


### Find fastest route

```
POST /api/navigation/route
```

**Operation ID:** `route`

Find the shortest route between two POIs.

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `Route`

#### Responses

- **200** — Successful operation


### Get detailed space

```
POST /api/navigation/space/id
```

**Operation ID:** `navSpaceId`

Based on buid get a space with full description (floors, POIs).

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `SpaceId`

#### Responses

- **200** — Successful operation


### Get POI

```
POST /api/navigation/pois/id
```

**Operation ID:** `navPOIsId`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `SpacePOI`

#### Responses

- **200** — Successful operation


---

## Position

Acquiring a user's position.

### Predict floor

```
POST /api/position/predictFloorAlgo1
```

**Operation ID:** `predictFloor`

According near-by Wi-Fi measurements tries to predict the floor

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Location description |

**Body Schema:** `PredictFloor`

#### Responses

- **200** — Successful operation


### Estimate position.

```
POST /api/position/estimate
```

**Operation ID:** `estimatePosition`

Not sure if this is properly implemented

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | TODO |

#### Responses

- **200** — Successful operation


---

## Radiomap

Maps constructed from WiFi fingerprints.

### Gets a frozen radiomap

```
POST /api/radiomaps_frozen/{space}/{floor}/{filename}
```

**Operation ID:** `radiomapFrozenBuidFlrnumName`

Used by Web apps
How about Android though?

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `space` | path | string | ✅ Yes |  |
| `floor` | path | string | ✅ Yes |  |
| `filename` | path | string | ✅ Yes |  |
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation


### Gets a particular radiomap.

```
POST /api/radiomaps/{radio_folder}/{filename}
```

**Operation ID:** `radiomapFolderFilename`

Probably used in a conjuction with another endpoint?
 to know how to build those URLs

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `radio_folder` | path | string | ✅ Yes |  |
| `filename` | path | string | ✅ Yes |  |
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation


### Upload a radiomap

```
POST /api/radiomap/upload
```

**Operation ID:** `radiomapUpload`

TODO docs. Also make specific for radiomap type (CV, WiFi, BLE?)
TODO require authentication? And test on mobile..

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation


### Get radiomaps of floor

```
POST /api/radiomap/floor
```

**Operation ID:** `radiomapFloor`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

**Body Schema:** `RadiomapFloor`

#### Responses

- **200** — Successful operation


### Get Wi-Fi radiomaps for the given floors

```
POST /api/radiomap/floors
```

**Operation ID:** `radiomapFloors`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

**Body Schema:** `RadiomapFloors`

#### Responses

- **200** — Successful operation


### Get radiomaps in a bounding box

```
POST /api/radiomap/floor/bbox
```

**Operation ID:** `radiomapFloorBbox`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

**Body Schema:** `RadiomapBbox`

#### Responses

- **200** — Successful operation


### Get radiomaps of a space

```
POST /api/radiomap/space
```

**Operation ID:** `radiomapSpace`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

**Body Schema:** `RadiomapSpace`

#### Responses

- **200** — Successful operation


### Generate time-based heatmaps for all zoom levels

```
POST /api/radiomap/time
```

**Operation ID:** `radiomapTime`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

**Body Schema:** `RadiomapSpace`

#### Responses

- **200** — Successful operation


### Delete radiomaps in a bounding box in a time-span

```
POST /api/auth/radiomap/delete/time
```

**Operation ID:** `radiomapDeleteTime`

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

**Body Schema:** `RadiomapDeleteTime`

#### Responses

- **200** — Successful operation


### Delete radiomaps in a bounding box

```
POST /api/auth/radiomap/delete
```

**Operation ID:** `radiomapDelete`

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

**Body Schema:** `RadiomapDelete`

#### Responses

- **200** — Successful operation


---

## Space

An indoor space: a `building` or a `vessel`.

### Get all spaces

```
POST /api/mapping/space/public
```

**Operation ID:** `spaceAll`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

#### Responses

- **200** — Successful operation
  - *Example (application/json):*
    ```json
    {
      "spaces": [
        {
          "buid": "building_ABC-123",
          "name": "University of Cyprus",
          "coordinates_lat": "35.69681975652278",
          "coordinates_lon": "51.30831956863403",
          "bucode": "ucy",
          "is_published": "true",
          "space_type": "building"
        },
        {
          "buid": "vessel_ABC-123",
          "name": "Fast Ship",
          "coordinates_lat": "35.69681975652278",
          "coordinates_lon": "51.30831956863403",
          "bucode": "fstship",
          "is_published": "true",
          "space_type": "vessel"
        }
      ]
    }
    ```


### Get a space

```
POST /api/mapping/space/get
```

**Operation ID:** `spaceGet`

Based on the buid retrieve a space.

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `SpaceId`

#### Responses

- **200** — Successful operation


### Add a space

```
POST /api/auth/mapping/space/add
```

**Operation ID:** `addSpace`

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `SpaceAdd`

#### Responses

- **200** — Successful operation


### Update a space

```
POST /api/auth/mapping/space/update
```

**Operation ID:** `updateSpace`

Provide the new fields that you wish to update.

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `SpaceUpdate`

#### Responses

- **200** — Successful operation


### Sets the coOwners array of a user. Passing empty CoOwners will erase them

```
POST /api/auth/mapping/space/coowners
```

**Operation ID:** `shareSpace`

An owner of the space can add co-owners.

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | coownerId |

**Body Schema:** `SetCoOwners`

#### Responses

- **200** — Successful operation


### User access to building

```
POST /api/auth/mapping/space/access
```

**Operation ID:** `userAccess`

Returns whether a user has access to a particular space.

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | coownerId |

**Body Schema:** `CanAccess`

#### Responses

- **200** — Successful operation


### Delete a Space

```
POST /api/auth/mapping/space/delete
```

**Operation ID:** `deleteSpace`

Provide the buid and your access token.

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `SpaceDelete`

#### Responses

- **200** — Successful operation


### Get user owned/co-owned spaces

```
POST /api/auth/mapping/space/accessible
```

**Operation ID:** `spaceAllAccessible`

Based on user's `owner_id` all the spaces are retrieved.

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

#### Responses

- **200** — Successful operation


### Get user owned spaces

```
POST /api/auth/mapping/space/user
```

**Operation ID:** `spaceAllOwned`

Based on user's `owner_id` all the spaces are retrieved.

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation


### Get near-by spaces

```
POST /api/auth/mapping/space/coordinates
```

**Operation ID:** `spaceCoords`

Returns spaces near to the given coordinates.
`range` is in meters and is optional. If not given it uses a default range of `50`.
The maximum range is `500`.


🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `SpaceCoords`

#### Responses

- **200** — Successful operation


---

## Space:Campus

A collection of spaces.

### Get the SpaceSet of a campus

```
POST /api/mapping/campus/get
```

**Operation ID:** `campusGet`

Returns a group of Spaces that belong to a Campus

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Campus description |

**Body Schema:** `CampusGet`

#### Responses

- **200** — Successful operation


### Add Campus

```
POST /api/auth/mapping/campus/add
```

**Operation ID:** `campusAdd`

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Campus description |

**Body Schema:** `CampusAdd`

#### Responses

- **200** — Successful operation


### Update Campus

```
POST /api/auth/mapping/campus/update
```

**Operation ID:** `campusUpdate`

CHECK: On frontend(js) buildings and greeklish are not set in the form.


🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Campus description |

**Body Schema:** `CampusUpdate`

#### Responses

- **200** — Successful operation


### Delete Campus

```
POST /api/auth/mapping/campus/delete
```

**Operation ID:** `campusDelete`

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Campus description |

**Body Schema:** `CampusDelete`

#### Responses

- **200** — Successful operation


### Get user's Campus

```
POST /api/auth/mapping/campus/user
```

**Operation ID:** `campusUser`

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Campus description |

#### Responses

- **200** — Successful operation


---

## Space:Connection

Allows navigation between POIs.
That is the vertice between edges (POIs).
It does not contain a location, but instead the two POIs it links.
The POIs can be either a `connector` POI or a non-connector POI (regular POI).
Regular POIs are always at the beginning or at the end of a calculated route (see [Space:POI](#/Space%3APOI)).

### Retrieve all connections of a floor

```
POST /api/mapping/connection/floor/all
```

**Operation ID:** `conAllFloor`

Provide buid and floor in order to retrieve all connections of that floor

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `FloorAll`

#### Responses

- **200** — Successful operation


### Retrieve all connections of a space

```
POST /api/mapping/connection/floors/all
```

**Operation ID:** `conAllFloors`

Provide buid in order to retrieve all connections of that space

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

#### Responses

- **200** — Successful operation


### Add a connection

```
POST /api/auth/mapping/connection/add
```

**Operation ID:** `conAdd`

Provide information for two POIs in order to add a connection.

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `ConnectionAdd`

#### Responses

- **200** — Successful operation


### Delete a connection

```
POST /api/auth/mapping/connection/delete
```

**Operation ID:** `conDelete`

Provide information about the connection you wish to delete

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `ConnectionDelete`

#### Responses

- **200** — Successful operation


---

## Space:Floor

A `floor` within a space.

### Get all floors

```
POST /api/mapping/floor/all
```

**Operation ID:** `floorAll`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `SpaceAll`

#### Responses

- **200** — Successful operation


### Add floor

```
POST /api/auth/mapping/floor/add
```

**Operation ID:** `floorAdd`

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Floor description |

**Body Schema:** `FloorAdd`

#### Responses

- **200** — Successful operation


### Delete floor

```
POST /api/auth/mapping/floor/delete
```

**Operation ID:** `floorDelete`

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Floor description |

**Body Schema:** `FloorDelete`

#### Responses

- **200** — Successful operation


---

## Space:Floorplan

Floorplan images and floor tiles

### Download a floorplan in base64

```
POST /api/floorplans64/{buid}/{floor_number}
```

**Operation ID:** `floorplan64BuidFloor`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `buid` | path | string | ✅ Yes |  |
| `floor_number` | path | string | ✅ Yes |  |
| `Body` | body | object | ✅ Yes | Empty json |

#### Responses

- **200** — Successful operation


### Download multiple `floors` floorplans in base64

```
POST /api/floorplans64/all/{buid}/{floors}
```

**Operation ID:** `floorplan64AllBuidFloor`

Used by the backup operation.
Floors are space separated: `-1 0 1`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `buid` | path | string | ✅ Yes |  |
| `floors` | path | string | ✅ Yes |  |
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation
  - *Example (application/json):*
    ```json
    {
      "all_floors": [
        "<floor1 BASE64>",
        "<floor2 BASE64>"
      ]
    }
    ```


### Uploads a floorplan

```
POST /api/mapping/floor/floorplan/upload
```

**Operation ID:** `floorplanUpload`

Used by architect.
Zoom level no longer affects the quality (handled in frontend).
`MIN_ZOOM_UPLOAD` has to be respected though (to ensure that the space
is accurately placed on the map).

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation


### Get link of a zip containing all the floor tiles

```
POST /api/floortiles/{buid}/{floor_number}
```

**Operation ID:** `floorplanTilesZipLink`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `buid` | path | string | ✅ Yes |  |
| `floor_number` | path | string | ✅ Yes |  |
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation


### Download a specific tile file

```
GET /api/floortiles/{buid}/{floor_number}/{file}
```

**Operation ID:** `floorplanTilesFile`

Not sure about that..

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `buid` | path | string | ✅ Yes |  |
| `floor_number` | path | string | ✅ Yes |  |
| `file` | path | string | ✅ Yes |  |
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation


### Gets a tile zip per floor?

```
POST /api/floortiles/zip/{buid}/{floor_number}
```

**Operation ID:** `floorplanTilesZipFloor`

Used by Android Navigator

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `buid` | path | string | ✅ Yes |  |
| `floor_number` | path | string | ✅ Yes |  |
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation


---

## Space:POI

A Point of Interest (POI) in a floor.
The POI type might be:
        - from a predefined list (e.g., elevator, stair, entrance)
        - any other custom type (from a string)
        - or the special `connector` type.

**Special POI `connector` type:**
A **connector** is essentially an edge on the **navigation map**.
A **navigation map** contains edges (either connectors or regular POIs), and vertices ([Space:Connection](#/Space%3AConnection)).

The non-connector POIs **must be leafs**. In simpler words, a non-connector POI can be either the beginning,
or the end of a **route**, but never in between. This was a design decision.

To create a **connector**, one must drag [this](/architect/build/images/edge-connector.png) icon from the architect.

### Get POIs of a floor

```
POST /api/mapping/pois/floor/all
```

**Operation ID:** `poisAllFloor`

Provide buid and floor in order to retrieve all POIs of that floor

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `FloorAll`

#### Responses

- **200** — Successful operation


### Get POIs of a space

```
POST /api/mapping/pois/space/all
```

**Operation ID:** `poisAllBuilding`

Provide buid in order to retrieve all POIs of that Space

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

#### Responses

- **200** — Successful operation


### Search for POIs

```
POST /api/mapping/pois/search
```

**Operation ID:** `poisSearch`

Provide cuid and buid to retrieve POIs based on letters. Supports greeklish search.

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `PoisSearch`

#### Responses

- **200** — Successful operation


### Add a POI

```
POST /api/auth/mapping/pois/add
```

**Operation ID:** `poisAdd`

Provide required fields in orded to add a POI in a specific floor, inside a space

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `PoisAdd`

#### Responses

- **200** — Successful operation


### Delete a POI

```
POST /api/auth/mapping/pois/delete
```

**Operation ID:** `poisDelete`

Provide buid and puid in order to delete a POI

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `PoisDelete`

#### Responses

- **200** — Successful operation


### Update a POI

```
POST /api/auth/mapping/pois/update
```

**Operation ID:** `poisUpdate`

Provide the new fields that you wish to update

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `PoisUpdate`

#### Responses

- **200** — Successful operation


---

## User

Anyplace account: local or a Google account.

### Adds a new user

```
POST /api/user/register
```

**Operation ID:** `userRegister`

Registers a local user.

Google login is also available.
See endpoint: [/api/user/login/google](/#/User/loginGoogle)

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Name and Surname |

**Body Schema:** `UserRegister`

#### Responses

- **200** — Successful operation


### Login for local users

```
POST /api/user/login
```

**Operation ID:** `loginLocal`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Name and Surname |

**Body Schema:** `UserLogin`

#### Responses

- **200** — success
  - *Example (application/json):*
    ```json
    {
      "user": {
        "name": "Alan Turing",
        "email": "Alan@turing.com",
        "username": "turing",
        "access_token": "apLocal_ABC123ap",
        "external": "anyplace",
        "type": "user",
        "owner_id": "turing_12341234_local"
      },
      "status": "success",
      "message": "Successfully found user.",
      "status_code": 200
    }
    ```


### Refreshes a user login using the local `access_token`.
NOTE: Only for local accounts.

```
POST /api/user/refresh
```

**Operation ID:** `refreshLocal`

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | accessToken |

**Body Schema:** `LocalAccessToken`

#### Responses

- **200** — success


### Login for Google users

```
POST /api/user/login/google
```

**Operation ID:** `loginGoogle`

Login or register (on the first login) to Anyplace using a Google account.

The Google OAuth token is used retrieving the anyplace account.
For all other requests, it uses the Anyplace Access Token, just like the local accounts.


#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Login using a Google account.   On the **first** login an An... |

**Body Schema:** `UserLoginGoogle`

#### Responses

- **200** — success
  - *Example (application/json):*
    ```json
    {
      "user": {
        "name": "Alan Turing",
        "access_token": "apGoogle_ABC123ap",
        "external": "google",
        "type": "user",
        "owner_id": "123123_google"
      },
      "status": "success",
      "message": "User exists (or created).",
      "status_code": 200
    }
    ```


---

## User:Admin

Priviledged tasks for `admin` or `moderators`

### Update user

```
POST /api/auth/user/update
```

**Operation ID:** `usersUpdate`

Provide a `user_id` and at least one optional of the sample parameters to update a user.

The below operations can be performed, according to user `type`:
`User`: normal users can update their information: `name`, `username`, `password`, `email`/
`Moderator`: can also edit users
`Admin`: can also promote users to `moderators`.


🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes | Space description |

**Body Schema:** `UserUpdate`

#### Responses

- **200** — Successful operation


### Retrieves all user accounts

```
POST /api/auth/moderator/users/all
```

**Operation ID:** `usersAll`

Only for the moderators.

🔒 **Authentication Required**

#### Parameters

| Name | In | Type | Required | Description |
|------|----|------|----------|-------------|
| `Body` | body | object | ✅ Yes |  |

#### Responses

- **200** — Successful operation


---

# Schemas (Definitions)

## APs

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `floor` | string | `0` |

## APsId

| Property | Type | Example |
|----------|------|---------|
| `ids` | array | `["00:11:74:b3:a6:e1", "00:11:74:b3:a6:c1", "8c:dc:...` |

## CampusAdd

| Property | Type | Example |
|----------|------|---------|
| `cuid` | string | `ucy` |
| `description` | string | `University campus located at..` |
| `name` | string | `ucy campus` |
| `greeklish` | string | `true` |
| `buids` | array | `["buid-1", "buid-2", "buid-3"]` |

## CampusDelete

| Property | Type | Example |
|----------|------|---------|
| `cuid` | string | `Aphrodite` |

## CampusGet

| Property | Type | Example |
|----------|------|---------|
| `cuid` | string | `ucy` |

## CampusUpdate

| Property | Type | Example |
|----------|------|---------|
| `cuid` | string | `Alpha` |
| `description` | string | `University campus` |
| `name` | string | `ucy` |
| `greeklish` | boolean | `False` |
| `buids` | array | `["buid-1", "buid-2"]` |

## CanAccess

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_abc-1234-abc_567` |

## ConnectionAdd

| Property | Type | Example |
|----------|------|---------|
| `is_published` | string | `true` |
| `buid_a` | string | `building_84c01910-f4a4-4b63-a0d5-d74300e30be6_1617...` |
| `floor_a` | string | `0` |
| `pois_a` | string | `poi_4e9806d4-a0a7-4107-87ff-485b80570471` |
| `buid_b` | string | `building_84c01910-f4a4-4b63-a0d5-d74300e30be6_1617...` |
| `floor_b` | string | `0` |
| `pois_b` | string | `poi_4e9806d4-a0a7-4107-87ff-485b80570473` |
| `buid` | string | `building_84c01910-f4a4-4b63-a0d5-d74300e30be6_1617...` |
| `edge_type` | string | `hallway` |

## ConnectionDelete

| Property | Type | Example |
|----------|------|---------|
| `buid_a` | string | `building_84c01910-f4a4-4b63-a0d5-d74300e30be6_1617...` |
| `pois_a` | string | `poi_4e9806d4-a0a7-4107-87ff-485b80570471` |
| `buid_b` | string | `building_84c01910-f4a4-4b63-a0d5-d74300e30be6_1617...` |
| `pois_b` | string | `poi_4e9806d4-a0a7-4107-87ff-485b80570473` |

## FloorAdd

| Property | Type | Example |
|----------|------|---------|
| `is_published` | string | `false` |
| `buid` | string | `building_636caa6f-7ad4-4303-87fb-63cee9a482d0_1626...` |
| `floor_name` | string | `` |
| `description` | string | `first floor` |
| `floor_number` | string | `-1` |

## FloorAll

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `floor_number` | string | `1` |

## FloorDelete

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_636caa6f-7ad4-4303-87fb-63cee9a482d0_1626...` |
| `floor_number` | string | `-1` |

## Heatmap

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `floor` | string | `0` |

## HeatmapTiles

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `floor` | string | `0` |
| `x` | integer | `2486415` |
| `y` | integer | `1659305` |
| `z` | integer | `22` |

## HeatmapTime

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `floor` | string | `0` |
| `timestampX` | string | `1000` |
| `timestampY` | string | `1579620960000` |

## HeatmapTimeTiles

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `floor` | string | `0` |
| `x` | integer | `2486415` |
| `y` | integer | `1659305` |
| `z` | integer | `22` |
| `timestampX` | string | `1319572080000` |
| `timestampY` | string | `1579620960000` |

## LocalAccessToken

| Property | Type | Example |
|----------|------|---------|
| `access_token` | string | `apLocal_123ABC_ap` |

## PoisAdd

| Property | Type | Example |
|----------|------|---------|
| `name` | string | `stairs` |
| `buid` | string | `building_636caa6f-7ad4-4303-87fb-63cee9a482d0_1626...` |
| `floor_name` | string | `1` |
| `floor_number` | string | `1` |
| `is_building_entrance` | string | `true` |
| `is_door` | string | `false` |
| `description` | string | `Entrance staircase` |
| `coordinates_lat` | string | `25.00683111039714` |
| `coordinates_lon` | string | `55.52313655614853` |
| `pois_type` | string | `Stair` |
| `is_published` | string | `true` |

## PoisDelete

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_636caa6f-7ad4-4303-87fb-63cee9a482d0_1626...` |
| `puid` | string | `poi_f387b832-301e-4f9a-b735-1ee5dabc1ed0` |

## PoisSearch

| Property | Type | Example |
|----------|------|---------|
| `cuid` | string | `ucy` |
| `letters` | string | `toual` |
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `greeklish` | string | `true` |

## PoisUpdate

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_636caa6f-7ad4-4303-87fb-63cee9a482d0_1626...` |
| `puid` | string | `poi_f387b832-301e-4f9a-b735-1ee5dabc1ed0` |
| `name` | string | `Main door` |
| `is_building_entrance` | string | `false` |
| `is_door` | string | `true` |
| `description` | string | `Entrance door` |
| `coordinates_lat` | string | `35.00683111039714` |
| `coordinates_lon` | string | `45.52313655614853` |
| `pois_type` | string | `Entrance` |
| `is_published` | string | `true` |

## PredictFloor

| Property | Type | Example |
|----------|------|---------|
| `first` | object | `{"MAC": "04:a1:51:a3:13:25", "rss": "-76"}` |
| `wifi` | array | `["{\"MAC\": \"24:b6:57:ae:40:30\", \"rss\": \"-85\...` |
| `dlat` | number | `35.14451561520357` |
| `dlong` | number | `33.4112872928381` |

## RadiomapBbox

| Property | Type | Example |
|----------|------|---------|
| `coordinates_lat` | string | `35.14447778163889` |
| `coordinates_lon` | string | `33.41125577688217` |
| `floor_number` | string | `0` |
| `range` | string | `222` |

## RadiomapDelete

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_12345678-1234-1234-1234-123456789123_1234...` |
| `floor` | string | `0` |
| `lat1` | string | `34.9203791974277` |
| `lon1` | string | `3.013322331003295` |
| `lat2` | string | `34.92033411232339` |
| `lon2` | string | `33.01325326412116` |

## RadiomapDeleteTime

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_12345678-1234-1234-1234-123456789123_1234...` |
| `floor` | string | `0` |
| `lat1` | string | `34.9203791974277` |
| `lon1` | string | `33.013322331003295` |
| `lat2` | string | `34.92033411232339` |
| `lon2` | string | `33.01325326412116` |
| `timestampX` | string | `0` |
| `timestampY` | string | `1617117985695` |

## RadiomapFloor

| Property | Type | Example |
|----------|------|---------|
| `coordinates_lat` | string | `35.14447778163889` |
| `coordinates_lon` | string | `33.41125577688217` |
| `floor_number` | string | `1` |

## RadiomapFloors

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `floors` | string | `-1 0 1` |

## RadiomapSpace

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `floor` | string | `1` |

## RadiomapUpload

*No properties defined.*

## Route

| Property | Type | Example |
|----------|------|---------|
| `pois_from` | string | `poi_908db729-0edd-4817-ac34-ca99b25d0f3d` |
| `pois_to` | string | `poi_bcf9d54a-9f9f-4ae6-957e-2d37787e3dfb` |

## RouteXY

| Property | Type | Example |
|----------|------|---------|
| `coordinates_lon` | string | `33.41028` |
| `coordinates_lat` | string | `35.145` |
| `floor_number` | string | `1` |
| `pois_to` | string | `poi_8a5ac942-3a02-453e-8cda-5b6870ecf92b` |

## SetCoOwners

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_abc-1234-abc_567` |
| `co_owners` | array | `["userID1", "userID2"]` |

## SpaceAdd

| Property | Type | Example |
|----------|------|---------|
| `name` | string | `203` |
| `description` | string | `Conference room` |
| `url` | string | `www.myBuildingUrl.com` |
| `address` | string | `2783 Harper Street` |
| `coordinates_lat` | string | `25.00683111039714` |
| `coordinates_lon` | string | `55.52313655614853` |
| `space_type` | string | `building, vessel` |
| `is_published` | string | `true` |

## SpaceAll

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |

## SpaceCoords

| Property | Type | Example |
|----------|------|---------|
| `coordinates_lat` | string | `25.00683111039714` |
| `coordinates_lon` | string | `55.52313655614853` |
| `range` | integer | `100` |

## SpaceDelete

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_636caa6f-7ad4-4303-87fb-63cee9a482d0_1626...` |

## SpaceGetResp

| Property | Type | Example |
|----------|------|---------|
| `coordinates_lat` | string | `35.14442624023263` |
| `description` | string | `Κοσμητεία ΣΘΕΕ
Τμήμα Βιολογικών Επιστημών
Τμήμα Φυ...` |
| `name` | string | `UCY, FST02/ΘΕΕ02, New Campus, Nicosia, Cyprus` |
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |
| `bucode` | string | `FST02` |
| `coordinates_lon` | string | `33.41047257184982` |
| `is_published` | string | `true` |
| `type` | string | `building` |

## SpaceId

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423...` |

## SpacePOI

| Property | Type | Example |
|----------|------|---------|
| `pois` | string | `poi_a7035659-881f-4169-9737-914081ee2f61` |

## SpaceUpdate

| Property | Type | Example |
|----------|------|---------|
| `buid` | string | `building_abc-1234-abc_567` |
| `name` | string | `302` |
| `description` | string | `Conference room 2` |
| `url` | string | `www.myBuildingUrl2.com` |
| `address` | string | `2781 Harper Street` |
| `coordinates_lat` | string | `35.00683111039714` |
| `coordinates_lon` | string | `45.52313655614853` |
| `space_type` | string | `building` |
| `is_published` | string | `true` |

## UserLogin

| Property | Type | Example |
|----------|------|---------|
| `username` | string | `username` |
| `password` | string | `password` |

## UserLoginGoogle

| Property | Type | Example |
|----------|------|---------|
| `external` | string | `google` |
| `access_token` | string | `AccessTokenFromGoogle` |
| `name` | string | `Alan Turing` |

## UserRegister

| Property | Type | Example |
|----------|------|---------|
| `name` | string | `Alan Turing` |
| `email` | string | `my_email@gmail.com` |
| `username` | string | `username` |
| `password` | string | `password` |

## UserUpdate

| Property | Type | Example |
|----------|------|---------|
| `name` | string | `Alan Turing` |
| `username` | string | `username2` |
| `password` | string | `password2` |
| `email` | string | `my_email2@gmail.com` |
| `type` | string | `moderator` |
| `user_id` | string | `username_18925790_231645_local` |

## Version

| Property | Type | Example |
|----------|------|---------|
| `version` | string | `1.0.0` |
| `variant` | string | `alpha` |
