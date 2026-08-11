# Use E-JUST Android application and signing identities

Logger and Navigator will use E-JUST-owned package IDs (`eg.edu.ejust.anyplace.logger` and `eg.edu.ejust.anyplace.navigator`) and university-controlled release signing keys. The original UCY identities cannot be retained safely because their signing keys and publisher custody are unavailable; this sacrifices in-place updates for existing UCY-signed installations but gives E-JUST durable control of releases and signature-restricted service credentials.
