/*
 * AnyPlace: A free and open Indoor Navigation Service with superb accuracy!
 *
 * Anyplace is a first-of-a-kind indoor information service offering GPS-less
 * localization, navigation and search inside buildings using ordinary smartphones.
 *
 * Author(s): Lambros Petrou, Kyriakos Georgiou
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

USGSOverlay.prototype = new google.maps.OverlayView();
/** @constructor */
function USGSOverlay(bounds, image, map) {

    // Now initialize all properties.
    this.bounds_ = bounds;
    this.image_ = image;
    this.image64 = (typeof image === 'string') ? image : (image && image.src ? image.src : '');
    this.map_ = map;

    // We define a property to hold the image's div.
    this.div_ = null;
    this.img_ = null;

    // Explicitly call setMap on this overlay if map was provided
    if (map) {
        this.setMap(map);
    }
}

USGSOverlay.prototype.onAdd = function() {

    // Note: an overlay's receipt of onAdd() indicates that
    // the map's panes are now available for attaching
    // the overlay to the map via the DOM.

    if (!this.div_) {
        // Create the DIV and set some basic attributes.
        var div = document.createElement('div');
        div.id = "ground_overlay";
        div.style.borderStyle = 'none';
        div.style.borderWidth = '0px';
        div.style.position = 'absolute';

        // Use existing image element if supplied, or create a new one
        var img;
        if (typeof HTMLImageElement !== 'undefined' && this.image_ instanceof HTMLImageElement) {
            img = this.image_;
        } else {
            img = document.createElement('img');
            img.src = this.image64;
        }
        img.style.width = '100%';
        img.style.height = '100%';
        img.style.position = 'absolute';

        if (img.parentNode !== div) {
            div.appendChild(img);
        }

        // Set the overlay's properties
        this.div_ = div;
        this.img_ = img;
    }

    // We add an overlay to a map via one of the map's panes.
    // We'll add this overlay to the overlayLayer pane.
    var panes = this.getPanes();
    if (panes && panes.overlayLayer && this.div_.parentNode !== panes.overlayLayer) {
        panes.overlayLayer.appendChild(this.div_);
    }
};

USGSOverlay.prototype.draw = function() {

    if (!this.div_ || !this.bounds_) {
        return;
    }

    var overlayProjection = this.getProjection();
    if (!overlayProjection) {
        return;
    }

    // Retrieve the southwest and northeast coordinates of this overlay
    // in latlngs and convert them to pixels coordinates.
    // We'll use these coordinates to resize the DIV.
    var sw = overlayProjection.fromLatLngToDivPixel(this.bounds_.getSouthWest());
    var ne = overlayProjection.fromLatLngToDivPixel(this.bounds_.getNorthEast());
    if (!sw || !ne) {
        return;
    }

    // Resize the image's DIV to fit the indicated dimensions.
    var div = this.div_;
    div.style.left = sw.x + 'px';
    div.style.top = ne.y + 'px';
    div.style.width = (ne.x - sw.x) + 'px';
    div.style.height = (sw.y - ne.y) + 'px';
};

USGSOverlay.prototype.onRemove = function() {
    // Detach from DOM pane, but retain the decoded img_ and div_ so
    // re-attaching on floor return is instant (<1ms) with zero re-decode overhead.
    if (this.div_ && this.div_.parentNode) {
        this.div_.parentNode.removeChild(this.div_);
    }
};

USGSOverlay.prototype.destroy = function() {
    // Explicit destruction method for LRU cache eviction to free memory.
    this.setMap(null);
    if (this.div_ && this.div_.parentNode) {
        this.div_.parentNode.removeChild(this.div_);
    }
    if (this.img_) {
        this.img_.src = '';
        this.img_ = null;
    }
    this.div_ = null;
    this.image_ = null;
    this.image64 = null;
    this.bounds_ = null;
};