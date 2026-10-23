/**
 The MIT License (MIT)
 Copyright (c) 2015, Kyriakos Georgiou, Data Management Systems Laboratory (DMSL)
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
app.controller('ControlBarController',
    ['$scope', '$rootScope',
        'AnyplaceService', 'GMapService', 'AnyplaceAPIService',
        function ($scope, $rootScope,
                  AnyplaceService, GMapService, AnyplaceAPIService) {

    $scope.anyService = AnyplaceService;
    $scope.gmapService = GMapService;
    $scope.isAuthenticated = false;

    $scope.creds = {
        fullName: undefined,
        username: undefined,
        password: undefined
    };

    $scope.emptyUser = {
        name: undefined,
        email: undefined,
        id: undefined,
        username: undefined,
        password: undefined,
        access_token: undefined
    }

    $scope.user = $scope.emptyUser
    var self = this; //to be able to reference to it in a callback, you could use $scope instead

    angular.element(document).ready(function () {
        // if a local user was already logged in (in cookies) then refresh it (with the server)
        if ($scope.user == undefined || $scope.user.access_token == undefined) {
            $scope.refreshLocalLogin()
        }
    });

    $scope.showFullControls = true;
    $scope.setAuthenticated = function (bool) { $scope.isAuthenticated = bool; };
    $scope.toggleFullControls = function () { $scope.showFullControls = !$scope.showFullControls; };

    $scope.copyApiKey = function () {
        LOG.W("Copying api key")
        var copyTextarea = document.querySelector('#auth-api-key');
        copyTextarea.focus();
        copyTextarea.select();
        document.execCommand("copy");
        _info($scope, "API key copied!");
    }

    $scope.showGoogleAuth = function () { // INFO this is anyplace access token
        if (!$scope.user.access_token) { return; }
        AnyplaceService.addAlert('success', 'access_token: ' + $scope.user.access_token);
    };

    $scope.refreshLocalLogin = function () {
        LOG.D3("refreshLocalLogin");
        var jsonReq = {};
        var cookieAccessToken = $scope.getCookie("localAccessToken");
        if (!cookieAccessToken || cookieAccessToken === "") { return; }

        jsonReq.access_token = cookieAccessToken;
        LOG.D2("Refreshing local login.");

        var promise = AnyplaceAPIService.refreshLocalAccount(jsonReq);
        promise.then(
            function (resp) { // on success
                var data = resp.data;
                if (typeof data === "string") {
                    try { data = JSON.parse(data); } catch (e) { }
                }
                if (!data || !data.user) {
                    $scope.deleteCookie("localAccessToken");
                    return;
                }
                LOG.D4("refreshLocalLogin");
                LOG.D4(resp);
                if (!$scope.user) { $scope.user = {}; }
                $scope.user.username = data.user.username;
                $scope.user.name = data.user.name;
                $scope.user.email = data.user.email;
                $scope.user.id =  data.user.owner_id;
                $scope.user.accountType = "local";
                $scope.user.type = data.user.type;

                $scope.user.access_token = data.user.access_token;
                app.user=$scope.user;
                $scope.setAuthenticated(true);
                if ($scope.user && $scope.user.id) { $scope.$broadcast('loggedIn', []); }
            },
            function (resp) {
                // Silently clear expired or invalid cookie on background refresh
                $scope.deleteCookie("localAccessToken");
            }
        );
    };

    $scope.loginWithLocalAccount = function () {
        var unameEl = document.getElementById('uname');
        var pswEl = document.getElementById('sPsw');

        var uVal = "";
        var pVal = "";

        // First check DOM inputs directly to capture browser autofill/password manager values
        if (unameEl && unameEl.value && unameEl.value.trim().length > 0) {
            uVal = unameEl.value.trim();
        } else if ($scope.user && $scope.user.username && $scope.user.username.trim().length > 0) {
            uVal = $scope.user.username.trim();
        }

        if (pswEl && pswEl.value && pswEl.value.trim().length > 0) {
            pVal = pswEl.value.trim();
        } else if ($scope.user && $scope.user.password && $scope.user.password.trim().length > 0) {
            pVal = $scope.user.password.trim();
        }

        if (!uVal || !pVal) {
            _warn($scope, "Please enter both username and password.");
            return;
        }

        if (!$scope.user) { $scope.user = {}; }
        $scope.user.username = uVal;
        $scope.user.password = pVal;

        var jsonReq = {
            username: uVal,
            password: pVal
        };

        LOG.D3("loginWithLocalAccount: " + uVal);

        var promise = AnyplaceAPIService.loginLocalAccount(jsonReq);
        promise.then(
            function (resp) { // on success
                var data = resp.data;
                if (typeof data === "string") {
                    try { data = JSON.parse(data); } catch (e) { }
                }
                if (!data || !data.user) {
                    var errTxt = (data && data.message) ? data.message : "Login failed: Invalid response";
                    _err($scope, errTxt);
                    return;
                }
                LOG.D4(resp);
                $scope.user.username = data.user.username;
                $scope.user.name = data.user.name;
                $scope.user.email = data.user.email;
                $scope.user.id =  data.user.owner_id;
                $scope.user.accountType = "local";
                $scope.user.type = data.user.type;
                $scope.user.access_token = data.user.access_token;
                app.user = $scope.user;
                $scope.setAuthenticated(true);

                // Always persist fresh access token
                $scope.setCookie("localAccessToken", $scope.user.access_token, 30);

                // Hide login modal and menu
                var modal = document.getElementById('id01');
                if (modal) { modal.style.display = 'none'; }
                var regOpts = document.getElementById('registerOptions');
                if (regOpts) { regOpts.style.display = 'none'; }

                if ($scope.user && $scope.user.id) { $scope.$broadcast('loggedIn', []); }
                _suc($scope, "Welcome back, " + ($scope.user.name || $scope.user.username) + "!");
            },
            function (resp) {
                var serverMsg = "";
                if (resp && resp.data) {
                    var d = resp.data;
                    if (typeof d === "string") {
                        try { d = JSON.parse(d); } catch (e) { }
                    }
                    if (d && typeof d === "object") {
                        if (d.message) {
                            serverMsg = d.message;
                        } else if (Array.isArray(d.error_messages) && d.error_messages.length > 0) {
                            serverMsg = d.error_messages.join(", ");
                        }
                    }
                }
                if (!serverMsg && resp && resp.status === 0) {
                    serverMsg = "Network connection error.";
                }
                var displayMsg = serverMsg ? "Login failed: " + serverMsg : "Login failed. Please check your credentials.";
                _err($scope, displayMsg);
                $scope.deleteCookie("localAccessToken");
            }
        );
    };

    $scope.registerLocalAccount = function () {
        var jsonReq = {};
        jsonReq.name = ($scope.user && $scope.user.name) ? $scope.user.name : "";
        jsonReq.email = ($scope.user && $scope.user.email) ? $scope.user.email : "";
        jsonReq.username = ($scope.user && $scope.user.username) ? $scope.user.username : "";
        jsonReq.password = ($scope.user && $scope.user.password) ? $scope.user.password : "";

        var rPswEl = document.getElementById('rPsw');
        if (rPswEl && rPswEl.value && rPswEl.value.trim().length > 0) {
            jsonReq.password = rPswEl.value.trim();
        }

        var promise = AnyplaceAPIService.registerLocalAccount(jsonReq);
        promise.then(function (resp) {  // on success
                var data = resp.data;
                var modal = document.getElementById('id02');
                if (modal) { modal.style.display = 'none'; }
                _suc($scope, "Successfully registered! Please log in.");
            },
            function (resp) {
                var msg = "Something went wrong at registration.";
                if (resp && resp.data) {
                    var d = resp.data;
                    if (typeof d === "string") { try { d = JSON.parse(d); } catch (e) { } }
                    if (d && d.message) { msg = d.message; }
                }
                _err($scope, msg);
            }
        );
    };

    $scope.signOut = function () {
        $scope.isAuthenticated = false;

        $scope.$broadcast('loggedOff', []);
        $scope.user={};
        clearFingerprintCoverage();
        clearFingerprintHeatmap();
        $scope.deleteCookie("localAccessToken");
    };

    function clearFingerprintCoverage() {
        var check = 0;
        if (heatMap[check] !== undefined && heatMap[check] !== null) {
            var i = heatMap.length;
            while (i--) {
                heatMap[i].rectangle.setMap(null);
                heatMap[i] = null;
            }
            heatMap = [];
            document.getElementById("radioHeatmapRSS-mode").classList.remove('quickaction-selected');
            _HEATMAP_FINGERPRINT_COVERAGE = false;
            setColorClicked('g', false);
            setColorClicked('y', false);
            setColorClicked('o', false);
            setColorClicked('p', false);
            setColorClicked('r', false);
            $scope.radioHeatmapRSSMode = false;
            if (typeof (Storage) !== "undefined" && localStorage) {
                localStorage.setItem('radioHeatmapRSSMode', 'NO');
            }
            $scope.anyService.radioHeatmapRSSMode = false;
            $scope.radioHeatmapRSSHasGreen = false;
            $scope.radioHeatmapRSSHasYellow = false;
            $scope.radioHeatmapRSSHasOrange = false;
            $scope.radioHeatmapRSSHasPurple = false;
            $scope.radioHeatmapRSSHasRed = false;
            $cookieStore.put('RSSClicked', 'NO');
        }
    }

    function clearFingerprintHeatmap() {
        var check = 0;
        if (fingerPrintsMap[check] !== undefined && fingerPrintsMap[check] !== null) {
            var i = fingerPrintsMap.length;
            //hide fingerPrints
            while (i--) {
                fingerPrintsMap[i].setMap(null);
                fingerPrintsMap[i] = null;
            }
            fingerPrintsMap = [];
            _FINGERPRINTS_IS_ON = false;
            document.getElementById("fingerPrints-mode").classList.remove('quickaction-selected');
        }

        if (heatmap && heatmap.getMap()) { //hide fingerPrints heatmap
            heatmap.setMap(null);
            _FINGERPRINTS_IS_ON = false;
            document.getElementById("fingerPrints-mode").classList.remove('quickaction-selected');
            _HEATMAP_F_IS_ON = false;
            var i = heatmapFingerprints.length;
            while (i--) { heatmapFingerprints[i] = null; }
            heatmapFingerprints = [];
        }
    }

    $scope.getCookie = function (cname) {
        var name = cname + "=";
        var ca = document.cookie.split(';');
        for (var i = 0; i < ca.length; i++) {
            var c = ca[i];
            while (c.charAt(0) == ' ') { c = c.substring(1); }
            if (c.indexOf(name) == 0) { return c.substring(name.length, c.length); }
        }
        return "";
    };

    $scope.setCookie = function (cname, cvalue, exdays) {
        var d = new Date();
        d.setTime(d.getTime() + (exdays * 24 * 60 * 60 * 1000));
        var expires = "expires=" + d.toUTCString();
        document.cookie = cname + "=" + cvalue + "; " + expires + "; path=/; SameSite=Lax";
    };

    $scope.deleteCookie = function (cname) {
        document.cookie = cname + "=; expires=" + new Date(0).toUTCString() + "; path=/; SameSite=Lax";
        document.cookie = cname + "=; expires=" + new Date(0).toUTCString() + ";";
    };

    $scope.tab = 1;
    $scope.setTab = function (num) { $scope.tab = num; };
    $scope.isTabSet = function (num) { return $scope.tab === num; };

    $scope.isAdmin = function () {
        if ($scope.user == null) {
            return false;
        } else if ($scope.user.type == undefined) {
            return false;
        } else if ($scope.user.type == "admin") {
            return true;
        }
    };

    $scope.isAdminOrModerator = function () {
        if ($scope.user == null) {
            return false;
        } else if ($scope.user.type == undefined) {
            return false;
        } else if ($scope.user.type == "admin" || $scope.user.type == "moderator") {
            return true;
        }
    };

    var myLocMarker = undefined;
    $scope.userPosition = undefined;
    var pannedToUserPosOnce = false;
    $scope.isUserLocVisible = false;

    $scope.getIsUserLocVisible = function () { return $scope.isUserLocVisible; };

    $scope.panToUserLocation = function () {
        if (!$scope.userPosition)  return;

        GMapService.gmap.panTo($scope.userPosition);
        GMapService.gmap.setZoom(20);
    };

    $scope.displayMyLocMarker = function (posLatlng) {
        if (myLocMarker && myLocMarker.getMap()) {
            myLocMarker.setPosition(posLatlng);
            return;
        }
    };

    $scope.displayMyLocMarker = function (posLatlng) {
        if (myLocMarker && myLocMarker.getMap()) {
            myLocMarker.setPosition(posLatlng);
            return;
        }
        var s = new google.maps.Size(20, 20);
        if ($scope.isFirefox) s = new google.maps.Size(48, 48);

        myLocMarker = new google.maps.Marker({
            position: posLatlng,
            map: GMapService.gmap,
            draggable: false,
            icon: {
                url: 'build/images/location-radius-centre.png',
                origin: new google.maps.Point(0, 0), /* origin is 0,0 */
                anchor: new google.maps.Point(10, 10), /* anchor is bottom center of the scaled image */
                size: s,
                scaledSize: new google.maps.Size(20, 20)
            }
        });
    };

    $scope.hideUserLocation = function () {
        if (myLocMarker)  myLocMarker.setMap(null);
        //if (accuracyRadius) accuracyRadius.setMap(null);
        $scope.isUserLocVisible = false;
    };

    $scope.showUserLocation = function () {
        if ($scope.getIsUserLocVisible()) {
            $scope.hideUserLocation();
            if (navigator.geolocation)  navigator.geolocation.clearWatch(watchPosNum);
            return;
        }

        if (navigator.geolocation) {
            watchPosNum = navigator.geolocation.watchPosition(
                function (position) {
                    var posLatlng = {lat: position.coords.latitude, lng: position.coords.longitude};
                    $scope.userPosition = posLatlng;
                    $scope.displayMyLocMarker(posLatlng);
                    var infowindow = new google.maps.InfoWindow({
                        content: 'Your current location.',
                        maxWidth: 500
                    });

                    google.maps.event.addListener(myLocMarker, 'click', function () {
                        var self = this;
                        $scope.$apply(function () {
                            infowindow.open(GMapService.gmap, self);
                        })
                    });

                    if (!$scope.isUserLocVisible) {
                        $scope.$apply(function () {
                            $scope.isUserLocVisible = true;
                        });
                    }

                    if (!pannedToUserPosOnce) {
                        GMapService.gmap.panTo(posLatlng);
                        GMapService.gmap.setZoom(19);
                        pannedToUserPosOnce = true;
                    }
                },
                function (err) {
                    $scope.$apply(function () {
                      HandleGeolocationError($scope, err.code);
                    });
                });
        } else {
            _err($scope, ERR_GEOLOC_NOT_SUPPORTED);
        }
    };

    $scope.copyApiKey = function () {
        var copyTextarea = document.querySelector('#auth-api-key');
        copyTextarea.focus();
        copyTextarea.select();
        document.execCommand("copy");
        _info($scope, "API key copied");
    }

    $scope.centerViewToSelectedItem = function () {
        if ($scope.anyService.selectedBuilding == null || $scope.anyService.selectedBuilding == undefined) {
            _warn_autohide_timeout($scope, "Select a space first", 2000);
            return;
        }
        var position = {};
        if ($scope.anyService.selectedPoi) {
            var p = $scope.anyService.selectedPoi;
            position = {lat: parseFloat(p.coordinates_lat), lng: parseFloat(p.coordinates_lon)};
        } else if ($scope.anyService.selectedBuilding) {
            var b = $scope.anyService.selectedBuilding;
            position = {lat: parseFloat(b.coordinates_lat), lng: parseFloat(b.coordinates_lon)};
        } else {
            _err($scope, "No building is selected.");
            return;
        }
        $scope.gmapService.gmap.panTo(position);
        $scope.gmapService.gmap.setZoom(20);
    }
}]);
