/**
 *
 The MIT License (MIT)

 Copyright (c) 2015, Kyriakos Georgiou, Marileni Angelidou, Loukas Solea, Data Management Systems Laboratory (DMSL)
 Department of Computer Science, University of Cyprus, Nicosia, CYPRUS,
 dmsl@cs.ucy.ac.cy, http://dmsl.cs.ucy.ac.cy/

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */



app.controller('BuildingController', ['$cookieStore', '$scope', '$compile', '$q', 'GMapService', 'AnyplaceService', 'AnyplaceAPIService', function ($cookieStore, $scope, $compile, $q, GMapService, AnyplaceService, AnyplaceAPIService) {

    $scope.myMarkers = {};
    $scope.myMarkerId = 0;

    $scope.gmapService = GMapService;
    $scope.anyService = AnyplaceService;
    $scope.anyAPI = AnyplaceAPIService;
    $scope.example9model = [];
    $scope.example9data = [];
    $scope.example9settings = {enableSearch: true, scrollable: true};

    $scope.example9modeledit = [];
    $scope.example9dataedit = [];
    $scope.example9settingsedit = {enableSearch: true, scrollable: true};

    $scope.myBuildings = [];

    $scope.myBuildingsHashT = {};
    $scope.myCampus = [];
    $scope.old_campus = [];

    $scope.crudTabSelected = 1;

    $scope.fileToUpload = "";
    $scope.logfile = "";

    $scope.poisTypes = {};
    $scope.catTypes = {};
    $scope.spaceTypes = {};

    $scope.pageLoad = false;

    $scope.crudTabSelected = 1;

    $scope.fetchVersion = function () {
        var jsonReq = {};
        var promise = $scope.anyAPI.version(jsonReq);
        promise.then(
            function (resp) { // on success
                var data = resp.data;
                var prettyVersion=getPrettyVersion(data);
                LOG.D3("Anyplace Version: " + prettyVersion);
                var element = document.getElementById("anyplace-version");
                element.textContent = "v"+prettyVersion;
            },
            function (resp) { console.log("Failed to get version: " + resp.data); }
        );
    };
    $scope.fetchVersion();

    $scope.setCrudTabSelected = function (n) {
        $scope.crudTabSelected = n;
        // Add (1) and Restore (6) work with no building selected (Restore
        // auto-creates the space from the backup), so only guard the tabs
        // that require an existing building: Edit (2), Delete (3), Backup
        // (4) and Share (5).
        if (n !== 1 && n !== 6 && !$scope.anyService.getBuilding()) {
            _err($scope, "No building selected.");
            return;
        }
        var b = $scope.myBuildingsHashT[$scope.anyService.getBuildingId()];
        if (!b) { return; }
        var m = b.marker;
        if (!m) { return; }
        // edit building
        if (n === 2) {
            m.setDraggable(true);
        } else {
            m.setDraggable(false);
        }
    };
    $scope.isCrudTabSelected = function (n) {
        return $scope.crudTabSelected === n;
    };

    $scope.$on("loggedIn", function (event, mass) {
        // BUG: loggedIn event is raised multiple times (3) for some reason,
        // even with the code below
        LOG.D3("loggedIn: Handled")
        $scope.getSpacesAccessible();
        $scope.getUserCampuses();
    });

    $scope.$on("loggedOff", function (event, mass) {
        _clearBuildingMarkersAndModels();
        $scope.myMarkers = {};
        $scope.myMarkerId = 0;
        $scope.myBuildings = [];
        $scope.myBuildingsHashT = {};
    });

    /**
     * @return {string}
     */
    function S4() {
        return (((1 + Math.random()) * 0x10000) | 0).toString(16).substring(1);
    }

    var guid = (S4() + S4() + "-" + S4() + "-4" + S4().substr(0, 3) + "-" + S4() + "-" + S4() + S4() + S4()).toLowerCase();
    var d = new Date();
    document.getElementById("CampusID").value = "cuid_" + guid + "_" + d.getTime();

    var logoPlanInputElement = $('#input-logo');

    logoPlanInputElement.change(function handleImage(e) {
        var reader = new FileReader();
        reader.onload = function (event) {
            var imgObj = new Image();
            imgObj.src = event.target.result;
        };
        reader.readAsDataURL(e.target.files[0]);
    });

    // CHECK: what is LogoPlan ?!?
    // $scope.setLogoPlan = function (cuid) {
    //     LOG.D("setLogoPlan")
    //     var newFl = {
    //         is_published: 'true',
    //         cuid: cuid,
    //         logo: String($scope.newFloorNumber),
    //         description: String($scope.newFloorNumber),
    //         floor_number: String($scope.newFloorNumber)
    //     };
    //
    //     $scope.myFloors[$scope.myFloorId] = newFl;
    //     $scope.myFloorId++;
    //
    //     // create the proper image inside the canvas
    //     canvasOverlay.drawBoundingCanvas();
    //
    //     // create the ground overlay and destroy the canvasOverlay object
    //     // and also set the floor_plan_coords in $scope.data
    //     var bl = canvasOverlay.bottom_left_coords;
    //     var tr = canvasOverlay.top_right_coords;
    //     $scope.data.floor_plan_coords.bottom_left_lat = bl.lat();
    //     $scope.data.floor_plan_coords.bottom_left_lng = bl.lng();
    //     $scope.data.floor_plan_coords.top_right_lat = tr.lat();
    //     $scope.data.floor_plan_coords.top_right_lng = tr.lng();
    //     $scope.data.floor_plan_coords.zoom = GMapService.gmap.getZoom() + "";
    //     var data = canvasOverlay.getCanvas().toDataURL("image/png"); // defaults to png
    //     $scope.data.floor_plan_base64_data = data;
    //     var imageBounds = new google.maps.LatLngBounds(
    //         new google.maps.LatLng(bl.lat(), bl.lng()),
    //         new google.maps.LatLng(tr.lat(), tr.lng()));
    //     $scope.data.floor_plan_groundOverlay = new USGSOverlay(imageBounds, data, GMapService.gmap);
    //
    //     canvasOverlay.setMap(null); // remove the canvas overlay since the groundoverlay is placed
    //     $('#input-floor-plan').prop('disabled', false);
    //     $scope.isCanvasOverlayActive = false;
    //
    //     if (_floorNoExists($scope.newFloorNumber)) {
    //         for (var i = 0; i < $scope.xFloors.length; i++) {
    //             var f = $scope.xFloors[i];
    //             if (!LPUtils.isNullOrUndefined(f)) {
    //                 if (f.floor_number === String($scope.newFloorNumber)) {
    //                     $scope.uploadWithZoom($scope.anyService.selectedBuilding, f, $scope.data);
    //                     break;
    //                 }
    //             }
    //         }
    //     } else {
    //         $scope.addFloorObject(newFl, $scope.anyService.selectedBuilding, $scope.data);
    //     }
    // };

    $scope.$watch('anyService.selectedBuilding', function (newVal, oldVal) {
        if (newVal && newVal.coordinates_lat && newVal.coordinates_lon) {
            // Pan map to selected building
            $scope.gmapService.gmap.panTo(_latLngFromBuilding(newVal));
            $scope.gmapService.gmap.setZoom(19);
            if (typeof(Storage) !== "undefined" && localStorage) {
                localStorage.setItem("lastBuilding", newVal.buid);
            }
        }
        $scope.poisTypes = [
            "Disabled Toilets",
            "Elevator",
            "Entrance",
            "Fire Extinguisher",
            "First Aid/AED",
            "Kitchen",
            "Office",
            "Ramp",
            "Room",
            "Security/Guard",
            "Stair",
            "Toilets",
            "Other"
        ];
    });

    $scope.$watch('anyService.selectedBuilding', function () {
        $scope.spaceTypes = [
            "building",
            "vessel"
        ];
        $scope.spacecategories = [{
            spacecat: "building",
            id: "type1"
        },{
            spacecat: "vessel",
            id: "type2"
        }
        ];
    });

    $scope.$watch('anyService.selectedCampus', function (newVal, oldVal) {
        if (newVal && newVal.cuid) {
            // Pan map to selected building
            if (typeof(Storage) !== "undefined" && localStorage) {
                localStorage.setItem("lastCampus", newVal.cuid);
            }
        }
    });

    var _clearBuildingMarkersAndModels = function () {
        for (var b in $scope.myBuildingsHashT) {
            if ($scope.myBuildingsHashT.hasOwnProperty(b)) {
                $scope.myBuildingsHashT[b].marker.setMap(null);
                delete $scope.myBuildingsHashT[b];
            }
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

    $scope.getSpacesAccessible = function () {
        var jsonReq = {};
        LOG.D2("getSpacesAccessible");
        LOG.D4(jsonReq);
        var promise = $scope.anyAPI.spaceAccessible(jsonReq);
        promise.then(
            function (resp) { // on success
                var data = resp.data;
                $scope.myBuildings = data.spaces;
                var infowindow = new google.maps.InfoWindow({
                    content: '-',
                    maxWidth: 500
                });
                var localStoredBuildingIndex = -1;
                var localStoredBuildingId = undefined;
                if (typeof(Storage) !== "undefined" && localStorage && localStorage.getItem('lastBuilding')) {
                    localStoredBuildingId = localStorage.getItem('lastBuilding');
                }
                for (var i = 0; i < $scope.myBuildings.length; i++) {
                    var b = $scope.myBuildings[i];
                    $scope.example9data[i] = {id: b.buid, label: b.name};
                    $scope.example9dataedit[i] = {id: b.buid, label: b.name};
                    if (localStoredBuildingId && localStoredBuildingId === b.buid) {
                        localStoredBuildingIndex = i;
                    }
                    if (b.is_published === 'true' || b.is_published == true) {
                        b.is_published = true;
                    } else {
                        b.is_published = false;
                    }
                    var marker;
                    if (b.space_type == "vessel") {
                        marker = getMapsIconVesselArchitect(GMapService.gmap, _latLngFromBuilding(b))
                    } else {
                        marker = getMapsIconBuildingArchitect(GMapService.gmap, _latLngFromBuilding(b))
                    }

                    var htmlContent = '<div class="infowindow-scroll-fix">'
                        + '<div class="infowindow-title">'+b.name+'</div>'
                        + '<div class="font-weight-bold">BUID:</div>'
                        + '<input class="form-control input-tiny" value="'+b.buid+'" onClick="selectAllInputText(this)" readonly/>'
                        + '<div class="infowindow-title">Description:</div>'
                        + '<textarea class="infowindow-text-area"  rows="3" readonly>' + b.description + '</textarea>'
                        + '</div>';


                    marker.infoContent = htmlContent;
                    marker.building = b;
                    $scope.myBuildingsHashT[b.buid] = {
                        marker: marker,
                        model: b
                    };
                    google.maps.event.addListener(marker, 'click', function () {
                        infowindow.setContent(this.infoContent);
                        infowindow.open(GMapService.gmap, this);
                        var self = this;
                        $scope.$apply(function () {
                            $scope.anyService.setBuilding(self.building)
                        });
                    });
                }
                LOG.D("Loaded spaces: " + $scope.myBuildings.length)

                // using the latest building from localStorage
                if (localStoredBuildingIndex >= 0) {
                    $scope.anyService.setBuilding($scope.myBuildings[localStoredBuildingIndex]);
                } else if ($scope.myBuildings[0]) {
                    $scope.anyService.setBuilding($scope.myBuildings[0]);
                }

                // _suc('Successfully fetched buildings.');
            },
          function (resp) {
            ShowError($scope, resp, ERR_FETCH_BUILDINGS);
          }
        );
    };

    $scope.addNewBuilding = function (id) {
        if ($scope.myMarkers[id] && $scope.myMarkers[id].marker) {
            var building = $scope.myMarkers[id].model;
            building.coordinates_lat = String($scope.myMarkers[id].marker.position.lat());
            building.coordinates_lon = String($scope.myMarkers[id].marker.position.lng());
            if (building.coordinates_lat === undefined || building.coordinates_lat === null) {
                _err($scope, "Invalid building latitude.");
                return;
            }
            if (building.coordinates_lon === undefined || building.coordinates_lon === null) {
                _err($scope, "Invalid building longitude.");
                return;
            }
            if (building.is_published === true) {
                building.is_published = "true";
            } else {
                building.is_published = "false";
            }
            if (!building.description) {
                building.description = "-"; // puts an empty description. mongodb will ignore it
            }
            if (building.name && building.description && building.is_published && building.url && building.address && building.space_type) {
                var promise = $scope.anyAPI.addBuilding(building);
                promise.then(
                    function (resp) {  // on success
                        var data = resp.data;
                        building.buid = data.buid;

                        if (building.is_published === 'true' || building.is_published === true) {
                            building.is_published = true;
                        } else {
                            building.is_published = false;
                        }

                        // insert the newly created building inside the loadedBuildings
                        $scope.myBuildings.push(building);
                        $scope.anyService.setBuilding($scope.myBuildings[$scope.myBuildings.length - 1]);

                        $scope.myMarkers[id].marker.setDraggable(false);
                        if (building.space_type === "vessel") {
                            var icon_vessel= {
                                url: IMG_VESSEL_ARCHITECT,
                                scaledSize: new google.maps.Size(50, 50), // scaled size
                                origin: new google.maps.Point(0,0), // origin
                                anchor: new google.maps.Point(0, 0) // anchor
                            };
                            $scope.myMarkers[id].marker.icon = icon_vessel;
                        }

                        $scope.myBuildingsHashT[building.buid] = {
                            marker: $scope.myMarkers[id].marker,
                            model: building
                        };

                        if ($scope.myMarkers[id].infowindow) {
                            $scope.myMarkers[id].infowindow.setContent($scope.myMarkers[id].marker.tpl2[0]);
                            $scope.myMarkers[id].infowindow.close();
                        }

                        _info_autohide($scope, "Added " + building.space_type);
                    },
                    function (resp) {
                      ShowError($scope, resp);
                    }
                );
            } else {
                _err($scope, "Some required fields are missing.");
            }
        }
    };

    $scope.deleteBuilding = function () {
        var b = $scope.anyService.getBuilding();
        var reqObj = $scope.creds;
        reqObj.buid = b.buid;
        var promise = $scope.anyAPI.deleteBuilding(reqObj);
        promise.then(
            function (resp) { // on success
                var data = resp.data;
                // BUG does not disappear. They must be keeping references to the space in multiple places..
                if($scope.myBuildingsHashT[b.buid].marker) {
                    $scope.myBuildingsHashT[b.buid].marker.setMap(null);
                    delete $scope.myBuildingsHashT[b.buid].marker;
                }

                delete $scope.myBuildingsHashT[b.buid];
                var bs = $scope.myBuildings;
                var sz = bs.length;
                for (var i = 0; i < sz; i++) {
                    if (bs[i].buid == b.buid) {
                        bs.splice(i, 1);
                        break;
                    }
                }

                // update the selected building
                if ($scope.myBuildings && $scope.myBuildings.length > 0) {  // TODO:PV fix the logic
                    // $scope.anyService.setBuilding($scope.anyService.prevBuilding);
                    $scope.anyService.selectedBuilding = undefined;
                }
                $scope.setCrudTabSelected(1);
                _info_autohide($scope, "Deleted " + b.space_type + ". Please refresh.");
            },
            function (resp) {
              ShowError($scope, resp,
                "Something's wrong. Please refresh. Info:", true)
            }
        );
    };

    $scope.deleteRadiomaps = function () {
        var jsonReq = {"buid": $scope.anyService.getBuildingId(), "floor": $scope.anyService.getFloorNumber()};
        jsonReq.username = $scope.creds.username;
        jsonReq.password = $scope.creds.password;
        var promise = $scope.anyAPI.deleteRadiomaps(jsonReq);

        promise.then(
            function (resp) {
                _suc($scope, "Deleted radiomap floor")
            },

            function (resp) {
              ShowError($scope, resp, "deleteRadiomaps: file does not exist.", true);
            }
        );
    };

    $scope.updateBuilding = function () {
        var b = $scope.anyService.getBuilding();
        if (LPUtils.isNullOrUndefined(b) || LPUtils.isNullOrUndefined(b.buid)) {
            _err($scope, "No selected building found.");
            return;
        }
        var reqObj = {};
        reqObj.buid = b.buid;
        reqObj.description = b.description;
        if (isNullOrEmpty(b.description)) {
            reqObj.description = "";
        }
        if (b.name) {
            reqObj.name = b.name;
        }
        if (b.is_published === true || b.is_published == "true") {
            reqObj.is_published = "true";
        } else {
            reqObj.is_published = "false";
        }
        reqObj.bucode = b.bucode;
        if (isNullOrEmpty(b.bucode)) {
            reqObj.bucode = "";
        }
        reqObj.space_type = b.type;
        LOG.D2(b);
        var marker = $scope.myBuildingsHashT[b.buid].marker;
        if (marker) {
            var latLng = marker.position;
            if (latLng && latLng.lat() && latLng.lng()) {
                reqObj.coordinates_lat = String(latLng.lat());
                reqObj.coordinates_lon = String(latLng.lng());
            }
        }

        var promise = $scope.anyAPI.updateBuilding(reqObj);
        promise.then(
            function (resp) { // on success
                var data = resp.data;
                if (b.is_published === 'true' || b.is_published == true) {
                    b.is_published = true;
                } else {
                    b.is_published = false;
                }
                _suc($scope, "Successfully updated building.")
            },
            function (resp) {
              ShowError($scope, resp);
            }
        );

    };

    $scope.getUserCampuses = function () {
        var jsonReq = {};
        $scope.myCampus = [];
        var promise = $scope.anyAPI.getCampusUser(jsonReq);
        promise.then(
            function (resp) { // on success
                var data = resp.data;
                $scope.myCampus = data.buildingsets;
                var localStoredCampusIndex = -1;
                var localStoredCampusId = undefined;
                if (typeof(Storage) !== "undefined" && localStorage && localStorage.getItem('lastCampus')) {
                    localStoredCampusId = localStorage.getItem('lastCampus');
                }
                for (var i = 0; i < $scope.myCampus.length; i++) {

                    var b = $scope.myCampus[i];

                    if (localStoredCampusId && localStoredCampusId === b.cuid) {
                        localStoredCampusIndex = i;
                    }
                }
                // using the latest building set form localStorage
                if (localStoredCampusIndex >= 0) {
                    $scope.anyService.selectedCampus = $scope.myCampus[localStoredCampusIndex];
                } else if ($scope.myCampus[0]) {
                    $scope.anyService.selectedCampus = $scope.myCampus[0];
                }
            },
            function (resp) {
              ShowError($scope, resp, ERR_FETCH_BUILDINGS);
            }
        );
    };

    $scope.updateCampus = function () {
        var b = $scope.anyService.getCampus();
        if (LPUtils.isNullOrUndefined(b) || LPUtils.isNullOrUndefined(b.cuid)) {
            _err($scope, "No selected campus found.");
            return;
        }
        var reqObj = {};
        // from controlBarController
        reqObj.cuid = b.cuid;
        reqObj.description = b.description;
        if (isNullOrEmpty(b.description)) {
            reqObj.description = "";
        }
        reqObj.name = b.name;
        if (isNullOrEmpty(b.name)) {
            reqObj.name = "";
        }
        if (b.newcuid) {
            reqObj.newcuid = b.newcuid;
        }
        var sz = $scope.example9modeledit.length;
        if (sz == 0) {
            _err($scope, "No buildings selected.");
            return;
        }
        var buids = [];
        for (var i = sz - 1; i > 0; i--) {
            buids[i] = ($scope.example9modeledit[i].id);
        }
        buids[0] = ($scope.example9modeledit[0].id);
        LOG.D2(buids);
        reqObj.greeklish = document.getElementById("Greeklish-OnOffedit").checked;
        reqObj.buids = buids;
        var promise = $scope.anyAPI.updateCampus(reqObj);
        promise.then(
            function (resp) {
                // on success
                var data = resp.data;
                document.getElementById("CampusIDeditnew").value = "";
                _suc($scope, "Successfully updated campus.")
            },
            function (resp) {
              ShowError($scope, resp);
            }
        );

    };

    $scope.deleteCampus = function () {
        var b = $scope.anyService.getCampus();
        if (!b || !b.cuid) {
            _err($scope, "No Campus selected for deletion.");
            return;
        }
        var reqObj = {};
        reqObj.cuid = b.cuid;
        var promise = $scope.anyAPI.deleteCampus(reqObj);
        promise.then(
            function (resp) { // on success
                var data = resp.data;
                var bs = $scope.myCampus;
                var sz = bs.length;
                for (var i = 0; i < sz; i++) {
                    if (bs[i].cuid == b.cuid) {
                        bs.splice(i, 1);
                        break;
                    }
                }
                // update the selected building
                if ($scope.myCampus && $scope.myCampus.length > 0) {
                    $scope.anyService.selectedCampus = $scope.myCampus[0];
                }
                else if ($scope.myCampus.length == 0) {
                    $scope.anyService.selectedCampus = undefined;
                }
                $scope.setCrudTabSelected(1);
                _suc($scope, "Successfully deleted campus.");
            },
            function (resp) {
              ShowError($scope, resp,
                "Something went wrong. It's likely that everything related to " +
                "the campus is deleted but please refresh to make sure or try again.", true)
            }
        );
    };

    $scope.addCampus = function () {
        var name_element = document.getElementById("CampusName");
        var name = "\"name\":\"" + name_element.value + "\"";
        if (document.getElementById("CampusDescription").value.localeCompare("") == 0) {
            document.getElementById("CampusDescription").value = "-";
        }
        var des = document.getElementById("CampusDescription");
        var des = "\"description\":\"" + des.value + "\"";
        var mycuid = document.getElementById("CampusID");
        var mycuid = "\"cuid\":\"" + mycuid.value + "\"";
        var greeklish = document.getElementById("Greeklish-OnOff").checked;
        greeklish = "\"greeklish\":\"" + greeklish + "\"";
        var sz = $scope.example9model.length;
        if (sz == 0) {
            _err($scope, "No buildings selected.");
            return;
        }
        var buids = "\"buids\":[";
        for (var i = sz - 1; i > 0; i--) {
            buids = buids + "\"" + $scope.example9model[i].id + "\",";
        }
        buids = buids + "\"" + $scope.example9model[0].id + "\"]";
        var jreq = "{" + greeklish + "," + buids + "," + mycuid + "," + des + "," + name
            + ",\"owner_id\":\"" + $scope.owner_id +
            "\",\"access_token\":\"" + $scope.user.access_token + "\"}";
        //alert(document.getElementById("Greeklish-OnOff").checked);
        var promise = $scope.anyAPI.addBuildingSet(jreq);
        promise.then(
            function (resp) {
                // on success
                var data = resp.data;
                var new_campus = {};
                new_campus.name = document.getElementById("CampusName").value;
                new_campus.buids = buids.buids;
                new_campus.description = document.getElementById("CampusDescription").value;
                new_campus.cuid = data.cuid;
                $scope.myCampus.push(new_campus);
                $scope.anyService.selectedCampus = $scope.myCampus[$scope.myCampus.length - 1];
                _suc($scope, "Successfully added campus.");

                function S4() {
                    return (((1 + Math.random()) * 0x10000) | 0).toString(16).substring(1);
                }

                var guid = (S4() + S4() + "-" + S4() + "-4" + S4().substr(0, 3) + "-" + S4() + "-" + S4() + S4() + S4()).toLowerCase();
                var d = new Date();
                document.getElementById("CampusID").value = "cuid_" + guid + "_" + d.getTime();
            },
            function (resp) {
              ShowError($scope, resp);
            }
        );

    };

    var overlay = new google.maps.OverlayView();
    overlay.draw = function () { };
    overlay.setMap(GMapService.gmap);


    $("#draggable-building").draggable({
        helper: 'clone',
        create: function(event, ui) {
            // Resize as image is larger than the html element
            $(this).height(50).width(50);
        },
        stop: function (e) {
            var point = new google.maps.Point(e.pageX, e.pageY);
            var ll = overlay.getProjection().fromContainerPixelToLatLng(point);
            $scope.placeMarker(ll);
        }
    });

    $scope.placeMarker = function (location) {
        var prevMarker = $scope.myMarkers[$scope.myMarkerId - 1];

        if (prevMarker && prevMarker.marker && prevMarker.marker.getMap() && prevMarker.marker.getDraggable()) {
            // TODO: alert for already pending building.
            _warn_autohide($scope, 'Finish adding the previous building..');
            LOG.D('there is a building pending, please add 1 at a time');
            return;
        }

         // resize building (after it is placed on the map)
        var icon_building = {
            url: IMG_BUILDING_ARCHITECT,
            scaledSize: new google.maps.Size(50, 50), // scaled size
            origin: new google.maps.Point(0,0), // origin
            anchor: new google.maps.Point(0, 0) // anchor
        };

        var marker = new google.maps.Marker({
            position: location,
            map: GMapService.gmap,
            icon: icon_building, // assuming a building
            draggable: true
        });

        var infowindow = new google.maps.InfoWindow({
            content: '-',
            maxWidth: 500
        });

        $scope.$apply(function () {
            marker.myId = $scope.myMarkerId;
            $scope.myMarkers[marker.myId] = {};
            $scope.myMarkers[marker.myId].model = {
                description: "",
                name: undefined,
                is_published: true,
                address: "-",
                url: "-",
                bucode: "",
                type: undefined
            };

            $scope.myMarkers[marker.myId].marker = marker;
            $scope.myMarkers[marker.myId].infowindow = infowindow;
            $scope.myMarkerId++;
        });

        var htmlContent = '<form name="buildingForm" class="infowindow-scroll-fix">'
            + '<fieldset class="form-group">'
            + '<input ng-model="myMarkers[' + marker.myId + '].model.bucode" id="building-code" type="text" class="form-control" placeholder="Space Code (Optional)"/>'
            + '</fieldset>'
            + '<fieldset class="form-group">'
            + '<input ng-model="myMarkers[' + marker.myId + '].model.name" id="building-name" type="text" class="form-control" placeholder="Space Name *"/>'
            + '</fieldset>'
            + '<fieldset class="form-group">'
            + '<textarea ng-model="myMarkers[' + marker.myId + '].model.description" id="building-description" type="text" class="form-control" placeholder="Space Description (Optional)"></textarea>'
            + '</fieldset>'
            + '<fieldset class="form-group">'
            + '<select ng-model="myMarkers[' + marker.myId + '].model.space_type" class="form-control" ng-options="type for type in spaceTypes" title="Space Types" tabindex="2">'
            + '<option value="">Space Type</option>'
            + '</select>'
            + '</fieldset class="form-group">'
            + '<fieldset class="form-group">'
            + '<input ng-model="myMarkers[' + marker.myId + '].model.is_published" id="building-published" type="checkbox"><span> Make space public to view.</span>'
            + '</fieldset>'
            + '<fieldset class="form-group">'
            + '</fieldset class="form-group">'
            + '<div style="text-align: center;">'
            + '<fieldset class="form-group" style="display: inline-block; width: 75%;">'
            + '<button type="submit" class="btn btn-success add-any-button" ng-click="addNewBuilding(' + marker.myId + ')">'
            + '<span class="glyphicon glyphicon-plus"></span> Add'
            + '</button>'
            + '</fieldset>'
            + '<fieldset class="form-group" style="display: inline-block;width: 23%;">'
            + '<button class="btn btn-danger add-any-button" style="margin-left:2px" ng-click="deleteTempBuilding(' + marker.myId + ')"><span class="glyphicon glyphicon-remove"></span>'
            + '</button>'
            + '</fieldset>'
            + '</div>'
            + '</form>';

        var htmlContent2 = '<div class="infowindow-scroll-fix">'
            + '<h5 style="margin: 0">Space:</h5>'
            + '<span>{{myMarkers[' + marker.myId + '].model.name}}</span>'
            + '<h5 style="margin: 8px 0 0 0">Description:</h5>'
            + '<span>{{myMarkers[' + marker.myId + '].model.description}}</span>'
            + '</div>';

        var tpl = $compile(htmlContent)($scope);
        marker.tpl2 = $compile(htmlContent2)($scope);

        infowindow.setContent(tpl[0]);
        infowindow.open(GMapService.gmap, marker);

        google.maps.event.addListener(marker, 'click', function () {
            if (!infowindow.getMap()) {
                infowindow.open(GMapService.gmap, marker);
            }
        });
    };

    $scope.deleteTempBuilding = function (id) {
        var myMarker = $scope.myMarkers[id];
        if (myMarker && myMarker.marker) {
            myMarker.marker.setMap(null);
        }
    };

    /**
     * building {
     *  name:
     *  description:
     *  coordinates_lat:
     *  coordinates_lon:
     *  floors: [
     *      0: {
     *          pois: [
     *              name:
     *              description:
     *              pois_type:
     *              is_building_entrance:
     *              coordinates_lat:
     *              coordinates_lon:
     *          ]
     *      }
     *  ];
     * }
     */
    $scope.exportBuildingToJson = function () {
        var result = {
            building: {
                floors: []
            }
        };

        var building = $scope.anyService.selectedBuilding;
        if (LPUtils.isNullOrUndefined(building)) {
            _err($scope, 'No building selected');
            return;
        }
        result.building.buid = building.buid;
        result.building.name = building.name;
        result.building.description = building.description;
        result.building.coordinates_lat = building.coordinates_lat;
        result.building.coordinates_lon = building.coordinates_lon;

        var jsonReq = AnyplaceService.jsonReq;
        jsonReq.buid = building.buid;

        var count = 0;

        var promise = AnyplaceAPIService.allBuildingFloors(jsonReq);
        promise.then(
            function (resp) {
                var floors = resp.data.floors;

                var resFloors = [];

                if (floors) {
                    for (var i = 0; i < floors.length; i++) {

                        (function (jreq) {
                            var promise = AnyplaceAPIService.retrievePoisByBuildingFloor(jreq);
                            promise.then(
                                function (resp) {
                                    var data = resp.data;

                                    var poisArray = data.pois;

                                    if (poisArray) {

                                        var flPois = [];

                                        var fNo = poisArray[0].floor_number;

                                        for (var j = 0; j < poisArray.length; j++) {
                                            var sPoi = poisArray[j];

                                            if (sPoi.pois_type == "None") {
                                                continue;
                                            }
                                            if (sPoi.overwrite) {
                                                var tmp = {
                                                    name: sPoi.name,
                                                    description: sPoi.description,
                                                    puid: sPoi.puid,
                                                    pois_type: sPoi.pois_type,
                                                    coordinates_lat: sPoi.coordinates_lat,
                                                    coordinates_lon: sPoi.coordinates_lon,
                                                    overwrite: sPoi.overwrite
                                                };
                                            }
                                            else {
                                                var tmp = {
                                                    name: sPoi.name,
                                                    description: sPoi.description,
                                                    puid: sPoi.puid,
                                                    pois_type: sPoi.pois_type,
                                                    coordinates_lat: sPoi.coordinates_lat,
                                                    coordinates_lon: sPoi.coordinates_lon,
                                                    overwrite: "false"
                                                };
                                            }
                                            flPois.push(tmp);
                                        }

                                        resFloors.push(
                                            {
                                                floor_number: fNo,
                                                pois: flPois
                                            }
                                        );

                                        count++;
                                        if (count === floors.length) {
                                            result.building.floors = resFloors;
                                            _suc($scope, 'Successfully exported ' + building.name + ' to JSON.');
                                            var blob = new Blob([JSON.stringify(result, null, 4)], {type: "text/plain;charset=utf-8"});
                                            saveAs(blob, building.name.toLowerCase().replace(/[^a-zA-Z0-9]+/g, "-") + ".txt");
                                        }

                                    }
                                },
                                function (resp) {
                                    var data = resp.data;
                                    console.log(data.message);
                                });
                        }({
                            buid: building.buid,
                            floor_number: floors[i].floor_number
                        }));
                    }
                }
            },
            function (resp) {
                // TODO: alert failure
                console.log(resp.data.message);
            }
        );
    };

    /**
     * campus {
   "buids": [
   ],
   "description": "",
   "name": "",
   "owner_id": "",
   "access_token": "",
   "cuid": ""
    }
     * }
     */
    $scope.exportCampusToJson = function () {
        var result = {
            campus: {
                buids: []
            }
        };

        var campus = $scope.anyService.selectedCampus;
        if (LPUtils.isNullOrUndefined(campus)) {
            _err('No campus selected');
            return;
        }

        result.campus.name = campus.name;
        result.campus.description = campus.description;
        result.campus.buids = campus.buids;

        _suc($scope, 'Successfully exported ' + campus.name + ' to JSON.');

        var blob = new Blob([JSON.stringify(result, null, 4)], {type: "text/plain;charset=utf-8"});
        saveAs(blob, campus.name.toLowerCase().replace(/[^a-zA-Z0-9]+/g, "-") + ".txt");
    };

    function readSingleFile(e) {
        var file = e.target.files[0];
        if (!file) {
            return;
        }
        var reader = new FileReader();
        reader.onload = function (e) {
            var contents = e.target.result;
            $scope.fileToUpload = contents;
        };
        reader.readAsText(file);
    }

    document.getElementById('file-input')
        .addEventListener('change', readSingleFile, false);

    $scope.anyService.downloadlogfile = false;

    $scope.importBuildingFromJson = function () {

        $scope.anyService.progress = 0;
        var i, j, count = 0, countok = 0;
        if ($scope.fileToUpload == "") {
            _err($scope, "Something went wrong no file selected");
        }
        var obj = JSON.parse($scope.fileToUpload);
        for (i = 0; i < obj.building.floors.length; i++) {
            for (j = 0; j < obj.building.floors[i].pois.length; j++) {
                if (obj.building.floors[i].pois[j].overwrite == "true") {
                    count++;
                }
            }
        }
        if (count == 0) {
            _err($scope, "Something went wrong no pois to update");
        }

        for (i = 0; i < obj.building.floors.length; i++) {
            for (j = 0; j < obj.building.floors[i].pois.length; j++) {
                if (obj.building.floors[i].pois[j].overwrite == "true") {
                    countok++;
                    $scope.updatePoifromFile(obj.building.floors[i].pois[j].puid,
                        obj.building.floors[i].pois[j].coordinates_lat,
                        obj.building.floors[i].pois[j].coordinates_lon,
                        obj.building.floors[i].pois[j].name,
                        obj.building.floors[i].pois[j].description,
                        obj.building.floors[i].pois[j].pois_type,
                        obj.building.floors[i].pois[j].overwrite,
                        obj.building.buid, i, j, count, countok,
                        obj.building.name
                    );
                }
            }
        }
    }

    $scope.allpois = {};
    $scope.pois = {};

    $scope.importBuildingFromExcel = function (oEvent) {
        $scope.anyService.progress = 0;
        // Get The File From The Input
        var oFile = document.getElementById('my_file_input').files[0];
        $scope.fileToUpload = oFile.name;
        // Create A File Reader HTML5
        var reader = new FileReader();
        // Ready The Event For When A File Gets Selected
        reader.onload = function (e) {
            var data = e.target.result;
            var cfb = XLS.CFB.read(data, {type: 'binary'});
            var wb = XLS.parse_xlscfb(cfb);
            // Loop Over Each Sheet
            wb.SheetNames.forEach(function (sheetName) {
                // Obtain The Current Row As CSV
                var oJS = XLS.utils.sheet_to_row_object_array(wb.Sheets[sheetName]);
                var last_buid = "";
                $scope.uploadloop(0, oJS, last_buid);
            });
        };

        // Tell JS To Start Reading The File.. You could delay this if desired
        reader.readAsBinaryString(oFile);
    }

    $scope.uploadloop = function (potition, oJS, last_buid) {

        for (var i = potition; i < oJS.length; i++) {
            if (last_buid != oJS[i].buid && oJS[i].buid != undefined) {
                $scope.pois = {};
                last_buid = oJS[i].buid;
                $scope.fetchAllPoisForBuilding(oJS[i].buid, oJS, i, last_buid);
                return;
            }
            var description = "";

            if (oJS[i].des3 != undefined && oJS[i].des3 != "" && oJS[i].des3 != null) {
                if (oJS[i].des4 != undefined && oJS[i].des4 != "" && oJS[i].des4 != null) {
                    description = description + oJS[i].des3 + " " + oJS[i].des4;
                }
                else {
                    description = description + oJS[i].des3;
                }
            }
            else {
                if (oJS[i].des4 != undefined && oJS[i].des4 != "" && oJS[i].des4 != null) {
                    description = description + oJS[i].des4;
                }
            }

            if (oJS[i].des1 != undefined && oJS[i].des1 != "" && oJS[i].des1 != null) {
                if (description != "") {
                    description = description + "\n" + oJS[i].des1;
                }
                else {
                    description = description + oJS[i].des1;
                }
            }

            if (oJS[i].des2 != undefined && oJS[i].des2 != "" && oJS[i].des2 != null) {
                if (description != "") {
                    description = description + "\n" + oJS[i].des2;
                }
                else {
                    description = description + oJS[i].des2;
                }
            }

            $scope.anyService.progress = (i / (oJS.length - 1)) * 100;
            if ((oJS.length - 1) == 0) $scope.anyService.progress = 100;

            if ($scope.pois[oJS[i].name]) {
                $scope.updatePoifromExcel($scope.pois[oJS[i].name].puid,
                    $scope.pois[oJS[i].name].coordinates_lat,
                    $scope.pois[oJS[i].name].coordinates_lon,
                    $scope.pois[oJS[i].name].is_building_entrance,
                    oJS[i].name,
                    description,
                    $scope.pois[oJS[i].name].pois_type,
                    $scope.pois[oJS[i].name].overwrite,
                    $scope.pois[oJS[i].name].buid,
                    ""
                );
            }
            else {
                $scope.updatePoifromExcel("",
                    "",
                    "",
                    "",
                    oJS[i].name,
                    description,
                    "",
                    "",
                    "",
                    ""
                );
            }

        }
    };

    $scope.fetchAllPoisForBuilding = function (building, oJS, position, last_buid) {
        var jsonReq = AnyplaceService.jsonReq;
        jsonReq.buid = building;

        var promise = AnyplaceAPIService.retrievePoisByBuilding(jsonReq);
        promise.then(
            function (resp) {
                var data = resp.data;

                $scope.myPois = data.pois;

                var sz = $scope.myPois.length;
                for (var i = sz - 1; i >= 0; i--) {
                    var name = $scope.myPois[i].name;
                    $scope.pois[name] = $scope.myPois[i];
                }
                $scope.uploadloop(position, oJS, last_buid);
            },
            function (resp) {
              ShowError($scope, resp);
            }
        );
    };
    $scope.logfile = {
        pois: []
    };
    $scope.updatePoifromExcel = function (id, lat, lng, building_entrance, nm, des, ptype, ovwrite, bid, buildingname) {
        var obj = {};
        obj.coordinates_lat = lat;
        obj.coordinates_lon = lng;
        obj.is_building_entrance = building_entrance;
        obj.name = nm;
        obj.puid = id;
        obj.description = des;
        obj.pois_type = ptype;
        obj.overwrite = "false";
        obj.buid = bid;
        // make the request at AnyplaceAPI
        var promise = $scope.anyAPI.updatePois(obj);
        promise.then(
            function (resp) {
                var data = resp.data;
                if ($scope.anyService.progress == 100) {
                    if ($scope.anyService.downloadlogfile) {
                        $scope.anyService.downloadlogfile = false;
                        _suc($scope, "Successfully updated POIs.A log file will be downloaded");
                        var blob = new Blob([JSON.stringify($scope.logfile, null, 4)], {type: "text/plain;charset=utf-8"});
                        saveAs(blob, ($scope.fileToUpload + "-log_file").toLowerCase().replace(/[^a-zA-Z0-9]+/g, "-") + ".txt");
                        setTimeout(function () {
                            $scope.anyService.progress = undefined;
                        }, 2500);
                    }
                    else {
                        _suc($scope, "Successfully updated POIs.");
                        setTimeout(function () {
                            $scope.anyService.progress = undefined;
                            location.reload();
                        }, 2500);
                    }
                }
            },
            function (resp) {
                var data = resp.data;
                $scope.logfile.pois.push({
                    "name": nm,
                    "puid": id,
                    "description": des,
                    "status": "Something went wrong while updating POI."
                });
                $scope.anyService.downloadlogfile = true;
                if ($scope.anyService.progress == 100) {
                    $scope.anyService.downloadlogfile = false;
                    _suc($scope, "Successfully updated POIs.A log file will be downloaded");
                    var blob = new Blob([JSON.stringify($scope.logfile, null, 4)], {type: "text/plain;charset=utf-8"});
                    saveAs(blob, ($scope.fileToUpload + "-log_file").toLowerCase().replace(/[^a-zA-Z0-9]+/g, "-") + ".txt");
                    $scope.logfile.pois = [];

                    setTimeout(function () {
                        $scope.anyService.progress = undefined;
                    }, 2500);
                }
            }
        );
    };


    $scope.updatePoifromFile = function (id, lat, lng, nm, des, ptype, ovwrite, bid, i, j, count, countok, buildingname) {
        var obj = {};
        obj.coordinates_lat = lat;
        obj.coordinates_lon = lng;
        obj.name = nm;
        obj.puid = id;
        obj.description = des;
        obj.pois_type = ptype;
        obj.overwrite = "false";
        obj.buid = bid;
        // make the request at AnyplaceAPI
        var promise = $scope.anyAPI.updatePois(obj);
        promise.then(
            function (resp) {
                var data = resp.data;
                $scope.anyService.progress = countok / count * 100;
                if ($scope.anyService.progress == 100) {
                    if ($scope.anyService.downloadlogfile) {
                        _suc($scope, "Successfully updated POIs.A log file will be downloaded");
                        var blob = new Blob([JSON.stringify($scope.logfile, null, 4)], {type: "text/plain;charset=utf-8"});
                        saveAs(blob, (buildingname + "-log_file").toLowerCase().replace(/[^a-zA-Z0-9]+/g, "-") + ".txt");
                        setTimeout(function () {
                            $scope.anyService.progress = undefined;
                        }, 2500);
                    }
                    else {
                        _suc($scope, "Successfully updated POIs.");
                        setTimeout(function () {
                            $scope.anyService.progress = undefined;
                            location.reload();
                        }, 2500);
                    }
                }
            },
            function (resp) {
                var data = resp.data;

                $scope.logfile.pois.push({
                    "name": nm,
                    "puid": id,
                    "description": des,
                    "status": "Something went wrong while updating POI."
                });

                $scope.anyService.downloadlogfile = true;
                $scope.anyService.progress = countok / count * 100;
                if ($scope.anyService.progress == 100) {

                    if ($scope.anyService.downloadlogfile) {
                        _suc($scope, "Successfully updated POIs.A log file will be downloaded");
                        var blob = new Blob([JSON.stringify($scope.logfile, null, 4)], {type: "text/plain;charset=utf-8"});
                        saveAs(blob, (buildingname + "-log_file").toLowerCase().replace(/[^a-zA-Z0-9]+/g, "-") + ".txt");
                        $scope.logfile.pois = [];
                        setTimeout(function () {
                            $scope.anyService.progress = undefined;
                        }, 2500);
                    }
                    else {
                        _suc($scope, "Successfully updated POIs.");
                        setTimeout(function () {
                            $scope.anyService.progress = undefined;
                            location.reload();
                        }, 2500);
                    }
                }
            }
        );
    };

    $scope.Poisresult = {
        building: {
            floors: []
        }
    };

    $scope.Connectionsresult = {
        building: {}
    };

    $scope.zip = new JSZip();
    $scope.DownloadBackup = function () {
        LOG.D3("DownloadBackup")
        var b = $scope.anyService.selectedBuilding;
        var xFloors = [];
        var jsonReq = AnyplaceService.jsonReq;
        jsonReq.buid = b.buid;
        $scope.anyService.progress = 0;
        var promise = AnyplaceAPIService.allBuildingFloors(jsonReq);
        promise.then(
            function (resp) { // success
                _info_autohide_timeout($scope, "Fetched floors..", 1500)
                xFloors = resp.data.floors;
                var floor = 0;
                var floorNumbers = "";
                for (var i = 0; i < xFloors.length; i++) {
                    if (i == 0) {
                        floorNumbers = xFloors[i].floor_number;
                    }
                    else {
                        floorNumbers = floorNumbers + " " + xFloors[i].floor_number;
                    }
                }
                $scope.anyService.progress = 10;
                var buid = b.buid;
                var jsonReq2 = AnyplaceService.jsonReq;
                var promise2 = AnyplaceAPIService.downloadFloorPlanAll(jsonReq2, buid, floorNumbers);
                promise2.then(
                    function (resp) { // on success
                        _info_autohide_timeout($scope, "Fetched floorplans..", 1500)
                        var data = resp.data;
                        var img = $scope.zip.folder("floor_plans");
                        for (var si = 0; si < data.all_floors.length; si++) {
                            if (data.all_floors[si] != "") {
                                img.file(xFloors[si].floor_number + ".png", data.all_floors[si], {base64: true});
                            }
                        }
                        $scope.anyService.progress = 25;
                        var jsonReq3 = AnyplaceService.jsonReq;
                        jsonReq3.buid = buid;
                        jsonReq3.floors = floorNumbers;
                        var promise3 = AnyplaceAPIService.getRadioByBuildingFloorAll(jsonReq3);
                        promise3.then(function (resp) {
                                _info_autohide_timeout($scope, "Fetched radiomaps..", 1500)
                                var data2 = resp.data;
                                var logs = $scope.zip.folder("radiomaps");
                                if (data2.rss_log_files) {
                                    for (var si2 = 0; si2 < data2.rss_log_files.length; si2++) {
                                        logs.file(xFloors[si2].floor_number + "-radiomap.txt", data2.rss_log_files[si2]);
                                    }
                                }
                                $scope.anyService.progress = 70;
                                $scope.exportPoisBuildingToJson();
                            }, function (resp) {
                                ShowError($scope, resp, ERR_FETCH_ALL_RADIOMAPS, true);
                            });
                    },
                    function (resp) {
                	ShowError($scope, resp, ERR_FETCH_ALL_FLOORPLANS, true);
                    }
                );
            },
            function (resp) {
              ShowError($scope, resp, ERR_FETCH_ALL_FLOORS, true);
            }
        );
    }

    $scope.exportPoisBuildingToJson = function () {

        var building = $scope.anyService.selectedBuilding;
        if (LPUtils.isNullOrUndefined(building)) {
            _err($scope, 'No building selected');
            return;
        }
        $scope.Poisresult.building.buid = building.buid;
        $scope.Poisresult.building.name = building.name;
        $scope.Poisresult.building.description = building.description;
        $scope.Poisresult.building.coordinates_lat = building.coordinates_lat;
        $scope.Poisresult.building.coordinates_lon = building.coordinates_lon;

        var jsonReq = AnyplaceService.jsonReq;
        jsonReq.buid = building.buid;

        var count = 0;

        var promise = AnyplaceAPIService.allBuildingFloors(jsonReq);
        promise.then(
            function (resp) {
                var floors = resp.data.floors;

                var resFloors = [];
                $scope.anyService.progress = 80;
                if (floors) {
                    for (var i = 0; i < floors.length; i++) {
                        // Record EVERY floor (even one with zero POIs) so the
                        // backup carries its name/description/zoom and coordinate
                        // bounds; otherwise a POI-free floor (e.g. "Floor 2")
                        // would be omitted and its floorplan could not be
                        // repositioned when the space is restored.
                        (function (fl) {
                            var flEntry = {
                                floor_number: fl.floor_number,
                                pois: [],
                                floor_name: fl.floor_name,
                                description: fl.description,
                                bottom_left_lat: fl.bottom_left_lat,
                                bottom_left_lng: fl.bottom_left_lng,
                                top_right_lat: fl.top_right_lat,
                                top_right_lng: fl.top_right_lng,
                                zoom: fl.zoom
                            };
                            resFloors.push(flEntry);
                            var promise = AnyplaceAPIService.retrievePoisByBuildingFloor({
                                buid: building.buid,
                                floor_number: fl.floor_number
                            });
                            promise.then(
                                function (resp) {
                                    var data = resp.data;
                                    var poisArray = data.pois;
                                    if (poisArray && poisArray.length > 0) {
                                        for (var j = 0; j < poisArray.length; j++) {
                                            var sPoi = poisArray[j];

                                            // NOTE: do NOT skip pois_type=="None" here.  This
                                            // backup is used to restore a space, and connector
                                            // POIs (pois_type None) are the endpoints of the
                                            // connection graph.  If they are omitted, the
                                            // connection restore cannot resurrect the space.
                                            if (sPoi.overwrite) {
                                                var tmp = {
                                                    name: sPoi.name,
                                                    description: sPoi.description,
                                                    puid: sPoi.puid,
                                                    pois_type: sPoi.pois_type,
                                                    coordinates_lat: sPoi.coordinates_lat,
                                                    coordinates_lon: sPoi.coordinates_lon,
                                                    overwrite: sPoi.overwrite
                                                };
                                            } else {
                                                var tmp = {
                                                    name: sPoi.name,
                                                    description: sPoi.description,
                                                    puid: sPoi.puid,
                                                    pois_type: sPoi.pois_type,
                                                    coordinates_lat: sPoi.coordinates_lat,
                                                    coordinates_lon: sPoi.coordinates_lon,
                                                    overwrite: "false"
                                                };
                                            }

                                            if (sPoi.is_building_entrance == 'true') {
                                                tmp.is_building_entrance = 'true';
                                            } else {
                                                tmp.is_building_entrance = 'false';
                                            }
                                            flEntry.pois.push(tmp);
                                        }
                                    }
                                },
                                function (resp) {
                                    var data = resp.data;
                                    LOG.E(data.message);
                                }).finally(function () {
                                    count++;
                                    if (count === floors.length) {
                                        $scope.Poisresult.building.floors = resFloors;
                                        $scope.zip.file("allpois.json", JSON.stringify($scope.Poisresult, null, 4));
                                        $scope.anyService.progress = 90;
                                        $scope.exportConnectionBuildingToJson();
                                    }
                                });
                        })(floors[i]);
                    }
                }
            },
            function (resp) {
                LOG.E(resp.data.message);  // TODO: alert failure
            }
        );
    };

    $scope.exportConnectionBuildingToJson = function () {
        var building = $scope.anyService.selectedBuilding;
        if (LPUtils.isNullOrUndefined(building)) {
            _err('No building selected');
            return;
        }
        $scope.Connectionsresult.building.buid = building.buid;
        $scope.Connectionsresult.building.name = building.name;
        $scope.Connectionsresult.building.description = building.description;
        $scope.Connectionsresult.building.coordinates_lat = building.coordinates_lat;
        $scope.Connectionsresult.building.coordinates_lon = building.coordinates_lon;

        var jsonReq = AnyplaceService.jsonReq;
        jsonReq.buid = building.buid;
        AnyplaceAPIService.allBuildingFloors(jsonReq).then(
            function (resp) {
                var floors = resp.data.floors;
                var resFloors = [];
                var floorEntry = {};

                if (floors) {
                    for (var i = 0; i < floors.length; i++) {
                        // Record EVERY floor even if it has no connectors, so the
                        // restore knows all floors exist and downloads complete.
                        var flEntry = {
                            floor_number: floors[i].floor_number,
                            connections: []
                        };
                        resFloors.push(flEntry);
                        floorEntry[String(floors[i].floor_number)] = flEntry;
                    }
                }

                // Fetch ALL connections of the space in one call. The per-floor
                // endpoint only returns same-floor edges (floor_a==floor_b==floor)
                // and silently drops cross-floor edges (stairs/elevators), so
                // relying on it makes backups lossy. Group every edge (including
                // cross-floor ones) into the floor matching its floor_a so the
                // restore still reconstructs the full graph.
                AnyplaceAPIService.retrieveConnectionsByBuildingAllFloors({
                    buid: building.buid
                }).then(
                    function (resp) {
                        var connArray = (resp.data && resp.data.connections) || [];
                        if (connArray.length > 0) {
                            for (var j = 0; j < connArray.length; j++) {
                                var sConnection = connArray[j];
                                var tmp = {
                                    name: sConnection.name,
                                    description: sConnection.description,
                                    cuid: sConnection.cuid,
                                    weight: sConnection.weight,
                                    pois_a: sConnection.pois_a,
                                    pois_b: sConnection.pois_b,
                                    floor_a: sConnection.floor_a,
                                    floor_b: sConnection.floor_b,
                                    is_published: sConnection.is_published,
                                    buid_a: sConnection.buid_a,
                                    buid_b: sConnection.buid_b,
                                    edge_type: sConnection.edge_type || "hallway"
                                };
                                var fA = String(sConnection.floor_a);
                                var fB = String(sConnection.floor_b);
                                var target = floorEntry[fA];
                                if (!target) target = floorEntry[fB];
                                if (!target && resFloors.length > 0) target = resFloors[0];
                                if (target) target.connections.push(tmp);
                            }
                        }
                        $scope.Connectionsresult.building.floors = resFloors;
                        $scope.zip.file("allconnections.json", JSON.stringify($scope.Connectionsresult, null, 4));

                        $scope.zip.generateAsync({type: "blob"})
                            .then(function (content) {
                                // see FileSaver.js
                                saveAs(content, building.buid + ".zip");
                            });
                        $scope.anyService.progress = undefined;
                    },
                    function (resp) {
                        var data = resp.data;
                        console.log(data.message);
                        $scope.anyService.progress = undefined;
                    }
                );
            },
            function (resp) {
                LOG.E(resp.data.message);
            }
        );
    };

    // --------------------------------------------------------------------
    // Restore a space from a backup zip downloaded via DownloadBackup() above.
    // The zip (generated client-side) contains:
    //   floor_plans/<n>.png   floorplan images
    //   allpois.json          building + floors + pois
    //   allconnections.json   building + floors + connectors
    // Restore re-imports them through the same APIs used elsewhere in the UI:
    // floorplan upload (uploadFloorPlan64), POI add (addPois, puid preserved
    // so connectors link), and connection add (addConnection).
    // --------------------------------------------------------------------
    $scope.RestoreBackup = function () {
        // `b` may be null/undefined here: if no space is selected, a new space
        // is auto-created from the backup's building metadata (see below).
        var b = $scope.anyService.selectedBuilding;
        var fileInput = document.getElementById("backupRestoreFile");
        if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
            _err($scope, "Choose a backup zip file first.");
            return;
        }
        var file = fileInput.files[0];
        if (!/\.zip$/i.test(file.name)) {
            _err($scope, "Please select the <buid>.zip backup file downloaded from the Backup tab.");
            return;
        }

        var zip = new JSZip();
        _setProgress($scope, 0);
        var results = {};

        // JSZip 3.x resolves with native Promises; re-enter Angular's digest
        // stream so progress/alerts render.  App API calls are Angular $q
        // promises, so chaining from a $q root keeps everything in the digest.
        $q.when(zip.loadAsync(file)).then(function (z) {
            if (!z.file("allpois.json") || !z.file("allconnections.json")) {
                throw new Error("Not a valid space backup (missing allpois.json/allconnections.json).");
            }
            results.zip = z;
            return $q.all([
                $q.when(z.file("allpois.json").async("string")),
                $q.when(z.file("allconnections.json").async("string"))
            ]);
        }).then(function (parsed) {
            results.poisJson = JSON.parse(parsed[0]);
            results.connsJson = JSON.parse(parsed[1]);
            _setProgress($scope, 15);
            // Resolve the target space: reuse the currently selected one, or
            // auto-create a new space from the backup's building metadata when
            // none is selected.
            return _ensureRestoreTargetBuilding(results.poisJson.building);
        }).then(function (targetBuilding) {
            b = targetBuilding;
            // 1) ensure floors exist (with bounds/zoom) + upload floorplans
            return $scope._restoreFloorsAndFloorplans(b, results.zip, results.poisJson, results.connsJson);
        }).then(function (floorStats) {
            results.floorStats = floorStats;
            _setProgress($scope, 55);
            // 2) re-create all POIs (preserving puid so connectors link)
            return $scope._restorePois(b, results.poisJson);
        }).then(function (poiStats) {
            results.poiStats = poiStats;
            _setProgress($scope, 80);
            // 3) re-create the connectors between the restored POIs
            return $scope._restoreConnections(b, results.connsJson);
        }).then(function (connStats) {
            results.connStats = connStats;
            _setProgress($scope, undefined);
            var total = results.floorStats.added + results.poiStats.added + results.connStats.added;
            var allFailures = (results.floorStats.failures || [])
                .concat(results.poiStats.failures || [])
                .concat(results.connStats.failures || []);

            if (total > 0) {
                _suc($scope, "Restored " + total + " item(s): " + results.poiStats.added + " POI(s), " +
                    results.connStats.added + " connection(s), " + results.floorStats.added + " floor(s). " +
                    "Refresh the page to see the data.");
            } else {
                _warn($scope, "Restore finished but nothing was added. The backup may be empty, or this space already contains the data.");
            }

            // The per-item error tolerance means a bad floorplan/POI/connector no
            // longer aborts the whole restore.  Report every item that failed so
            // the user can see exactly what (and why) rather than a silent miss.
            if (allFailures.length > 0) {
                var shown = allFailures.slice(0, 8).join(". ");
                if (allFailures.length > 8) { shown += ". (" + (allFailures.length - 8) + " more)"; }
                _warn($scope, "Restore completed with " + allFailures.length + " item(s) not restored: " + shown + ". See the browser console for details.");
            }
            for (var fi2 = 0; fi2 < allFailures.length; fi2++) {
                LOG.E("restore: " + allFailures[fi2]);
            }
        })["catch"](function (err) {
            _setProgress($scope, undefined);
            var msg = _errorText(err);
            _err($scope, "Restore failed: " + msg);
        });
    };

    // Resolves the building to restore into.  If a space with a buid is
    // currently selected it is reused as-is; otherwise a new space is created
    // from the backup's building metadata (name + coordinates) so the restore
    // works even when the architect has no building on the map yet.
    // Returns a $q promise resolving to the target building object (with buid).
    var _ensureRestoreTargetBuilding = function (buildingMeta) {
        var selected = $scope.anyService.selectedBuilding;
        if (selected && selected.buid) {
            return $q.when(selected);
        }
        var meta = buildingMeta || {};
        var nb = {
            name: meta.name || "Restored Space",
            description: "-",
            is_published: "false",
            address: "-",
            url: "-",
            bucode: meta.buid || "",
            space_type: "building",
            coordinates_lat: String(meta.coordinates_lat),
            coordinates_lon: String(meta.coordinates_lon)
        };
        if (!nb.coordinates_lat || nb.coordinates_lat === "undefined" ||
            !nb.coordinates_lon || nb.coordinates_lon === "undefined") {
            return $q.reject(new Error("No space selected and the backup has no coordinates to create one."));
        }
        return $q.when($scope.anyAPI.addBuilding(nb)).then(function (resp) {
            var data = resp && resp.data ? resp.data : resp;
            if (!data || data.status !== "success" || !data.buid) {
                throw new Error("Failed to auto-create the space: " +
                    ((data && data.message) ? data.message : "unknown error"));
            }
            nb.buid = data.buid;
            $scope.anyService.setBuilding(nb);
            _suc($scope, "Auto-created new space '" + nb.name + "' from the backup. Restoring...");
            return nb;
        });
    };

    // Turns a thrown value / rejected promise result into a readable message.
    // Angular $http rejections are response objects (status/statusText/data);
    // JSZip and JSON.parse throw Errors with a `.message`.  Anything else is
    // reported generically instead of a useless "[object Object]".
    var _errorText = function (err) {
        var str = function (v) {
            if (LPUtils.isNullOrUndefined(v)) { return undefined; }
            var s = String(v);
            return (s.length > 0 && s !== "[object Object]") ? s : undefined;
        };
        if (err && typeof err === "object") {
            var m = str(err.message) || str(err.statusText) ||
                (err.data && str(err.data.message)) || str(err.data && err.data.status) ||
                (err.data && err.data.error) || undefined;
            if (m) { return m; }
            return "unknown error (HTTP status " + (typeof err.status !== "undefined" ? err.status : "?") + "). See the browser console for details.";
        }
        return str(err) || "unknown error";
    };

    // set progress safely (may be invoked from a native-Promise continuation).
    var _setProgress = function (scope, val) {
        if (scope.$root.$$phase) {
            scope.anyService.progress = val;
        } else {
            scope.$apply(function () { scope.anyService.progress = val; });
        }
    };

    // Fetches the building floors that carry coordinate bounds + zoom.
    $scope._loadBuildingFloors = function (b) {
        var jsonReq = AnyplaceService.jsonReq;
        jsonReq.buid = b.buid;
        return AnyplaceAPIService.allBuildingFloors(jsonReq).then(function (resp) {
            return resp.data.floors || [];
        });
    };

    // Ensures every floor referenced by the backup exists in the target (adding
    // it if missing), then uploads the accompanying floorplan image positioned
    // with the coordinate bounds + zoom captured in the backup.
    // Returns { added: <number of floors created> }.
    $scope._restoreFloorsAndFloorplans = function (b, z, poisJson, connsJson) {
        var byNo = {};
        var collectFloor = function (fl, withBounds) {
            var key = String(fl.floor_number);
            if (!byNo[key]) byNo[key] = { floor_number: String(fl.floor_number), meta: {} };
            if (withBounds) {
                byNo[key].meta.floor_name = byNo[key].meta.floor_name || fl.floor_name;
                byNo[key].meta.description = byNo[key].meta.description || fl.description;
                byNo[key].meta.bottom_left_lat = byNo[key].meta.bottom_left_lat || fl.bottom_left_lat;
                byNo[key].meta.bottom_left_lng = byNo[key].meta.bottom_left_lng || fl.bottom_left_lng;
                byNo[key].meta.top_right_lat = byNo[key].meta.top_right_lat || fl.top_right_lat;
                byNo[key].meta.top_right_lng = byNo[key].meta.top_right_lng || fl.top_right_lng;
                byNo[key].meta.zoom = byNo[key].meta.zoom || fl.zoom;
            }
        };
        (poisJson.building && poisJson.building.floors || []).forEach(function (fl) {
            collectFloor(fl, true);
        });
        (connsJson.building && connsJson.building.floors || []).forEach(function (fl) {
            collectFloor(fl, false);
        });

        return $scope._loadBuildingFloors(b).then(function (targetFloors) {
            var targetByNo = {};
            for (var i = 0; i < targetFloors.length; i++) {
                targetByNo[String(targetFloors[i].floor_number)] = targetFloors[i];
            }
            var nums = Object.keys(byNo);
            var added = 0;
            var failures = [];
            var seq = nums.map(function (no) {
                return function () {
                    var meta = byNo[no].meta || {};
                    // The target floor already exists -> we only (re)upload its
                    // floorplan image.  Failure here must NOT abort the rest of
                    // the restore (POIs + connectors), so it is caught and
                    // recorded instead of rejecting the chain.
                    if (targetByNo[String(no)]) {
                        return _restoreFloorplanSafe(b, z, no, meta, failures, targetByNo[String(no)]);
                    }
                    return $scope.anyAPI.addFloor({
                        is_published: "true",
                        buid: b.buid,
                        floor_number: String(no),
                        floor_name: meta.floor_name || (String(no) + " floor"),
                        description: meta.description || (String(no) + " floor")
                    }).then(function () {
                        added++;
                        return _restoreFloorplanSafe(b, z, no, meta, failures);
                    }, function (err) {
                        failures.push("floor " + no + " could not be created: " + _errorText(err));
                        return null;
                    });
                };
            });
            return _runSequential(seq).then(function () {
                return { added: added, failures: failures };
            });
        });
    };

    // Uploads floor_plans/<floor_number>.png for the given floor.  The
    // coordinate bounds come from the backup; if the backup lacks them (e.g.
    // the source floor was never geo-positioned), we fall back to the target
    // floor's already-stored bounds, and finally to a small box around the
    // building center so the floorplan image is still restored (best-effort
    // placement) rather than being dropped.  Never rejects the calling chain:
    // on any problem (no image, no usable bounds, upload failure) it records a
    // readable failure into `failures` and resolves with null so subsequent
    // floors, POIs and connectors are still restored.
    var _restoreFloorplanSafe = function (b, z, floor_number, meta, failures, targetFloor) {
        var imgPath = "floor_plans/" + floor_number + ".png";
        if (!z.file(imgPath)) return $q.when(null);
        var fl = meta || {};

        var isSet = function (v) {
            return !LPUtils.isNullOrUndefined(v) && !LPUtils.isStringBlankNullUndefined(String(v));
        };
        // Effective bounds: backup -> target floor's existing bounds -> building-derived default.
        var bottom_left_lat = isSet(fl.bottom_left_lat) ? fl.bottom_left_lat : undefined;
        var bottom_left_lng = isSet(fl.bottom_left_lng) ? fl.bottom_left_lng : undefined;
        var top_right_lat = isSet(fl.top_right_lat) ? fl.top_right_lat : undefined;
        var top_right_lng = isSet(fl.top_right_lng) ? fl.top_right_lng : undefined;
        var haveFullBackupBounds = isSet(bottom_left_lat) && isSet(bottom_left_lng) && isSet(top_right_lat) && isSet(top_right_lng);
        if (!haveFullBackupBounds) {
            bottom_left_lat = (targetFloor && isSet(targetFloor.bottom_left_lat)) ? targetFloor.bottom_left_lat : undefined;
            bottom_left_lng = (targetFloor && isSet(targetFloor.bottom_left_lng)) ? targetFloor.bottom_left_lng : undefined;
            top_right_lat = (targetFloor && isSet(targetFloor.top_right_lat)) ? targetFloor.top_right_lat : undefined;
            top_right_lng = (targetFloor && isSet(targetFloor.top_right_lng)) ? targetFloor.top_right_lng : undefined;
        }
        var haveFullTargetBounds = !haveFullBackupBounds && isSet(bottom_left_lat) && isSet(bottom_left_lng) && isSet(top_right_lat) && isSet(top_right_lng);
        var rawZoom = isSet(fl.zoom) ? fl.zoom : (targetFloor && isSet(targetFloor.zoom) ? targetFloor.zoom : "19");
        var zoomInt = parseInt(rawZoom, 10);
        // backend uploadWithZoom requires zoom >= MIN_ZOOM_UPLOAD (18).
        var zoom = (isNaN(zoomInt) || zoomInt < 18) ? "19" : String(zoomInt);

        var haveFullBounds = haveFullBackupBounds || haveFullTargetBounds;
        if (!haveFullBounds) {
            // Last resort: a ~350m box around the building center so the image
            // is restored even though it cannot be positioned precisely.
            var cLat = Number(b.coordinates_lat);
            var cLon = Number(b.coordinates_lon);
            if (!isNaN(cLat) && !isNaN(cLon)) {
                var dLat = 0.0025;
                var dLon = dLat / Math.max(0.01, Math.cos(cLat * Math.PI / 180));
                bottom_left_lat = String(cLat - dLat);
                bottom_left_lng = String(cLon - dLon);
                top_right_lat = String(cLat + dLat);
                top_right_lng = String(cLon + dLon);
                haveFullBounds = true;
                failures.push("floor " + floor_number + " had no coordinate bounds in the backup or target; its floorplan was placed around the building center as a best-effort and may need repositioning");
            } else {
                failures.push("floor " + floor_number + " has no coordinate bounds in the backup and no building center to fall back to; its floorplan was not restored");
                return $q.when(null);
            }
        } else if (haveFullTargetBounds) {
            failures.push("floor " + floor_number + " had no coordinate bounds in the backup; the target floor's existing bounds were used for its floorplan");
        }
        return $q.when(z.file(imgPath).async("base64")).then(function (b64) {
            var coords = {
                buid: b.buid,
                floor_number: String(floor_number),
                bottom_left_lat: String(bottom_left_lat),
                bottom_left_lng: String(bottom_left_lng),
                top_right_lat: String(top_right_lat),
                top_right_lng: String(top_right_lng),
                owner_id: $scope.owner_id,
                zoom: String(zoom)
            };
            return $scope.anyAPI.uploadFloorPlan64(JSON.stringify(coords),
                "data:image/png;base64," + b64).then(function () {
                    return true;
                }, function (err) {
                    failures.push("floor " + floor_number + " floorplan upload failed: " + _errorText(err));
                    return null;
                });
        });
    };

    // Re-creates the POIs, preserving each puid so connectors keep their links.
    // Returns { added: <number of POIs>, failures: [messages] }.  A single POI
    // that fails to insert does not stop the rest of the restore.
    $scope._restorePois = function (b, poisJson) {
        var floorList = (poisJson.building && poisJson.building.floors) || [];
        var tasks = [];
        var added = 0;
        var failures = [];
        for (var i = 0; i < floorList.length; i++) {
            var fl = floorList[i];
            var pois = fl.pois || [];
            for (var j = 0; j < pois.length; j++) {
                (function (poi, flno, flname) {
                    tasks.push(function () {
                        return $scope.anyAPI.addPois({
                            puid: poi.puid,
                            buid: b.buid,
                            floor_number: String(flno),
                            floor_name: flname || (String(flno) + " floor"),
                            name: poi.name,
                            description: poi.description || "",
                            pois_type: poi.pois_type || "POI",
                            is_published: "true",
                            is_door: "false",
                            is_building_entrance: poi.is_building_entrance ? String(poi.is_building_entrance) : "false",
                            coordinates_lat: poi.coordinates_lat,
                            coordinates_lon: poi.coordinates_lon,
                            overwrite: "true",
                            owner_id: $scope.owner_id
                        }).then(function () {
                            added++;
                        }, function (err) {
                            failures.push("POI \"" + (poi.name || "?") + "\" (" + (poi.puid || "no puid") + "): " + _errorText(err));
                            return null;
                        });
                    });
                })(pois[j], fl.floor_number, fl.floor_name);
            }
        }
        return _runSequential(tasks).then(function () {
            return { added: added, failures: failures };
        });
    };

    // Re-creates the connectors between the (restored) POIs.
    // Returns { added: <number of connections>, failures: [messages] }.
    // A connector usually fails here only if its endpoint POIs (matching puid)
    // were not restored, which we report instead of aborting the restore.
    // Re-creates the connectors between the (restored) POIs.  Before wiring,
    // every connector endpoint POI must exist in the target.  A backup made by
    // an older exporter may omit the intermediate "connector" nodes (pois_type
    // "None"), so their endpoints are missing entirely; we re-create those as
    // connector POIs (best-effort position) so the whole graph still comes
    // back instead of silently yielding zero connections.
    // Returns { added: <number of connections>, created: <connector POIs re-created>,
    //           failures: [messages] }.
    $scope._restoreConnections = function (b, connsJson) {
        var floors = (connsJson.building && connsJson.building.floors) || [];
        return _ensureConnectorPois(b, connsJson).then(function (connectorRes) {
            var tasks = [];
            var added = 0;
            var failures = connectorRes.failures;
            for (var i = 0; i < floors.length; i++) {
                var fl = floors[i];
                var conns = fl.connections || [];
                for (var j = 0; j < conns.length; j++) {
                    (function (c) {
                        tasks.push(function () {
                            return $scope.anyAPI.addConnection({
                            name: c.name,
                            description: c.description || "",
                            weight: c.weight,
                            pois_a: c.pois_a,
                            pois_b: c.pois_b,
                            floor_a: c.floor_a,
                            floor_b: c.floor_b,
                            buid: b.buid,
                            buid_a: b.buid,
                            buid_b: b.buid,
                            is_published: c.is_published ? String(c.is_published) : "true",
                            edge_type: c.edge_type || "hallway",
                            owner_id: $scope.owner_id
                        }).then(function () {
                            added++;
                        }, function (err) {
                            failures.push("connection \"" + (c.name || "?") + "\" (" + (c.pois_a || "?") + "->" + (c.pois_b || "?") + "): " + _errorText(err));
                            return null;
                        });
                    });
                    })(conns[j]);
                }
            }
            return _runSequential(tasks).then(function () {
                return { added: added, created: connectorRes.created, failures: failures };
            });
        });
    };

    // Ensures every POI endpoint referenced by the connections exists in the
    // target (matching puid), creating any that are missing as connector POIs
    // (pois_type "None").  Older backups drop these intermediate connector
    // nodes, so without this step every connection would fail because its
    // endpoint POI is absent.  Returns { created: <number>, failures: [msg] }.
    // A missing node has no backup coordinates, so its position is derived
    // from the centroid of its already-placed connection partners (this
    // propagates through connector chains over a few passes) and, failing
    // that, from a small deterministic scatter around the building center.
    // These re-created nodes may need repositioning, which the caller reports.
    var _ensureConnectorPois = function (b, connsJson) {
        var floors = (connsJson.building && connsJson.building.floors) || [];
        // 1) collect every endpoint (puid, floor) the graph needs
        var needed = [];            // {puid, floor}
        var seen = {};
        var neededByFloor = {};     // floor -> array of puids
        for (var i = 0; i < floors.length; i++) {
            var fl = floors[i];
            var conns = fl.connections || [];
            for (var j = 0; j < conns.length; j++) {
                var c = conns[j];
                _noteEndpoint(c.pois_a, c.floor_a);
                _noteEndpoint(c.pois_b, c.floor_b);
            }
        }
        function _noteEndpoint(puid, flr) {
            if (!puid) return;
            var key = String(flr) + ":" + String(puid);
            if (seen[key]) return;
            seen[key] = true;
            needed.push({ puid: puid, floor: String(flr) });
            (neededByFloor[String(flr)] = neededByFloor[String(flr)] || []).push(puid);
        }

        // 2) load POIs already in the target (so we don't duplicate)
        return $scope.anyAPI.retrievePoisByBuilding({
            buid: b.buid,
            owner_id: $scope.owner_id
        }).then(function (resp) {
            var existing = {};          // "floor:puid" -> poi
            var placed = resp.data && resp.data.pois || [];
            for (var k = 0; k < placed.length; k++) {
                var p = placed[k];
                existing[String(p.floor_number) + ":" + String(p.puid)] = p;
            }

            // 3) build an adjacency map of endpoint nodes (floor:puid) and seed
            //    "known" coordinates from POIs already placed in the target
            var adj = {};               // key -> [key, ...] same-floor neighbors
            var known = {};             // key -> {lat,lon}
            for (var p = 0; p < placed.length; p++) {
                var pp = placed[p];
                var plat = Number(pp.coordinates_lat);
                var plon = Number(pp.coordinates_lon);
                if (!isNaN(plat) && !isNaN(plon)) {
                    known[String(pp.floor_number) + ":" + String(pp.puid)] = { lat: plat, lon: plon };
                }
            }
            // seed known positions also from backup POIs (they were just restored by _restorePois)
            for (var i3 = 0; i3 < floors.length; i3++) {
                var fl3 = floors[i3];
                var bpois = fl3.pois || [];
                for (var j3 = 0; j3 < bpois.length; j3++) {
                    var bp = bpois[j3];
                    var bl = Number(bp.coordinates_lat);
                    var bn = Number(bp.coordinates_lon);
                    if (!isNaN(bl) && !isNaN(bn)) {
                        known[String(fl3.floor_number) + ":" + String(bp.puid)] = { lat: bl, lon: bn };
                    }
                }
            }
            for (var m = 0; m < floors.length; m++) {
                var flx = floors[m];
                var cns = flx.connections || [];
                for (var n = 0; n < cns.length; n++) {
                    var cc = cns[n];
                    _link(cc.pois_a, cc.floor_a, cc.pois_b, cc.floor_b);
                }
            }
            function _link(a, fa, c2, fb) {
                var aKey = String(fa) + ":" + String(a);
                var bKey = String(fb) + ":" + String(c2);
                if (String(fa) !== String(fb)) return; // only place within a floor
                if (!adj[aKey]) adj[aKey] = [];
                if (!adj[bKey]) adj[bKey] = [];
                if (adj[aKey].indexOf(bKey) === -1) adj[aKey].push(bKey);
                if (adj[bKey].indexOf(aKey) === -1) adj[bKey].push(aKey);
            }

            // 4) resolve positions iteratively: propagate centroids along chains
            //    until no new node can be placed (or a cap of passes is reached)
            var positions = {};         // key -> {lat, lon}
            var passes = 8;
            for (var pass = 0; pass < passes; pass++) {
                var changed = false;
                for (var r = 0; r < needed.length; r++) {
                    var nd = needed[r];
                    var key2 = String(nd.floor) + ":" + String(nd.puid);
                    if (known[key2] || positions[key2]) continue;
                    var nb = adj[key2] || [];
                    var acc = { lat: 0, lon: 0, count: 0 };
                    for (var q = 0; q < nb.length; q++) {
                        var nk = known[nb[q]] || positions[nb[q]];
                        if (!nk) continue;
                        acc.lat += nk.lat;
                        acc.lon += nk.lon;
                        acc.count++;
                    }
                    if (acc.count > 0) {
                        positions[key2] = { lat: acc.lat / acc.count, lon: acc.lon / acc.count };
                        changed = true;
                    }
                }
                if (!changed) break;
            }

            // 5) fallback for anything still unresolved: building center + scatter
            var cLat = Number(b.coordinates_lat);
            var cLon = Number(b.coordinates_lon);
            var hasCenter = !isNaN(cLat) && !isNaN(cLon);
            var created = 0;
            var failures = [];
            var hashOffset = function (str) {
                var h = 0;
                for (var s = 0; s < str.length; s++) {
                    h = ((h << 5) - h + str.charCodeAt(s)) | 0;
                }
                return (h >>> 0) % 1000 / 1000; // [0,1)
            };
            var tasks = needed.map(function (nd) {
                var key3 = String(nd.floor) + ":" + String(nd.puid);
                return function () {
                    if (existing[key3]) return null; // already present, nothing to do
                    var lat, lon;
                    if (positions[key3]) {
                        lat = positions[key3].lat;
                        lon = positions[key3].lon;
                    } else if (hasCenter) {
                        var r1 = hashOffset(nd.puid + "a") * 0.0015;
                        var r2 = hashOffset(nd.puid + "b") * 0.0015;
                        lat = cLat + r1;
                        lon = cLon + r2;
                        failures.push("connector POI \"" + (nd.puid || "?") + "\" had no backup position; placed near the building center (reposition if needed)");
                    } else {
                        failures.push("connector POI \"" + (nd.puid || "?") + "\" could not be placed (no position and no building center); skipped");
                        return null;
                    }
                    return $scope.anyAPI.addPois({
                        puid: nd.puid,
                        buid: b.buid,
                        floor_number: String(nd.floor),
                        floor_name: String(nd.floor) + " floor",
                        name: "connector",
                        description: "re-created connector node (was missing from the backup)",
                        pois_type: "None",
                        is_published: "true",
                        is_door: "false",
                        is_building_entrance: "false",
                        coordinates_lat: String(lat),
                        coordinates_lon: String(lon),
                        overwrite: "true",
                        owner_id: $scope.owner_id
                    }).then(function () {
                        created++;
                    }, function (err) {
                        failures.push("connector POI \"" + (nd.puid || "?") + "\" not created: " + _errorText(err));
                        return null;
                    });
                };
            });
            return _runSequential(tasks).then(function () {
                return { created: created, failures: failures };
            });
        });
    };

    // Runs an array of functions returning promises strictly in order.
    var _runSequential = function (tasks) {
        return tasks.reduce(function (prev, task) {
            return prev.then(task);
        }, $q.when());
    };

    //set cookies
    $('#dismiss').on('click', function () {
        // set expire date.
        if (typeof(Storage) !== "undefined" && localStorage) {
            localStorage.setItem('dismissClicked', 'YES');
        }
    });

    if (localStorage.getItem('dismissClicked') !== 'YES') {
        function showWelcomeMessage() {
            $('#myModal_Welcome').modal('show');
        }

        window.onload = showWelcomeMessage;
    }
}]);
