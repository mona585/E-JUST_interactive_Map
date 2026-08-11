# Anyplace Indoor Navigation

This context defines the stable language used by the E-JUST deployment of Anyplace. It covers mapped places and the data used to navigate within them.

## People

**User**:
A person with an Anyplace account and the default permissions assigned to a self-registered account.
_Avoid_: Account, standard user

**Administrator**:
A User with system-wide authority over users and mapped content.
_Avoid_: Operator, superuser

## Mapped Places

**Campus**:
A named group of Spaces presented as one site. A Campus stores the identifiers of its member Spaces.
_Avoid_: Site, building group

**Space**:
An independently mapped venue, normally a building or vessel. User interfaces may label a Space as a building, but repository-wide discussion should use Space.
_Avoid_: Building, venue

**Floor**:
A level within a Space, identified by its floor number and Space identifier.
_Avoid_: Storey, level

**Floorplan**:
The georeferenced image and tile set associated with a Floor.
_Avoid_: Map, blueprint

**Point of Interest (POI)**:
A named, positioned location on a Floor that can be displayed or used in navigation.
_Avoid_: Marker, waypoint

**Connection**:
An edge joining two POIs for routing, such as a hallway, stair, elevator, room, or outdoor link.
_Avoid_: Path, link

## Positioning

**Radiomap**:
The Wi-Fi fingerprint data for a Space and Floor used by the positioning system.
_Avoid_: Heatmap, signal map

**Access Point**:
A detected Wi-Fi transmitter represented in fingerprint and heatmap data.
_Avoid_: Router, beacon
