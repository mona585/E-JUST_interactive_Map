/*
 * Anyplace: A free and open Indoor Navigation Service with superb accuracy!
 *
 * Anyplace is a first-of-a-kind indoor information service offering GPS-less
 * localization, navigation and search inside buildings using ordinary smartphones.
 *
 * Author(s): Kyriakos Georgiou
 *
 * Supervisor: Demetrios Zeinalipour-Yazti
 *
 * URL: http://anyplace.cs.ucy.ac.cy
 * Contact: anyplace@cs.ucy.ac.cy
 *
 * Copyright (c) 2015, Data Management Systems Lab (DMSL), University of Cyprus.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the “Software”), to deal in the
 * Software without restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so, subject to the
 * following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 */
app.controller('FloorController', ['$scope', '$compile', 'AnyplaceService', 'GMapService', 'AnyplaceAPIService', function ($scope, $compile, AnyplaceService, GMapService, AnyplaceAPIService) {
    $scope.anyService = AnyplaceService;
    $scope.anyAPI = AnyplaceAPIService;

    $scope.xFloors = [];

    $scope.data = {
        floor_plan_coords: {},
        floor_plan_base64_data: {},
        floor_plan_groundOverlay: null
    };

    // --- Optimized Floorplan Cache & Prefetch Infrastructure ---
    var floorplanLRUCache = {}; // key -> { overlay, img, bounds, buid, floor_number, loadedAt }
    var floorplanLRUOrder = [];  // [key_oldest, ..., key_newest]
    var MAX_FLOORPLAN_CACHE = 3; // Strictly bounded to 3 decoded floorplans (~253 MB max bitmap memory)
    var inFlightFloorplans = {}; // key -> Promise<{ overlay, img, bounds }>
    var currentLoadSequence = 0; // Monotonically increasing sequence ID
    var preloadTimeoutId = null; // Timer for background adjacent preloading

    function getCacheKey(buid, floor_number) {
        return String(buid) + ":" + String(floor_number);
    }

    function touchCacheKey(key) {
        var idx = floorplanLRUOrder.indexOf(key);
        if (idx !== -1) {
            floorplanLRUOrder.splice(idx, 1);
        }
        floorplanLRUOrder.push(key);
    }

    function evictOldestCacheEntry() {
        while (floorplanLRUOrder.length > MAX_FLOORPLAN_CACHE) {
            var evictKey = floorplanLRUOrder.shift();
            var entry = floorplanLRUCache[evictKey];
            if (entry) {
                LOG.D2("LRU evicting floorplan: " + evictKey);
                if (entry.overlay && $scope.data.floor_plan_groundOverlay !== entry.overlay) {
                    entry.overlay.destroy();
                }
                delete floorplanLRUCache[evictKey];
            }
        }
    }

    function clearFloorplanCache() {
        if (preloadTimeoutId) {
            clearTimeout(preloadTimeoutId);
            preloadTimeoutId = null;
        }
        for (var k in floorplanLRUCache) {
            if (floorplanLRUCache.hasOwnProperty(k)) {
                try {
                    if (floorplanLRUCache[k].overlay) {
                        floorplanLRUCache[k].overlay.destroy();
                    }
                } catch (e) {}
            }
        }
        floorplanLRUCache = {};
        floorplanLRUOrder = [];
        inFlightFloorplans = {};
    }

    function getOrCreateFloorplan(buid, floor_number, flObj) {
        var key = getCacheKey(buid, floor_number);

        // 1. Fast Cache Hit
        if (floorplanLRUCache[key]) {
            touchCacheKey(key);
            return Promise.resolve(floorplanLRUCache[key]);
        }

        // 2. In-Flight Request Deduplication: reuse existing promise if already downloading
        if (inFlightFloorplans[key]) {
            return inFlightFloorplans[key];
        }

        // 3. Initiate HTTP fetch and asynchronous decode
        var loadPromise = new Promise(function (resolve, reject) {
            var jsonReq = $scope.anyService.jsonReq;
            var httpPromise = AnyplaceAPIService.downloadFloorPlan(jsonReq, buid, floor_number);
            httpPromise.then(
                function (resp) {
                    var data = resp.data;
                    if (!data || data.length === 0) {
                        delete inFlightFloorplans[key];
                        reject(new Error("Empty floorplan data received"));
                        return;
                    }

                    // Resolve coordinates from flObj or availableFloors
                    var fl = flObj;
                    if (!fl && $scope.anyService.availableFloors) {
                        fl = $scope.anyService.availableFloors[floor_number];
                    }
                    var bl_lat = fl ? fl.bottom_left_lat : 0;
                    var bl_lng = fl ? fl.bottom_left_lng : 0;
                    var tr_lat = fl ? fl.top_right_lat : 0;
                    var tr_lng = fl ? fl.top_right_lng : 0;

                    var imageBounds = new google.maps.LatLngBounds(
                        new google.maps.LatLng(bl_lat, bl_lng),
                        new google.maps.LatLng(tr_lat, tr_lng)
                    );

                    // Decode image asynchronously off the main rendering thread
                    var img = new Image();
                    img.src = "data:image/png;base64," + data;

                    var onImageDecoded = function () {
                        // Create overlay with retained DOM elements
                        var overlay = new USGSOverlay(imageBounds, img, null);
                        var entry = {
                            key: key,
                            overlay: overlay,
                            img: img,
                            bounds: imageBounds,
                            buid: buid,
                            floor_number: floor_number,
                            loadedAt: Date.now()
                        };

                        floorplanLRUCache[key] = entry;
                        touchCacheKey(key);
                        evictOldestCacheEntry();
                        delete inFlightFloorplans[key];
                        resolve(entry);
                    };

                    if (typeof img.decode === "function") {
                        img.decode().then(onImageDecoded).catch(function () {
                            if (img.complete) {
                                onImageDecoded();
                            } else {
                                img.onload = onImageDecoded;
                                img.onerror = function (e) {
                                    delete inFlightFloorplans[key];
                                    reject(e);
                                };
                            }
                        });
                    } else {
                        if (img.complete) {
                            onImageDecoded();
                        } else {
                            img.onload = onImageDecoded;
                            img.onerror = function (e) {
                                delete inFlightFloorplans[key];
                                reject(e);
                            };
                        }
                    }
                },
                function (err) {
                    delete inFlightFloorplans[key];
                    reject(err);
                }
            );
        });

        inFlightFloorplans[key] = loadPromise;
        return loadPromise;
    }

    function scheduleAdjacentPreload(buid, currentFloorNumber) {
        if (preloadTimeoutId) {
            clearTimeout(preloadTimeoutId);
            preloadTimeoutId = null;
        }

        // Idle delay of 1200ms: only preload when user is idle, never during navigation/pan/zoom
        preloadTimeoutId = setTimeout(function () {
            if (!$scope.xFloors || $scope.xFloors.length <= 1) return;
            if (!$scope.anyService.selectedBuilding || buid !== $scope.anyService.selectedBuilding.buid) return;

            // Find current floor index
            var currentIdx = -1;
            for (var i = 0; i < $scope.xFloors.length; i++) {
                if (String($scope.xFloors[i].floor_number) === String(currentFloorNumber)) {
                    currentIdx = i;
                    break;
                }
            }
            if (currentIdx === -1) return;

            var candidates = [];
            if (currentIdx + 1 < $scope.xFloors.length) {
                candidates.push($scope.xFloors[currentIdx + 1]);
            }
            if (currentIdx - 1 >= 0) {
                candidates.push($scope.xFloors[currentIdx - 1]);
            }

            // Preload sequentially (concurrency = 1)
            function preloadStep(idx) {
                if (idx >= candidates.length) return;
                var cand = candidates[idx];
                var candKey = getCacheKey(buid, cand.floor_number);

                if (floorplanLRUCache[candKey] || inFlightFloorplans[candKey]) {
                    preloadStep(idx + 1);
                    return;
                }

                LOG.D2("Preloading adjacent floor: " + cand.floor_number);
                getOrCreateFloorplan(buid, cand.floor_number, cand).then(
                    function () {
                        preloadStep(idx + 1);
                    },
                    function () {
                        preloadStep(idx + 1);
                    }
                );
            }

            preloadStep(0);
        }, 1200);
    }

    var _clearFloors = function () {
        clearFloorplanCache();
        $scope.removeFloorPlan();
        $scope.xFloors = [];
        $scope.myFloorId = 0;
        $scope.myFloors = {};
    };

    $scope.$watch('anyService.selectedBuilding', function (newVal, oldVal) {
        clearFloorplanCache();
        if (newVal && newVal.buid) {
            $scope.fetchAllFloorsForBuilding(newVal);
        } else {
            $scope.removeFloorPlanOverlay();
        }
    });

    $scope.$watch('anyService.selectedFloor', function (newVal, oldVal) {
        if (newVal !== undefined && newVal !== null) {
            $scope.fetchFloorPlanOverlay(newVal);
            // TODO:PV see equivalent point in anyplace_viewer_campus (also similar thing with architect)
            // GMapService.gmap.panTo(_latLngFromBuilding($scope.anyService.selectedBuilding));
            // GMapService.gmap.setZoom(20);

            try {
                if (typeof(Storage) !== "undefined" && localStorage) {
                    localStorage.setItem("lastFloor", newVal.floor_number);
                }
            } catch (e) {

            }
        }
    });

    $scope.removeFloorPlanOverlay = function () {
        if ($scope.data.floor_plan_groundOverlay) {
            $scope.data.floor_plan_groundOverlay.setMap(null);
        }
    };

    var _latLngFromBuilding = function (b) {
        if (b && b.coordinates_lat && b.coordinates_lon) {
            return {
                lat: parseFloat(b.coordinates_lat),
                lng: parseFloat(b.coordinates_lon)
            }
        }
        return undefined;
    };

    $scope.orderByFloorNo = function (floor) {
        if (!floor || LPUtils.isNullOrUndefined(floor.floor_number)) {
            return 0;
        }
        return parseInt(floor.floor_number);
    };

    $scope.fetchAllFloorsForBuilding = function (b) {
        var jsonReq = AnyplaceService.jsonReq;
        jsonReq.buid = b.buid;

        var promise = AnyplaceAPIService.allBuildingFloors(jsonReq);
        promise.then(
            function (resp) {
                var data = resp.data;
                if (typeof data === "string") {
                    try { data = JSON.parse(data); } catch (e) { }
                }
                $scope.xFloors = (data && data.floors) ? data.floors : [];
                $scope.xFloors = $scope.xFloors.sort(function (a, b) {
                    return parseInt(a.floor_number) - parseInt(b.floor_number)
                });

                $scope.anyService.availableFloors = {};
                for (var ind = 0; ind < $scope.xFloors.length; ind++) {
                    var fl = $scope.xFloors[ind];
                    $scope.anyService.availableFloors[fl.floor_number] = fl;
                }

                // give priority to floor in url parameter - if exists
                if ($scope.urlFloor) {
                    for (var k = 0; k < $scope.xFloors.length; k++) {
                        if ($scope.urlFloor == $scope.xFloors[k].floor_number) {
                            $scope.anyService.selectedFloor = $scope.xFloors[k];
                            return;
                        }
                    }
                }

                // give 2nd priority to floor found in localStorage
                try {
                    if (typeof(Storage) !== "undefined" && localStorage && !LPUtils.isNullOrUndefined(localStorage.getItem('lastBuilding')) && !LPUtils.isNullOrUndefined(localStorage.getItem('lastFloor'))) {
                        for (var i = 0; i < $scope.xFloors.length; i++) {
                            if (String($scope.xFloors[i].floor_number) === String(localStorage.getItem('lastFloor'))) {
                                $scope.anyService.selectedFloor = $scope.xFloors[i];
                                return;
                            }
                        }
                    }
                } catch (e) {

                }

                // try loading floor 0
                for (var j = 0; j < $scope.xFloors.length; j++) {
                    if ($scope.xFloors[j].floor_number == "0") {
                        $scope.anyService.selectedFloor = $scope.xFloors[j];
                        return;
                    }
                }

                // last resort, default floor
                if ($scope.xFloors[0]) {
                    $scope.anyService.selectedFloor = $scope.xFloors[0];
                }
            },
            function (resp) {
                ShowError($scope, resp, ERR_FETCH_ALL_FLOORS, true);
            }
        );
    };

    $scope.fetchFloorPlanOverlay = function (floorObj) {
        var targetFloor = floorObj || $scope.anyService.selectedFloor;
        if (!targetFloor || targetFloor.floor_number === undefined || targetFloor.floor_number === null ||
            !$scope.anyService.selectedBuilding || !$scope.anyService.selectedBuilding.buid) {
            return;
        }

        var buid = $scope.anyService.selectedBuilding.buid;
        var floor_number = targetFloor.floor_number;
        var seq = ++currentLoadSequence;
        var key = getCacheKey(buid, floor_number);

        // INSTANT PATH: If cached, attach immediately with zero delay (<1ms)
        if (floorplanLRUCache[key]) {
            var cached = floorplanLRUCache[key];
            touchCacheKey(key);

            if ($scope.data.floor_plan_groundOverlay && $scope.data.floor_plan_groundOverlay !== cached.overlay) {
                $scope.data.floor_plan_groundOverlay.setMap(null);
            }

            $scope.data.floor_plan_groundOverlay = cached.overlay;
            cached.overlay.setMap(GMapService.gmap);

            scheduleAdjacentPreload(buid, floor_number);
            return;
        }

        // ASYNC PATH: Deduplicated fetch & async decode
        getOrCreateFloorplan(buid, floor_number, targetFloor).then(
            function (entry) {
                // Ensure request is still current (prevents race conditions from fast switching)
                if (seq === currentLoadSequence &&
                    $scope.anyService.selectedBuilding &&
                    buid === $scope.anyService.selectedBuilding.buid &&
                    $scope.anyService.selectedFloor &&
                    String(floor_number) === String($scope.anyService.selectedFloor.floor_number)) {

                    if ($scope.data.floor_plan_groundOverlay && $scope.data.floor_plan_groundOverlay !== entry.overlay) {
                        $scope.data.floor_plan_groundOverlay.setMap(null);
                    }

                    $scope.data.floor_plan_groundOverlay = entry.overlay;
                    entry.overlay.setMap(GMapService.gmap);

                    scheduleAdjacentPreload(buid, floor_number);
                }
            },
            function (err) {
                LOG.E("Failed to load floorplan for " + buid + " fl: " + floor_number, err);
            }
        );
    };

    var canvasOverlay = null;
    $scope.isCanvasOverlayActive = false;

    $scope.setFloorPlan = function () {
        if (!canvasOverlay) { return; }

        if (AnyplaceService.getBuildingId() === null || AnyplaceService.getBuildingId() === undefined) {
            console.log('building is undefined');
            _err($scope, "Something went wrong. It seems like there is no building selected");
        }

        var newFl = {
            is_published: 'true',
            buid: String(AnyplaceService.getBuildingId()),
            floor_name: String($scope.newFloorNumber),
            description: String($scope.newFloorNumber),
            floor_number: String($scope.newFloorNumber)
        };

        $scope.myFloors[$scope.myFloorId] = newFl;
        $scope.myFloorId++;

        // create the proper image inside the canvas
        canvasOverlay.drawBoundingCanvas();

        // create the ground overlay and destroy the canvasOverlay object
        // and also set the floor_plan_coords in $scope.data
        var bl = canvasOverlay.bottom_left_coords;
        var tr = canvasOverlay.top_right_coords;
        $scope.data.floor_plan_coords.bottom_left_lat = bl.lat();
        $scope.data.floor_plan_coords.bottom_left_lng = bl.lng();
        $scope.data.floor_plan_coords.top_right_lat = tr.lat();
        $scope.data.floor_plan_coords.top_right_lng = tr.lng();

        var data = canvasOverlay.getCanvas().toDataURL("image/png"); // defaults to png
        $scope.data.floor_plan_base64_data = data;
        var imageBounds = new google.maps.LatLngBounds(
            new google.maps.LatLng(bl.lat(), bl.lng()),
            new google.maps.LatLng(tr.lat(), tr.lng()));
        $scope.data.floor_plan_groundOverlay = new USGSOverlay(imageBounds, data, GMapService.gmap);

        canvasOverlay.setMap(null); // remove the canvas overlay since the groundoverlay is placed
        $('#input-floor-plan').prop('disabled', false);
        $scope.isCanvasOverlayActive = false;

        $scope.addFloorObject(newFl, $scope.anyService.selectedBuilding, $scope.data);
    };

    $scope.removeFloorPlan = function () {
        $scope.data.floor_plan_file = null;
        $scope.data.floor_plan = null;

        if (canvasOverlay) {
            canvasOverlay.setMap(null);
        }

        var x = $('#input-floor-plan');
        x.replaceWith(x = x.clone(true));

        x.prop('disabled', false);

        $scope.isCanvasOverlayActive = false;
    };

    $scope.floorUp = function () {
        for (var i = 0; i < $scope.xFloors.length; i++) {
            if ($scope.xFloors[i].floor_number == $scope.anyService.selectedFloor.floor_number) {
                if (i + 1 < $scope.xFloors.length) {
                    $scope.anyService.selectedFloor = $scope.xFloors[i + 1];
                    return;
                } else {
                    //_warn("There is no other floor above.");
                    return;
                }
            }
        }

        _err($scope, "Floor not found.");
    };

    $scope.floorDown = function () {
        for (var i = 0; i < $scope.xFloors.length; i++) {
            if ($scope.xFloors[i].floor_number == $scope.anyService.selectedFloor.floor_number) {
                if (i - 1 >= 0) {
                    $scope.anyService.selectedFloor = $scope.xFloors[i - 1];
                    return;
                } else {
                    //_warn("There is no other floor below.");
                    return;
                }
            }
        }

        _err($scope, "Floor not found.");
    };

    // pass scope to floor controls in the html
    var floorControls = $('#floor-controls');
    floorControls.replaceWith($compile(floorControls.html())($scope));
}
])
;
