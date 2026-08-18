/*
 * Anyplace: A free and open Indoor Navigation Service with superb accuracy!
 *
 * Anyplace is a first-of-a-kind indoor information service offering GPS-less
 * localization, navigation and search inside buildings using ordinary smartphones.
 *
 * Author(s): Timotheos Constambeys, Lambros Petrou
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
 * this software and associated documentation files (the "Software"), to deal in the
 * Software without restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so, subject to the
 * following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 */

package cy.ac.ucy.cs.anyplace.logger;

import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.GooglePlayServicesUtil;
import com.google.android.gms.common.api.GoogleApiClient;
import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationListener;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.maps.CameraUpdate;
import com.google.android.gms.maps.CameraUpdateFactory;

import com.google.android.gms.maps.GoogleMap;
import com.google.android.gms.maps.GoogleMap.CancelableCallback;
import com.google.android.gms.maps.GoogleMap.OnMarkerDragListener;
import com.google.android.gms.maps.OnMapReadyCallback;
import com.google.android.gms.maps.SupportMapFragment;
import com.google.android.gms.maps.GoogleMap.OnMapClickListener;
import com.google.android.gms.maps.model.BitmapDescriptorFactory;
import com.google.android.gms.maps.model.CameraPosition;
import com.google.android.gms.maps.model.Circle;
import com.google.android.gms.maps.model.CircleOptions;
import com.google.android.gms.maps.model.LatLng;
import com.google.android.gms.maps.model.MapStyleOptions;
import com.google.android.gms.maps.model.Marker;
import com.google.android.gms.maps.model.MarkerOptions;
import com.google.android.gms.maps.model.TileOverlay;
import com.google.android.gms.maps.model.TileOverlayOptions;
import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.android.gms.tasks.Task;
import com.google.maps.android.clustering.Cluster;
import com.google.maps.android.clustering.ClusterManager;
import com.google.maps.android.clustering.ClusterManager.OnClusterClickListener;
import com.google.maps.android.clustering.ClusterManager.OnClusterItemClickListener;
import com.google.maps.android.heatmaps.Gradient;
import com.google.maps.android.heatmaps.HeatmapTileProvider;
import com.google.maps.android.heatmaps.WeightedLatLng;

import cy.ac.ucy.cs.anyplace.lib.RadioMap;
import cy.ac.ucy.cs.anyplace.lib.android.logger.LogRecordMap;
import cy.ac.ucy.cs.anyplace.lib.android.nav.AnyPlaceSeachingHelper;
import cy.ac.ucy.cs.anyplace.logger.LoggerPrefs.Action;
import cy.ac.ucy.cs.anyplace.lib.android.logger.LoggerWiFi;
import cy.ac.ucy.cs.anyplace.lib.android.logger.LoggerWiFi.Function;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.UploadRSSLogTask;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchBuildingsTask.FetchBuildingsTaskListener;
import cy.ac.ucy.cs.anyplace.lib.android.wifi.SimpleWifiManager;
import cy.ac.ucy.cs.anyplace.lib.android.wifi.WifiReceiver;
import cy.ac.ucy.cs.anyplace.lib.android.sensors.MovementDetector;
import cy.ac.ucy.cs.anyplace.lib.android.sensors.SensorsMain;
import cy.ac.ucy.cs.anyplace.lib.android.nav.BuildingModel;
import cy.ac.ucy.cs.anyplace.lib.android.nav.FloorModel;
import cy.ac.ucy.cs.anyplace.lib.android.nav.AnyUserData;
import cy.ac.ucy.cs.anyplace.lib.android.nav.AnyPlaceSeachingHelper.SearchTypes;
import cy.ac.ucy.cs.anyplace.lib.android.cache.AnyplaceCache;
import cy.ac.ucy.cs.anyplace.lib.android.AnyplaceDebug;
import cy.ac.ucy.cs.anyplace.lib.android.cache.BackgroundFetchListener;
import cy.ac.ucy.cs.anyplace.lib.android.googlemap.MapTileProvider;
import cy.ac.ucy.cs.anyplace.lib.android.googlemap.MyBuildingsRenderer;
import cy.ac.ucy.cs.anyplace.lib.android.utils.NetworkUtils;
import cy.ac.ucy.cs.anyplace.lib.android.utils.GeoPoint;
import cy.ac.ucy.cs.anyplace.lib.android.utils.AnyplaceUtils;
import cy.ac.ucy.cs.anyplace.lib.android.utils.AndroidUtils;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchFloorsByBuidTask.FetchFloorsByBuidTaskListener;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.DeleteFolderBackgroundTask;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.DownloadRadioMapTaskBuid;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchFloorPlanTask;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchNearBuildingsTask;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.DownloadRadioMapTaskBuid.DownloadRadioMapListener;

import android.Manifest;
import android.app.AlertDialog;
import android.app.ProgressDialog;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import com.google.android.gms.maps.model.BitmapDescriptorFactory;
import com.google.android.gms.maps.model.CircleOptions;
import com.google.android.gms.maps.model.GroundOverlayOptions;
import com.google.android.gms.maps.model.LatLngBounds;

import java.io.File;
import java.io.FilenameFilter;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentSender;
import android.content.SharedPreferences;
import android.content.SharedPreferences.OnSharedPreferenceChangeListener;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Color;
import android.location.Location;
import android.location.LocationManager;
import android.net.wifi.ScanResult;
import android.os.AsyncTask;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Looper;
import android.preference.PreferenceManager;
import android.telecom.Call;
import android.text.Html;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuInflater;
import android.view.MenuItem;
import android.view.View;
import android.view.View.OnClickListener;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.ImageButton;
import android.widget.ProgressBar;
import android.widget.RelativeLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

/**
 * Anyplace Logger Activity. The main interface for the Logger functionality
 *
 */
public class AnyplaceLoggerActivity extends AppCompatActivity implements
    OnSharedPreferenceChangeListener, GoogleApiClient.ConnectionCallbacks,
    GoogleApiClient.OnConnectionFailedListener, LocationListener, OnMapClickListener,
    OnMapReadyCallback {
  private static final String TAG = "AnyplaceLoggerActivity";

  // Define a request code to send to Google Play services This code is
  // returned in Activity.onActivityResult
  private final static int LOCATION_CONNECTION_FAILURE_RESOLUTION_REQUEST = 9000;
  private final static int PLAY_SERVICES_RESOLUTION_REQUEST = 9001;
  private final static int PREFERENCES_ACTIVITY_RESULT = 1114;
  private static final int SELECT_PLACE_ACTIVITY_RESULT = 1112;
  private final int REQUEST_PERMISSION_LOCATION = 1;

  private static final float mInitialZoomLevel = 18.0f;

  // Google API

  private LocationListener mLocationListener = this;
  // Location API
  // private LocationClient mLocationClient;
  // Define an object that holds accuracy and frequency parameters
  private LocationRequest mLocationRequest;

  private GoogleMap mMap;
  private Marker marker;
  private LatLng curLocation = null;
  private Location mLastLocation;

  private FusedLocationProviderClient mFusedLocationClient;

  // <Load Building and Marker>
  private ClusterManager<BuildingModel> mClusterManager;
  private DownloadRadioMapTaskBuid downloadRadioMapTaskBuid;
  private SearchTypes searchType = null;
  private Marker gpsMarker = null;
  private float bearing;
  private ImageButton btnTrackme;
  // </Load Building and Marker>

  // UI Elements
  ProgressBar progressBar;

  // WiFi manager
  private SimpleWifiManager wifi;

  // WiFi Receiver
  private WifiReceiver receiverWifi;

  // TextView showing the current floor
  private TextView textFloor;

  // TextView showing the current scan results
  private TextView scanResults;

  // ProgressDialog
  private ProgressDialog mSamplingProgressDialog;

  // Path to store rss file
  private String folder_path;

  // Filename to store rss records
  private String filename_rss;

  // Button that records access points
  private Button btnRecord;

  // the textview that displays the current position and heading
  private TextView mTrackingInfoView = null;

  private SharedPreferences preferences;

  // Positioning
  private SensorsMain positioning;
  private MovementDetector movementDetector;

  // Direct Hardware Accelerometer, Magnetometer & Gyroscope Sensors
  private SensorManager mSensorManager;
  private Sensor mAccelerometerSensor;
  private Sensor mMagnetometerSensor;
  private Sensor mGyroscopeSensor;
  private float[] mGravityMatrix = new float[3];
  private float[] mGeomagneticMatrix = new float[3];
  private float[] mGyroscopeMatrix = new float[3];
  private boolean mHasGravity = false;
  private boolean mHasGeomagnetic = false;
  private boolean mHasGyroscope = false;

  private final SensorEventListener mHardwareSensorListener = new SensorEventListener() {
    @Override
    public void onSensorChanged(SensorEvent event) {
      if (event == null || event.values == null) return;

      if (event.sensor.getType() == Sensor.TYPE_ACCELEROMETER) {
        System.arraycopy(event.values, 0, mGravityMatrix, 0, 3);
        mHasGravity = true;
        if (movementDetector != null) {
          movementDetector.onNewAccelerometer(event.values);
        }
      } else if (event.sensor.getType() == Sensor.TYPE_MAGNETIC_FIELD) {
        System.arraycopy(event.values, 0, mGeomagneticMatrix, 0, 3);
        mHasGeomagnetic = true;
      } else if (event.sensor.getType() == Sensor.TYPE_GYROSCOPE) {
        System.arraycopy(event.values, 0, mGyroscopeMatrix, 0, 3);
        mHasGyroscope = true;
      }

      if (mHasGravity && mHasGeomagnetic) {
        float R[] = new float[9];
        float I[] = new float[9];
        boolean success = SensorManager.getRotationMatrix(R, I, mGravityMatrix, mGeomagneticMatrix);
        if (success) {
          float orientation[] = new float[3];
          SensorManager.getOrientation(R, orientation);
          float azimuthInDegrees = (float) Math.toDegrees(orientation[0]);
          if (azimuthInDegrees < 0) {
            azimuthInDegrees += 360;
          }
          raw_heading = azimuthInDegrees;
          updateInfoView();
        }
      }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {}
  };
  private float raw_heading = 0.0f;
  private boolean walking = false;

  private boolean upInProgress = false;
  private Object upInProgressLock = new Object();

  private boolean userIsNearby = false;
  private BuildingModel mCurrentBuilding = null;
  private FloorModel mCurrentFloor = null;
  private HeatmapTileProvider mProvider;
  private TileOverlay mHeatmapOverlay = null;
  private List<Circle> mFingerprintCircles = new ArrayList<>();
  // Logger Service
  private int mCurrentSamplesTaken = 0;
  private boolean mIsSamplingActive = false;
  private LoggerWiFi logger;
  private AnyplaceApp app;

  private List<BuildingModel> builds;

  @Override
  public void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    // app = (AnyplaceApp) getApplication();
    setContentView(R.layout.activity_logger);

    mFusedLocationClient = LocationServices.getFusedLocationProviderClient(this);

    textFloor = (TextView) findViewById(R.id.textFloor);
    progressBar = (ProgressBar) findViewById(R.id.progressBar);
    btnRecord = (Button) findViewById(R.id.recordBtn);
    btnRecord.setOnClickListener(new OnClickListener() {
      public void onClick(View v) {
        btnRecordingInfo();
      }
    });

    // setup the trackme button overlaid in the map
    btnTrackme = (ImageButton) findViewById(R.id.btnTrackme);

    btnTrackme.setOnClickListener(new OnClickListener() {
      @Override
      public void onClick(View v) {
        checkLocationPermission();
        if (mFusedLocationClient != null) {
          mFusedLocationClient.getLastLocation().addOnCompleteListener(new OnCompleteListener<Location>() {
            @Override
            public void onComplete(@NonNull Task<Location> task) {
              Location loc = task.getResult();
              if (loc != null) {
                final LatLng coord = new LatLng(loc.getLatitude(), loc.getLongitude());
                if (gpsMarker != null) {
                  gpsMarker.remove();
                }
                MarkerOptions markerOptions = new MarkerOptions()
                    .position(coord)
                    .title("GPS Position")
                    .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE));
                gpsMarker = mMap.addMarker(markerOptions);
                if (mMap != null) {
                  mMap.animateCamera(create3DCameraUpdate(coord, 19.0f));
                }

                AnyplaceServerAPI.fetchBuildings(AnyplaceLoggerActivity.this, new FetchBuildingsTaskListener() {
                  @Override
                  public void onSuccess(String result, List<BuildingModel> buildings) {
                    if (buildings != null && !buildings.isEmpty()) {
                      builds = buildings;
                      FetchNearBuildingsTask nearest = new FetchNearBuildingsTask();
                      nearest.run(buildings.iterator(), coord.latitude, coord.longitude, 200);
                      if (nearest.buildings != null && nearest.buildings.size() > 0) {
                        bypassSelectBuildingActivity(nearest.buildings.get(0));
                      }
                    }
                  }

                  @Override
                  public void onErrorOrCancel(String result) {
                  }
                });
              } else {
                Toast.makeText(getApplicationContext(), "Locating GPS position...", Toast.LENGTH_SHORT).show();
                if (mLocationRequest != null && mLocationCallbackConnected != null) {
                  try {
                    mFusedLocationClient.requestLocationUpdates(mLocationRequest, mLocationCallbackConnected, Looper.getMainLooper());
                  } catch (Exception ignored) {}
                }
              }
            }
          });
        }
      }
    });

    ImageButton btnFloorUp = (ImageButton) findViewById(R.id.btnFloorUp);
    btnFloorUp.setOnClickListener(new OnClickListener() {

      @Override
      public void onClick(View v) {

        if (mCurrentBuilding == null) {
          Toast.makeText(getBaseContext(), "Load a map before tracking can be used!", Toast.LENGTH_SHORT).show();
          return;
        }

        if (mIsSamplingActive) {
          Toast.makeText(getBaseContext(), "Invalid during logging.", Toast.LENGTH_LONG).show();
          return;
        }

        // Move one floor up
        int index = mCurrentBuilding.getSelectedFloorIndex();

        if (mCurrentBuilding.checkIndex(index + 1)) {
          bypassSelectBuildingActivity(mCurrentBuilding, mCurrentBuilding.getFloors().get(index + 1));
        }

      }
    });

    ImageButton btnFloorDown = (ImageButton) findViewById(R.id.btnFloorDown);
    btnFloorDown.setOnClickListener(new OnClickListener() {

      @Override
      public void onClick(View v) {
        if (mCurrentBuilding == null) {
          Toast.makeText(getBaseContext(), "Load a map before tracking can be used!", Toast.LENGTH_SHORT).show();
          return;
        }

        if (mIsSamplingActive) {
          Toast.makeText(getBaseContext(), "Invalid during logging.", Toast.LENGTH_LONG).show();
          return;
        }

        // Move one floor down
        int index = mCurrentBuilding.getSelectedFloorIndex();

        if (mCurrentBuilding.checkIndex(index - 1)) {
          bypassSelectBuildingActivity(mCurrentBuilding, mCurrentBuilding.getFloors().get(index - 1));
        }
      }

    });

    scanResults = (TextView) findViewById(R.id.detectedAPs);
    mTrackingInfoView = (TextView) findViewById(R.id.trackingInfoData);

    /*
     * Create a new location client, using the enclosing class to handle
     * callbacks.
     */
    // Create the LocationRequest object
    mLocationRequest = LocationRequest.create();
    // Use high accuracy
    mLocationRequest.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY);
    // Set the update interval to 2 seconds
    mLocationRequest.setInterval(2000);
    // Set the fastest update interval to 1 second
    mLocationRequest.setFastestInterval(1000);

    // get settings
    PreferenceManager.setDefaultValues(this, getString(R.string.preferences_file), MODE_PRIVATE,
        cy.ac.ucy.cs.anyplace.lib.R.xml.preferences_logger, true);
    preferences = getSharedPreferences(getString(R.string.preferences_file), MODE_PRIVATE);
    SharedPreferences.Editor initEditor = preferences.edit();
    if (!BuildConfig.BOOTSTRAP_USERNAME.isEmpty()) initEditor.putString("username", BuildConfig.BOOTSTRAP_USERNAME);
    if (!BuildConfig.BOOTSTRAP_PASSWORD.isEmpty()) initEditor.putString("password", BuildConfig.BOOTSTRAP_PASSWORD);
    initEditor.putString("server_ip_address", BuildConfig.SERVER_HOST);
    initEditor.putString("server_port", BuildConfig.SERVER_PORT);
    initEditor.putString("samples_interval", "1000");
    initEditor.commit();

    SharedPreferences apPrefs = getSharedPreferences("Anyplace_Preferences", MODE_PRIVATE);
    SharedPreferences.Editor apEditor = apPrefs.edit();
    if (!BuildConfig.BOOTSTRAP_USERNAME.isEmpty()) apEditor.putString("username", BuildConfig.BOOTSTRAP_USERNAME);
    if (!BuildConfig.BOOTSTRAP_PASSWORD.isEmpty()) apEditor.putString("password", BuildConfig.BOOTSTRAP_PASSWORD);
    if (!BuildConfig.BOOTSTRAP_ACCESS_TOKEN.isEmpty()) apEditor.putString("access_token", BuildConfig.BOOTSTRAP_ACCESS_TOKEN);
    apEditor.putString("server_ip_address", BuildConfig.SERVER_HOST);
    apEditor.putString("server_port", BuildConfig.SERVER_PORT);
    apEditor.putString("samples_interval", "1000");
    apEditor.commit();

    SharedPreferences defPrefs = PreferenceManager.getDefaultSharedPreferences(this);
    SharedPreferences.Editor defEditor = defPrefs.edit();
    if (!BuildConfig.BOOTSTRAP_USERNAME.isEmpty()) defEditor.putString("username", BuildConfig.BOOTSTRAP_USERNAME);
    if (!BuildConfig.BOOTSTRAP_PASSWORD.isEmpty()) defEditor.putString("password", BuildConfig.BOOTSTRAP_PASSWORD);
    if (!BuildConfig.BOOTSTRAP_ACCESS_TOKEN.isEmpty()) defEditor.putString("access_token", BuildConfig.BOOTSTRAP_ACCESS_TOKEN);
    defEditor.putString("server_ip_address", BuildConfig.SERVER_HOST);
    defEditor.putString("server_port", BuildConfig.SERVER_PORT);
    defEditor.putString("samples_interval", "1000");
    defEditor.commit();

    preferences.registerOnSharedPreferenceChangeListener(this);
    onSharedPreferenceChanged(preferences, "walk_bar");

    File appStorageDir = getExternalFilesDir(null);
    String defaultFolder = (appStorageDir != null) ? appStorageDir.getAbsolutePath() : getFilesDir().getAbsolutePath();
    folder_path = preferences.getString("folder_browser", defaultFolder);
    filename_rss = preferences.getString("filename_log", "anyplace_rss.txt");

    if (appStorageDir != null) {
      if (!appStorageDir.exists()) {
        appStorageDir.mkdirs();
      }
      SharedPreferences.Editor editor = preferences.edit();
      editor.putString("folder_browser", folder_path);
      editor.putString("filename_log", filename_rss);
      editor.commit();
    }

    // WiFi manager to manage scans
    wifi = SimpleWifiManager.getInstance(getApplicationContext());
    // Create new receiver to get broadcasts
    receiverWifi = new SimpleWifiReceiver();
    wifi.registerScan(receiverWifi);
    wifi.startScan(preferences.getString("samples_interval", "1000"));

    positioning = new SensorsMain(this);
    movementDetector = new MovementDetector();
    positioning.addListener(movementDetector);
    positioning.addListener(new OrientationListener());
    movementDetector.addStepListener(new WalkingListener());

    AnyplaceLoggerReceiver mSamplingAnyplaceLoggerReceiver = new AnyplaceLoggerReceiver();
    logger = new LoggerWiFi(mSamplingAnyplaceLoggerReceiver);

    setUpMapIfNeeded();
  }

  public static final int MY_PERMISSIONS_REQUEST_LOCATION = 99;


  private void checkLocationPermission() {
    if (ActivityCompat.checkSelfPermission(this,
        Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {

      // Should we show an explanation?
      if (ActivityCompat.shouldShowRequestPermissionRationale(this,
          Manifest.permission.ACCESS_FINE_LOCATION)) {

        // Show an explanation to the user *asynchronously* -- don't block
        // this thread waiting for the user's response! After the user
        // sees the explanation, try again to request the permission.
        new AlertDialog.Builder(this)
            .setTitle("Location Permission Needed")
            .setMessage("This app needs the Location permission, please accept to use location functionality")
            .setPositiveButton("OK", new DialogInterface.OnClickListener() {
              @Override
              public void onClick(DialogInterface dialogInterface, int i) {
                // Prompt the user once explanation has been shown
                ActivityCompat.requestPermissions(AnyplaceLoggerActivity.this,
                    new String[] { Manifest.permission.ACCESS_FINE_LOCATION },
                    MY_PERMISSIONS_REQUEST_LOCATION);
              }
            })
            .create()
            .show();

      } else {
        // No explanation needed, we can request the permission.
        ActivityCompat.requestPermissions(this,
            new String[] { Manifest.permission.ACCESS_FINE_LOCATION },
            MY_PERMISSIONS_REQUEST_LOCATION);
      }
    }

    if (ActivityCompat.checkSelfPermission(this,
        Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {

      // Should we show an explanation?
      if (ActivityCompat.shouldShowRequestPermissionRationale(this,
          Manifest.permission.ACCESS_COARSE_LOCATION)) {

        // Show an explanation to the user *asynchronously* -- don't block
        // this thread waiting for the user's response! After the user
        // sees the explanation, try again to request the permission.
        new AlertDialog.Builder(this)
            .setTitle("Location Permission Needed")
            .setMessage("This app needs the Location permission, please accept to use location functionality")
            .setPositiveButton("OK", new DialogInterface.OnClickListener() {
              @Override
              public void onClick(DialogInterface dialogInterface, int i) {
                // Prompt the user once explanation has been shown
                ActivityCompat.requestPermissions(AnyplaceLoggerActivity.this,
                    new String[] { Manifest.permission.ACCESS_COARSE_LOCATION },
                    MY_PERMISSIONS_REQUEST_LOCATION);
              }
            })
            .create()
            .show();

      } else {
        // No explanation needed, we can request the permission.
        ActivityCompat.requestPermissions(this,
            new String[] { Manifest.permission.ACCESS_COARSE_LOCATION },
            MY_PERMISSIONS_REQUEST_LOCATION);
      }
    }

  }

  /*
   * GOOGLE MAP FUNCTIONS
   */

  /**
   * Sets up the map if it is possible to do so (i.e., the Google Play
   * services APK is correctly installed) and the map has not already been
   * instantiated.. This will ensure that we only ever call once when
   * {@link #mMap} is not null.
   * <p>
   * If it isn't installed {@link SupportMapFragment} (and
   * {@link com.google.android.gms.maps.MapView MapView}) will show a prompt for
   * the user to install/update the Google Play services APK on
   * their device.
   * <p>
   * A user can return to this FragmentActivity after following the prompt and
   * correctly installing/updating/enabling the Google Play services. Since the
   * FragmentActivity may not have been
   * completely destroyed during this process (it is likely that it would only be
   * stopped or paused), {@link #onCreate(Bundle)} may not be called again so we
   * should call this method in
   * {@link #onResume()} to guarantee that it will be called.
   */
  private void setUpMapIfNeeded() {
    // Do a null check to confirm that we have not already instantiated the
    // map.
    if (mMap != null) {
      return;
    }
    SupportMapFragment mapFragment = (SupportMapFragment) getSupportFragmentManager()
        .findFragmentById(R.id.map);

    mapFragment.getMapAsync(this);

  }

  @Override
  public void onMapReady(GoogleMap googleMap) {
    mMap = googleMap;
    mMap.setMapType(GoogleMap.MAP_TYPE_HYBRID);
    mMap.setBuildingsEnabled(false);
    mMap.setIndoorEnabled(true);
    mMap.getUiSettings().setTiltGesturesEnabled(false);
    mMap.getUiSettings().setCompassEnabled(true);
    mMap.getUiSettings().setZoomControlsEnabled(true);
    mMap.getUiSettings().setMyLocationButtonEnabled(true);

    mClusterManager = new ClusterManager<>(this, mMap);
    mClusterManager.setRenderer(new MyBuildingsRenderer(this, mMap, mClusterManager));
    initListeners();

    // Automatically reload buildings from server and refresh map markers
    handleBuildingsOnMap();
  }

  private CameraUpdate create3DCameraUpdate(LatLng target, float zoom) {
    CameraPosition cp = new CameraPosition.Builder()
        .target(target)
        .zoom(zoom)
        .tilt(0.0f)
        .build();
    return CameraUpdateFactory.newCameraPosition(cp);
  }

  private void updateGpsMarker(LatLng newPos) {
    if (mMap == null || newPos == null) return;
    if (gpsMarker == null) {
      MarkerOptions marker = new MarkerOptions();
      marker.position(newPos);
      marker.title("User").snippet("Estimated Position");
      marker.icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE));
      marker.anchor(0.5f, 0.5f);
      marker.flat(true);
      gpsMarker = mMap.addMarker(marker);
    } else {
      gpsMarker.setPosition(newPos);
    }
    if (gpsMarker != null) {
      gpsMarker.setRotation(raw_heading - bearing);
    }
  }

  LocationCallback mLocationCallbackInitial = new LocationCallback() {
    @Override
    public void onLocationResult(LocationResult locationResult) {
      if (locationResult == null) return;
      List<Location> locationList = locationResult.getLocations();
      if (locationList.size() > 0) {
        Location location = locationList.get(locationList.size() - 1);
        mLastLocation = location;
        LatLng newPos = new LatLng(location.getLatitude(), location.getLongitude());
        updateGpsMarker(newPos);
      }
      if (mFusedLocationClient != null) {
        try {
          mFusedLocationClient.removeLocationUpdates(mLocationCallbackInitial);
        } catch (Exception ignored) {}
      }
    }
  };

  LocationCallback mLocationCallback = new LocationCallback() {
    @Override
    public void onLocationResult(LocationResult locationResult) {
      if (locationResult == null) return;
      List<Location> locationList = locationResult.getLocations();
      if (locationList.size() > 0) {
        Location location = locationList.get(locationList.size() - 1);
        mLastLocation = location;
        LatLng newPos = new LatLng(location.getLatitude(), location.getLongitude());
        updateGpsMarker(newPos);
      }
    }
  };

  LocationCallback mLocationCallbackConnected = new LocationCallback() {
    @Override
    public void onLocationResult(LocationResult locationResult) {
      if (locationResult == null) return;
      List<Location> locationList = locationResult.getLocations();
      if (locationList.size() > 0) {
        Location location = locationList.get(locationList.size() - 1);
        mLastLocation = location;
        LatLng newPos = new LatLng(location.getLatitude(), location.getLongitude());
        updateGpsMarker(newPos);
      }
    }
  };

  private void initCamera() {

    if (gpsMarker != null) {
      return;
    }

    checkLocationPermission();
    mFusedLocationClient
        .getCurrentLocation(LocationRequest.PRIORITY_HIGH_ACCURACY, null)
        .addOnCompleteListener(new OnCompleteListener<Location>() {
          @Override
          public void onComplete(@NonNull Task<Location> task) {
            Location gps = task.getResult();
            mMap.animateCamera(
                create3DCameraUpdate(new LatLng(gps.getLatitude(), gps.getLongitude()), mInitialZoomLevel),
                new CancelableCallback() {

                  @Override
                  public void onFinish() {
                    handleBuildingsOnMap();
                  }

                  @Override
                  public void onCancel() {
                    handleBuildingsOnMap();
                  }
                });
          }
        }).addOnFailureListener(new OnFailureListener() {
          @Override
          public void onFailure(@NonNull Exception e) {
            Toast.makeText(getApplicationContext(), "Failed to get location. Please check if location is enabled",
                Toast.LENGTH_SHORT).show();
            Log.d(TAG, e.getMessage());
          }
        });

  }

  private void initListeners() {

    mMap.setOnCameraIdleListener(new GoogleMap.OnCameraIdleListener() {
      @Override
      public void onCameraIdle() {
        if (mMap == null) return;
        CameraPosition position = mMap.getCameraPosition();
        if (searchType != AnyPlaceSeachingHelper.getSearchType(position.zoom)) {
          searchType = AnyPlaceSeachingHelper.getSearchType(position.zoom);
          if (searchType == SearchTypes.INDOOR_MODE) {
            btnTrackme.setVisibility(View.VISIBLE);
            btnRecord.setVisibility(View.VISIBLE);
          } else if (searchType == SearchTypes.OUTDOOR_MODE) {
            btnTrackme.setVisibility(View.VISIBLE);
            btnRecord.setVisibility(View.VISIBLE);
          }
        }

        bearing = position.bearing;
        if (mClusterManager != null) {
          mClusterManager.onCameraChange(position);
        }
        if ((curLocation == null || (curLocation.latitude == 0.0 && curLocation.longitude == 0.0)) && position != null && position.target != null && (position.target.latitude != 0.0 || position.target.longitude != 0.0)) {
          curLocation = position.target;
        }
        updateInfoView();
      }
    });

    mMap.setOnMapClickListener(this);

    mMap.setOnMarkerDragListener(new OnMarkerDragListener() {

      @Override
      public void onMarkerDragStart(Marker arg0) {
        // TODO Auto-generated method stub

      }

      @Override
      public void onMarkerDragEnd(Marker arg0) {
        if (arg0 != null && arg0.getPosition() != null) {
          LatLng dragPosition = arg0.getPosition();

          if (mIsSamplingActive) {
            saveRecordingToLine(dragPosition);
          }

          curLocation = dragPosition;
          updateInfoView();
        }
      }

      @Override
      public void onMarkerDrag(Marker arg0) {
        // TODO Auto-generated method stub

      }
    });

    mMap.setOnMarkerClickListener(mClusterManager);

    mClusterManager.setOnClusterClickListener(new OnClusterClickListener<BuildingModel>() {
      @Override
      public boolean onClusterClick(Cluster<BuildingModel> cluster) {
        if (cluster != null && cluster.getPosition() != null && mMap != null) {
          mMap.animateCamera(CameraUpdateFactory.newLatLngZoom(cluster.getPosition(), mMap.getCameraPosition().zoom + 2));
        }
        return true;
      }
    });

    mClusterManager.setOnClusterItemClickListener(new OnClusterItemClickListener<BuildingModel>() {
      @Override
      public boolean onClusterItemClick(final BuildingModel b) {
        if (b != null && b.buid != null) {
          Toast.makeText(AnyplaceLoggerActivity.this, "Loading building: " + (b.name != null ? b.name : "Building"), Toast.LENGTH_SHORT).show();
          bypassSelectBuildingActivity(b);
        }
        return true;
      }
    });
  }

  private boolean checkReady() {
    if (mMap == null) {
      Toast.makeText(this, "Map not ready!", Toast.LENGTH_SHORT).show();
      return false;
    }
    return true;
  }

  /******************************************************************************************************************
   * LOCATION API FUNCTIONS
   */
  private boolean checkPlayServices() {
    // Check that Google Play services is available
    int resultCode = GooglePlayServicesUtil.isGooglePlayServicesAvailable(this);
    // If Google Play services is available
    if (ConnectionResult.SUCCESS == resultCode) {
      // In debug mode, log the status
      Log.d("Location Updates", "Google Play services is available.");
      // Continue
      return true;
    } else {
      // Google Play services was not available for some reason

      if (GooglePlayServicesUtil.isUserRecoverableError(resultCode)) {
        GooglePlayServicesUtil.getErrorDialog(resultCode, this, PLAY_SERVICES_RESOLUTION_REQUEST).show();
      } else {
        Log.i("AnyplaceNavigator", "This device is not supported.");
        finish();
      }
      return false;
    }
  }

  @Override
  public void onConnectionFailed(ConnectionResult connectionResult) {

    Log.d("Google Play Services", "Connection failed");
    // Google Play services can resolve some errors it detects.
    // If the error has a resolution, try sending an Intent to
    // start a Google Play services activity that can resolve
    // error.
    if (connectionResult.hasResolution()) {
      try {
        // Start an Activity that tries to resolve the error
        connectionResult.startResolutionForResult(this, LOCATION_CONNECTION_FAILURE_RESOLUTION_REQUEST);
        // Thrown if Google Play services canceled the original
        // PendingIntent
      } catch (IntentSender.SendIntentException e) {
        // Log the error
        e.printStackTrace();
      }
    } else {
      // If no resolution is available, display a dialog to the
      // user with the error.
      GooglePlayServicesUtil.getErrorDialog(connectionResult.getErrorCode(), this, 0).show();
    }

  }

  @Override
  public void onConnected(Bundle arg0) {

    mLocationRequest = LocationRequest.create();
    mLocationRequest.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY);
    mLocationRequest.setInterval(1000); // Update location every second
    checkLocationPermission();
    mFusedLocationClient.requestLocationUpdates(mLocationRequest, mLocationCallback, Looper.myLooper());

    // No map is loaded
    if (checkPlayServices()) {
      initCamera();
      SearchTypes type = AnyPlaceSeachingHelper.getSearchType(mMap.getCameraPosition().zoom);
      if (type == SearchTypes.INDOOR_MODE) {

      } else if (type == SearchTypes.OUTDOOR_MODE) {
      }
    }
  }

  @Override
  public void onConnectionSuspended(int i) {

  }

  @Override
  public void onLocationChanged(final Location location) {

    if (location != null) {
      GeoPoint gps;
      if (AnyplaceDebug.DEBUG_WIFI) {
        gps = AnyUserData.fakeGPS();
      } else {
        gps = new GeoPoint(location.getLatitude(), location.getLongitude());
        // checkLocationPermission();
      }

      updateLocation(gps);
    }
  }

  private void updateLocation(GeoPoint gps) {
    if (gpsMarker != null) {
      // draw the location of the new position
      gpsMarker.remove();
    }
    MarkerOptions marker = new MarkerOptions();
    marker.position(new LatLng(gps.dlat, gps.dlon));
    marker.title("User").snippet("Estimated Position");
    marker.icon(BitmapDescriptorFactory.fromResource(R.drawable.marker_icon));
    marker.rotation(raw_heading - bearing);
    gpsMarker = mMap.addMarker(marker);

  }

  private void handleBuildingsOnMap() {

    AnyplaceServerAPI.fetchBuildings(AnyplaceLoggerActivity.this, new FetchBuildingsTaskListener() {

      @Override
      public void onSuccess(String result, List<BuildingModel> buildings) {
        if (mClusterManager == null) return;
        List<BuildingModel> collection = new ArrayList<BuildingModel>(buildings);
        mClusterManager.clearItems();
        if (mCurrentBuilding != null)
          collection.remove(mCurrentBuilding);
        mClusterManager.addItems(collection);
        mClusterManager.cluster();
      }

      @Override
      public void onErrorOrCancel(String result) {

      }

    });
  }

  /** Called when we want to clear the map overlays */
  private void clearMap() {
    if (!checkReady()) {
      return;
    }
    mMap.clear();
  }

  @Override
  public void onPause() {
    Log.i(TAG, "onPause");
    super.onPause();

    if (!mIsSamplingActive && positioning != null) {
      positioning.pause();
    }

    if (mFusedLocationClient != null && mLocationCallbackConnected != null) {
      try {
        mFusedLocationClient.removeLocationUpdates(mLocationCallbackConnected);
      } catch (Exception ignored) {}
    }
  }

  @Override
  public void onResume() {
    Log.i(TAG, "onResume");
    super.onResume();
    setUpMapIfNeeded();

    if (!mIsSamplingActive && positioning != null) {
      positioning.resume();
    }

    // Register Direct Hardware Accelerometer, Magnetometer & Gyroscope
    mSensorManager = (SensorManager) getSystemService(Context.SENSOR_SERVICE);
    if (mSensorManager != null) {
      mAccelerometerSensor = mSensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
      mMagnetometerSensor = mSensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD);
      mGyroscopeSensor = mSensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE);
      if (mAccelerometerSensor != null) {
        mSensorManager.registerListener(mHardwareSensorListener, mAccelerometerSensor, SensorManager.SENSOR_DELAY_GAME);
      }
      if (mMagnetometerSensor != null) {
        mSensorManager.registerListener(mHardwareSensorListener, mMagnetometerSensor, SensorManager.SENSOR_DELAY_GAME);
      }
      if (mGyroscopeSensor != null) {
        mSensorManager.registerListener(mHardwareSensorListener, mGyroscopeSensor, SensorManager.SENSOR_DELAY_GAME);
      }
    }

    checkLocationPermission();
    if (mFusedLocationClient != null && mLocationRequest != null && mLocationCallbackConnected != null) {
      try {
        mFusedLocationClient.requestLocationUpdates(mLocationRequest, mLocationCallbackConnected, Looper.getMainLooper());
      } catch (Exception ignored) {}
    }
  }

  @Override
  protected void onStart() {
    super.onStart();

  }

  @Override
  protected void onStop() {
    super.onStop();

    if (mSensorManager != null && mHardwareSensorListener != null) {
      try {
        mSensorManager.unregisterListener(mHardwareSensorListener);
      } catch (Exception ignored) {}
    }

    if (mFusedLocationClient != null && mLocationCallbackConnected != null) {
      try {
        mFusedLocationClient.removeLocationUpdates(mLocationCallbackConnected);
      } catch (Exception ignored) {}
    }
  }

  @Override
  protected void onDestroy() {
    super.onDestroy();

    wifi.unregisterScan(receiverWifi);
  }

  protected void onActivityResult(int requestCode, int resultCode, Intent data) {
    super.onActivityResult(requestCode, resultCode, data);
    switch (requestCode) {
      case SELECT_PLACE_ACTIVITY_RESULT:
        if (resultCode == RESULT_OK) {
          if (data == null) {
            return;
          }

          try {
            int bIndex = data.getIntExtra("bmodel", 0);
            int fIndex = data.getIntExtra("fmodel", 0);
            List<BuildingModel> buildings = AnyplaceCache.getInstance(this).getSpinnerBuildings();
            if (buildings != null && bIndex >= 0 && bIndex < buildings.size()) {
              BuildingModel b = buildings.get(bIndex);
              FloorModel f = null;
              if (b.getFloors() != null && fIndex >= 0 && fIndex < b.getFloors().size()) {
                f = b.getFloors().get(fIndex);
              }
              if (f == null) {
                f = b.getSelectedFloor();
              }

              if (f != null) {
                selectPlaceActivityResult(b, f);
              }
            }
          } catch (Exception ex) {
            Log.e(TAG, "Error handling select place activity result: " + ex.getMessage(), ex);
          }
        } else if (resultCode == RESULT_CANCELED) {
          // CANCELLED
          if (data == null) {
            return;
          }
          String msg = (String) data.getSerializableExtra("message");
          if (msg != null) {
            Toast.makeText(getBaseContext(), msg, Toast.LENGTH_LONG).show();
          }
        }
        break;
      case PREFERENCES_ACTIVITY_RESULT:
        if (resultCode == RESULT_OK) {
          Action result = (Action) data.getSerializableExtra("action");

          switch (result) {
            case REFRESH_BUILDING:

              if (mCurrentBuilding == null) {
                Toast.makeText(getBaseContext(), "Load a map before performing this action!", Toast.LENGTH_SHORT)
                    .show();
                break;
              }

              if (progressBar.getVisibility() == View.VISIBLE) {
                Toast.makeText(getBaseContext(), "Building Loading in progress. Please Wait!", Toast.LENGTH_SHORT)
                    .show();
                break;
              }

              try {

                // clear_floorplans
                File floorsRoot = new File(AnyplaceUtils.getFloorPlansRootFolder(this), mCurrentBuilding.buid);
                // clear radiomaps
                File radiomapsRoot = AnyplaceUtils.getRadioMapsRootFolder(this);
                final String[] radiomaps = radiomapsRoot.list(new FilenameFilter() {

                  @Override
                  public boolean accept(File dir, String filename) {
                    if (filename.startsWith(mCurrentBuilding.buid))
                      return true;
                    else
                      return false;
                  }
                });
                for (int i = 0; i < radiomaps.length; i++) {
                  radiomaps[i] = radiomapsRoot.getAbsolutePath() + File.separator + radiomaps[i];
                }

                DeleteFolderBackgroundTask task = new DeleteFolderBackgroundTask(
                    new DeleteFolderBackgroundTask.DeleteFolderBackgroundTaskListener() {

                      @Override
                      public void onSuccess() {
                        bypassSelectBuildingActivity(mCurrentBuilding, mCurrentBuilding.getSelectedFloor());
                      }
                    }, this, true);
                task.setFiles(floorsRoot);
                task.setFiles(radiomaps);
                task.execute();
              } catch (Exception e) {
                Toast.makeText(getApplicationContext(), e.getMessage(), Toast.LENGTH_SHORT).show();
              }
          }
          break;
        }
        break;
    }
  }

  private void bypassSelectBuildingActivity(final BuildingModel b) {

    if (b != null) {

      if (mIsSamplingActive) {
        Toast.makeText(getBaseContext(), "Invalid during logging.", Toast.LENGTH_LONG).show();
        return;
      }

      // Load Building
      AnyplaceServerAPI.fetchFloors(AnyplaceLoggerActivity.this, b.buid, new FetchFloorsByBuidTaskListener() {

        @Override
        public void onSuccess(String result, List<FloorModel> floors) {

          AnyplaceCache mAnyplaceCache = AnyplaceCache.getInstance(AnyplaceLoggerActivity.this);
          ArrayList<BuildingModel> list = new ArrayList<BuildingModel>(1);
          list.add(b);
          mAnyplaceCache.setSelectedBuildingIndex(0);
          mAnyplaceCache.setSpinnerBuildings(getApplicationContext(), list);

          FloorModel floor = null;
          if (floors != null && !floors.isEmpty()) {
            try {
              if (b.getFloors() != null) {
                b.getFloors().clear();
                b.getFloors().addAll(floors);
              }
            } catch (Exception ignored) {}
            for (FloorModel fm : floors) {
              if ("0".equals(fm.floor_number)) {
                floor = fm;
                break;
              }
            }
            if (floor == null) {
              floor = floors.get(0);
            }
          }

          if (floor != null) {
            bypassSelectBuildingActivity(b, floor);
          } else {
            Toast.makeText(getBaseContext(), "No floors found for this building.", Toast.LENGTH_SHORT).show();
          }
        }

        @Override
        public void onErrorOrCancel(String result) {
          Toast.makeText(getBaseContext(), result, Toast.LENGTH_SHORT).show();

        }
      });
    }
  }

  private void bypassSelectBuildingActivity(final BuildingModel b, final FloorModel f) {
    if (b == null || f == null) {
      return;
    }

    AnyplaceServerAPI.fetchFloorPlan(getApplicationContext(), b.buid, f.floor_number, new FetchFloorPlanTask.FetchFloorPlanTaskListener() {

      @Override
      public void onSuccess(String result, File floor_plan_file) {
        if (progressBar != null) {
          progressBar.setVisibility(View.GONE);
        }
        selectPlaceActivityResult(b, f);
      }

      @Override
      public void onErrorOrCancel(String result) {
        if (progressBar != null) {
          progressBar.setVisibility(View.GONE);
        }
        selectPlaceActivityResult(b, f);
      }

      @Override
      public void onPrepareLongExecute() {
        RelativeLayout layout = findViewById(R.id.loggerView);
        if (progressBar == null) {
          progressBar = new ProgressBar(AnyplaceLoggerActivity.this, null, android.R.attr.progressBarStyleLarge);
          RelativeLayout.LayoutParams params = new RelativeLayout.LayoutParams(100, 100);
          params.addRule(RelativeLayout.CENTER_IN_PARENT);
          layout.addView(progressBar, params);
        }
        progressBar.setVisibility(View.VISIBLE);
      }
    });
  }

  private void loadMapBasicLayer(BuildingModel b, FloorModel f) {
    if (mMap == null || b == null || f == null) {
      return;
    }
    mMap.clear();

    try {
      File destDir = new File(getBaseContext().getExternalFilesDir(null), "floor_plans/" + b.buid + "/" + f.floor_number);
      File pngFile = new File(destDir, "floor_plan.png");
      if (!pngFile.exists()) {
        pngFile = new File(destDir, "tiles_archive.zip");
      }

      if (pngFile.exists() && pngFile.isFile()) {
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(pngFile.getAbsolutePath(), options);

        int maxDim = 2048;
        int inSampleSize = 1;
        if (options.outHeight > maxDim || options.outWidth > maxDim) {
          int heightRatio = Math.round((float) options.outHeight / (float) maxDim);
          int widthRatio = Math.round((float) options.outWidth / (float) maxDim);
          inSampleSize = Math.max(heightRatio, widthRatio);
        }

        BitmapFactory.Options decodeOptions = new BitmapFactory.Options();
        decodeOptions.inSampleSize = Math.max(1, inSampleSize);
        Bitmap bm = BitmapFactory.decodeFile(pngFile.getAbsolutePath(), decodeOptions);

        if (bm != null) {
          try {
            double blLat = 0, blLng = 0, trLat = 0, trLng = 0;
            boolean hasCoords = false;
            if (f.bottom_left_lat != null && !f.bottom_left_lat.isEmpty() &&
                f.bottom_left_lng != null && !f.bottom_left_lng.isEmpty() &&
                f.top_right_lat != null && !f.top_right_lat.isEmpty() &&
                f.top_right_lng != null && !f.top_right_lng.isEmpty()) {
              try {
                blLat = Double.parseDouble(f.bottom_left_lat);
                blLng = Double.parseDouble(f.bottom_left_lng);
                trLat = Double.parseDouble(f.top_right_lat);
                trLng = Double.parseDouble(f.top_right_lng);
                if (Math.abs(trLat - blLat) > 0.00001 && Math.abs(trLng - blLng) > 0.00001) {
                  hasCoords = true;
                }
              } catch (Exception ignored) {}
            }

            if (!hasCoords && b != null && b.getPosition() != null) {
              double centerLat = b.getPosition().latitude;
              double centerLng = b.getPosition().longitude;
              if (centerLat != 0.0 || centerLng != 0.0) {
                blLat = centerLat - 0.0004;
                blLng = centerLng - 0.0004;
                trLat = centerLat + 0.0004;
                trLng = centerLng + 0.0004;
                hasCoords = true;
              }
            }

            if (hasCoords) {
              LatLngBounds bounds = new LatLngBounds(
                  new LatLng(Math.min(blLat, trLat), Math.min(blLng, trLng)),
                  new LatLng(Math.max(blLat, trLat), Math.max(blLng, trLng))
              );

              mMap.addGroundOverlay(new GroundOverlayOptions()
                  .image(BitmapDescriptorFactory.fromBitmap(bm))
                  .positionFromBounds(bounds)
                  .zIndex(0));
              mMap.animateCamera(create3DCameraUpdate(bounds.getCenter(), 19.0f));

              // Automatically trigger fingerprint heatmap overlay from cached server radiomap or local RSS log
              try {
                File cachedServerMap = new File(getBaseContext().getExternalFilesDir(null), "radiomaps/" + b.buid + "/" + f.floor_number + "/indoor-radiomap-mean.txt");
                if (cachedServerMap.exists() && cachedServerMap.length() > 0) {
                  new HeatmapTask().execute(cachedServerMap);
                } else if (folder_path != null && filename_rss != null) {
                  File localRss = new File(folder_path, filename_rss);
                  if (localRss.exists() && localRss.length() > 0) {
                    new HeatmapTask().execute(localRss);
                  }
                }
              } catch (Exception ignored) {}

              return;
            }
          } catch (Exception nfe) {
            Log.e(TAG, "Coordinates parse error: " + nfe.getMessage());
          }
        }
      }

      File tilesDir = new File(destDir, "tiles_archive");
      if (tilesDir.exists() && tilesDir.isDirectory()) {
        mMap.addTileOverlay(
            new TileOverlayOptions().tileProvider(new MapTileProvider(getBaseContext(), b.buid, f.floor_number)).zIndex(0));
      }
    } catch (Exception e) {
      Log.e(TAG, "Error in loadMapBasicLayer: " + e.getMessage(), e);
    }
  }

  private void selectPlaceActivityResult(final BuildingModel b, FloorModel f) {
    if (b == null || f == null || mMap == null) {
      return;
    }

    // set the newly selected floor
    if (b.getFloors() != null && !b.getFloors().isEmpty() && f.floor_number != null) {
      b.setSelectedFloor(f.floor_number);
    }
    mCurrentBuilding = b;
    mCurrentFloor = f;
    if (b.getPosition() != null) {
      curLocation = b.getPosition();
    }
    userIsNearby = false;
    if (textFloor != null) {
      textFloor.setText(f.floor_name != null ? f.floor_name : f.floor_number);
    }

    if (curLocation != null) {
      updateMarker(curLocation);
      updateInfoView();
    }

    loadMapBasicLayer(b, f);
    mMap.animateCamera(create3DCameraUpdate(b.getPosition(), 19.0f), new CancelableCallback() {

      @Override
      public void onFinish() {
        handleBuildingsOnMap();
      }

      @Override
      public void onCancel() {
      }
    });

    // Fetch radiomap from server API and render fingerprint markers & heatmap
    AnyplaceServerAPI.fetchRadioMap(this, b.buid, f.floor_number, b.getLatitudeString(), b.getLongitudeString(), new AnyplaceServerAPI.FetchRadioMapCallback() {
      @Override
      public void onSuccess(File file) {
        if (file != null && file.exists()) {
          new HeatmapTask().execute(file);
        }
      }

      @Override
      public void onError(String error) {
        if (folder_path != null && filename_rss != null) {
          File localRss = new File(folder_path, filename_rss);
          if (localRss.exists() && localRss.length() > 0) {
            new HeatmapTask().execute(localRss);
          }
        }
      }
    });

    class Callback implements DownloadRadioMapListener, PreviousRunningTask {
      boolean progressBarEnabled = false;
      boolean disableSuccess = false;
      static final boolean DEBUG_CALLBACK = false;

      @Override
      public void onSuccess(String result) {

        if (disableSuccess) {
          onErrorOrCancel("");
          return;
        }

        File root;
        try {
          root = AnyplaceUtils.getRadioMapFolder(AnyplaceLoggerActivity.this, mCurrentBuilding.buid,
              mCurrentFloor.floor_number);
          File f = new File(root, AnyplaceUtils.getRadioMapFileName(mCurrentFloor.floor_number));
          if (DEBUG_CALLBACK) {
            Log.d(TAG, "inside the Callback class before heatmaptask");
          }

          new HeatmapTask().execute(f);
        } catch (Exception e) {
        }

        if (AnyplaceDebug.PLAY_STORE) {

          AnyplaceCache mAnyplaceCache = AnyplaceCache.getInstance(AnyplaceLoggerActivity.this);
          mAnyplaceCache.fetchAllFloorsRadiomapsRun(new BackgroundFetchListener() {

            @Override
            public void onSuccess(String result) {
              hideProgressBar();
              if (AnyplaceDebug.DEBUG_MESSAGES) {
                btnTrackme.setBackgroundColor(Color.YELLOW);
              }
            }

            @Override
            public void onProgressUpdate(int progress_current, int progress_total) {
              progressBar.setProgress((int) ((float) progress_current / progress_total * progressBar.getMax()));
            }

            @Override
            public void onErrorOrCancel(String result, ErrorType error) {
              // Do not hide progress bar if previous task is running
              // ErrorType.SINGLE_INSTANCE
              // Do not hide progress bar because a new task will be created
              // ErrorType.CANCELLED
              if (error == ErrorType.EXCEPTION)
                hideProgressBar();
            }

            @Override
            public void onPrepareLongExecute() {
              showProgressBar();
            }

          }, mCurrentBuilding);
        }
      }

      @Override
      public void onErrorOrCancel(String result) {
        if (DEBUG_CALLBACK) {
          Log.d(TAG, "Callback onErrorOrCancel with " + result);
        }
        if (progressBarEnabled) {
          hideProgressBar();
        }
      }

      @Override
      public void onPrepareLongExecute() {
        progressBarEnabled = true;
        showProgressBar();
        // Set a smaller percentage than fetchAllFloorsRadiomapsOfBUID
        int count = (b != null && b.getFloors() != null && !b.getFloors().isEmpty()) ? b.getFloors().size() : 1;
        progressBar.setProgress((int) (1.0f / (count * 2) * progressBar.getMax()));
      }

      @Override
      public void disableSuccess() {
        disableSuccess = true;
      }
    }

    if (downloadRadioMapTaskBuid != null) {
      ((PreviousRunningTask) downloadRadioMapTaskBuid.getCallbackInterface()).disableSuccess();
    }

    downloadRadioMapTaskBuid = new DownloadRadioMapTaskBuid(new Callback(), this, b.getLatitudeString(),
        b.getLongitudeString(), b.buid, f.floor_number, false);

    int currentapiVersion = android.os.Build.VERSION.SDK_INT;
    if (currentapiVersion >= android.os.Build.VERSION_CODES.HONEYCOMB) {
      // Execute task parallel with others and multiple instances of
      // itself
      downloadRadioMapTaskBuid.executeOnExecutor(AsyncTask.THREAD_POOL_EXECUTOR);
    } else {
      downloadRadioMapTaskBuid.execute();
    }
    showHelp("Help",
        "<b>1.</b> Select your floor (using arrows on the right).<br><b>2.</b> Click on the map (to identify your location).");
  }

  @Override
  public void onConfigurationChanged(Configuration newConfig) {
    // prevent orientation change when auto-rotate is enabled on Android OS
    super.onConfigurationChanged(newConfig);
    setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
  }

  // MENUS
  @Override
  public boolean onCreateOptionsMenu(Menu menu) {
    MenuInflater inflater = getMenuInflater();
    inflater.inflate(cy.ac.ucy.cs.anyplace.lib.R.menu.logger, menu);
    return true;
  }

  @Override
  public boolean onPrepareOptionsMenu(Menu menu) {
    return super.onPrepareOptionsMenu(menu);
  }

  @Override
  public boolean onOptionsItemSelected(MenuItem item) {
    switch (item.getItemId()) {
      case R.id.main_menu_upload_rsslog: {
        uploadRSSLog();
        return true;
      }
      case R.id.main_menu_loadmap: {
        // start the activity where the user can select the building
        if (mIsSamplingActive) {
          Toast.makeText(this, "Invalid during logging.", Toast.LENGTH_LONG).show();
          return true;
        }

        // checkLocationPermission();
        // Location currentLocation =
        // LocationServices.FusedLocationApi.getLastLocation(mGoogleApiClient);
        // we must set listener to the get the first location from the API
        // it will trigger the onLocationChanged below when a new location
        // is found or notify the user
        checkLocationPermission();

        mFusedLocationClient.getLastLocation().addOnCompleteListener(new OnCompleteListener<Location>() {
          @Override
          public void onComplete(@NonNull Task<Location> task) {
            final Location currentLocation = task.getResult();
            onLocationChanged(currentLocation);

            Intent placeIntent = new Intent(AnyplaceLoggerActivity.this, SelectBuildingActivity.class);
            Bundle b = new Bundle();
            if (currentLocation != null) {
              b.putString("coordinates_lat", String.valueOf(currentLocation.getLatitude()));
              b.putString("coordinates_lon", String.valueOf(currentLocation.getLongitude()));
            }

            if (mCurrentBuilding == null) {
              b.putSerializable("mode", SelectBuildingActivity.Mode.NEAREST);
            }

            placeIntent.putExtras(b);
            startActivityForResult(placeIntent, SELECT_PLACE_ACTIVITY_RESULT);

          }
        }).addOnFailureListener(new OnFailureListener() {
          @Override
          public void onFailure(@NonNull Exception e) {
            Toast.makeText(getBaseContext(), "No location available at the moment.", Toast.LENGTH_LONG).show();
          }
        });

        return true;
      }
      case R.id.main_menu_clear_logging: {
        resetServerRadioMap();
        return true;
      }

      // Launch preferences
      case R.id.logger_menu_preferences: {
        Intent i = new Intent(this, LoggerPrefs.class);
        startActivityForResult(i, PREFERENCES_ACTIVITY_RESULT);
        return true;
      }
      case R.id.main_menu_preferences: {
        Intent i = new Intent(this, SettingsActivity.class);
        // startActivityForResult(i, PREFERENCES_ACTIVITY_RESULT);
        startActivity(i);
        return true;
      }
      case R.id.main_menu_about: {
        startActivity(new Intent(AnyplaceLoggerActivity.this, AnyplaceAboutActivity.class));
        return true;
      }

      // case R.id.main_menu_exit: {
      // this.finish();
      // System.gc();
      // }
    }
    return false;
  }

  private void updateMarker(LatLng latlng) {
    if (this.marker != null) {
      this.marker.remove();
    }
    this.marker = this.mMap.addMarker(new MarkerOptions().position(latlng).draggable(true)
        .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_RED)));
    curLocation = latlng;
  }

  // update the info view
  private void updateInfoView() {
    LatLng displayLoc = curLocation;
    if (displayLoc == null || (displayLoc.latitude == 0.0 && displayLoc.longitude == 0.0)) {
      if (mCurrentBuilding != null && mCurrentBuilding.getPosition() != null && (mCurrentBuilding.getPosition().latitude != 0.0 || mCurrentBuilding.getPosition().longitude != 0.0)) {
        displayLoc = mCurrentBuilding.getPosition();
      } else if (gpsMarker != null && gpsMarker.getPosition() != null) {
        displayLoc = gpsMarker.getPosition();
      } else if (mMap != null && mMap.getCameraPosition() != null) {
        LatLng target = mMap.getCameraPosition().target;
        if (target != null && (target.latitude != 0.0 || target.longitude != 0.0)) {
          displayLoc = target;
        }
      }
    }

    if (displayLoc != null && (displayLoc.latitude != 0.0 || displayLoc.longitude != 0.0)) {
      curLocation = displayLoc;
    }

    String latStr = (displayLoc != null && (displayLoc.latitude != 0.0 || displayLoc.longitude != 0.0))
        ? String.format("%.6f", displayLoc.latitude) : "N/A";
    String lonStr = (displayLoc != null && (displayLoc.latitude != 0.0 || displayLoc.longitude != 0.0))
        ? String.format("%.6f", displayLoc.longitude) : "N/A";

    StringBuilder sb = new StringBuilder();
    sb.append("Lat[ ").append(latStr).append(" ]");
    sb.append("  Lon[ ").append(lonStr).append(" ]");
    sb.append("\nHeading[ ").append(String.format("%.2f", raw_heading)).append("° ]");
    if (mHasGyroscope) {
      sb.append(String.format("  Gyro[%.2f,%.2f,%.2f]", mGyroscopeMatrix[0], mGyroscopeMatrix[1], mGyroscopeMatrix[2]));
    }
    sb.append("  Status[ ").append(walking ? "Walking" : "Standing").append(" ]");
    sb.append("  Samples[ ").append(mCurrentSamplesTaken).append(" ]");
    mTrackingInfoView.setText(sb.toString());
  }

  /*
   * Gets called whenever there is a change in sensors in positioning
   *
   * @see com.lambrospetrou.anyplace.tracker.Positioning.PositioningListener#
   * onNewPosition()
   */

  private class OrientationListener implements SensorsMain.IOrientationListener {
    @Override
    public void onNewOrientation(float[] values) {
      raw_heading = values[0];
      updateInfoView();
    }
  }

  private class WalkingListener implements MovementDetector.MovementListener {

    @Override
    public void onWalking() {
      walking = true;
      updateInfoView();
    }

    @Override
    public void onStanding() {
      walking = false;
      updateInfoView();
    }

  }

  //
  // The receiver of the result after processing a WiFi ScanResult previously
  // by WiFiReceiver
  //
  public class AnyplaceLoggerReceiver implements LoggerWiFi.Callback {

    public double dist(double lat1, double lon1, double lat2, double lon2) {
      double dLat;
      double dLon;

      int R = 6371; // Km
      dLat = (lat2 - lat1) * Math.PI / 180;
      dLon = (lon2 - lon1) * Math.PI / 180;
      lat1 = lat1 * Math.PI / 180;
      lat2 = lat2 * Math.PI / 180;

      double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
          + Math.sin(dLon / 2) * Math.sin(dLon / 2) * Math.cos(lat1) * Math.cos(lat2);
      double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      double d = R * c;

      return d;

    }

    public double dist(LatLng latlng1, LatLng latlng2) {
      double lat1 = latlng1.latitude;
      double lon1 = latlng1.longitude;
      double lat2 = latlng2.latitude;
      double lon2 = latlng2.longitude;

      return dist(lat1, lon1, lat2, lon2);
    }

    private void draw(LatLng latlng, int sum) {
      CircleOptions options = new CircleOptions();
      options.center(latlng);
      options.radius(0.5 + sum * 0.05);
      options.fillColor(Color.BLUE);
      options.strokeWidth(3);
      // Display above floor image
      options.zIndex(2);
      mMap.addCircle(options);
    }

    @Override
    public void onFinish(LoggerWiFi logger, Function function) {
      if (function == Function.ADD) {
        runOnUiThread(new Runnable() {
          public void run() {
            updateInfoView();
          }
        });
      } else if (function == Function.SAVE) {

        final boolean exceptionOccured = logger.exceptionOccured;
        final String msg = logger.msg;
        final ArrayList<ArrayList<LogRecordMap>> mSamples = logger.mSamples;

        runOnUiThread(new Runnable() {
          @Override
          public void run() {

            if (exceptionOccured) {
              Toast.makeText(AnyplaceLoggerActivity.this, msg, Toast.LENGTH_LONG).show();
              return;
            } else {
              if (!(mSamples == null || mSamples.size() == 0)) {
                ArrayList<LogRecordMap> prevSample = mSamples.get(0);
                int sum = 0;

                for (int i = 1; i < mSamples.size(); i++) {
                  ArrayList<LogRecordMap> records = mSamples.get(i);
                  // double d = dist(prevSample.get(0).lat,
                  // prevSample.get(0).lng,
                  // records.get(0).lat, records.get(0).lng);

                  if (records.get(0).walking) {
                    LatLng latlng = new LatLng(prevSample.get(0).lat, prevSample.get(0).lng);
                    draw(latlng, sum);
                    prevSample = records;
                  } else {
                    if (sum < 10)
                      sum += 1;
                  }
                }

                LatLng latlng = new LatLng(prevSample.get(0).lat, prevSample.get(0).lng);
                draw(latlng, sum);
              }

              Toast.makeText(AnyplaceLoggerActivity.this, mSamples.size() + " Samples Recorded Successfully!",
                  Toast.LENGTH_LONG).show();
            }

            mCurrentSamplesTaken -= mSamples.size();
            if (mSamplingProgressDialog != null) {
              mSamplingProgressDialog.dismiss();
              mSamplingProgressDialog = null;
              enableRecordButton();
              showHelp("Help", "When you are done logging, click \"Menu\" -> \"Upload\"");
            }

          }
        });

      }

    }
  }

  //
  // The WifiReceiver is responsible to Receive Access Points results
  //
  private class SimpleWifiReceiver extends WifiReceiver {

    @Override
    public void onReceive(Context c, Intent intent) {

      try {
        if (intent == null || c == null || intent.getAction() == null)
          return;

        List<ScanResult> wifiList = wifi.getScanResults();
        scanResults.setText("AP : " + wifiList.size());

        // If we are not in an active sampling session we have to skip
        // this intent
        if (!mIsSamplingActive)
          return;

        if (wifiList.size() > 0 && curLocation != null) {
          mCurrentSamplesTaken++;
          logger.add(wifiList, curLocation.latitude + "," + curLocation.longitude, raw_heading, walking);
          updateInfoView();
        }
      } catch (RuntimeException e) {
        Log.e(TAG, "WiFi scan RuntimeException: " + e.getMessage(), e);
        return;
      }
    }
  }

  //
  // Method used to print pop up message to user
  //
  protected void toastPrint(String textMSG, int duration) {
    Toast.makeText(this, textMSG, duration).show();
  }

  //
  // Record button pressed. Get samples number from preferences
  //
  private void btnRecordingInfo() {

    if (mIsSamplingActive) {
      mIsSamplingActive = false;
      mSamplingProgressDialog = new ProgressDialog(AnyplaceLoggerActivity.this);
      mSamplingProgressDialog.setProgressStyle(ProgressDialog.STYLE_SPINNER);
      mSamplingProgressDialog.setMessage("Saving...");
      mSamplingProgressDialog.setCancelable(false);
      mSamplingProgressDialog.show();

      saveRecordingToLine(curLocation);

    } else {
      startRecordingInfo();
    }
  }

  private void startRecordingInfo() {

    // avoid recording when no floor has been selected
    if (mCurrentFloor == null || !mCurrentFloor.isFloorValid()) {
      Toast.makeText(getBaseContext(), "Load map before recording...", Toast.LENGTH_SHORT).show();
      return;
    }

    // avoid recording when no position has been clicked
    if (curLocation == null) {
      Toast.makeText(getBaseContext(), "Click a position on the map before recording...", Toast.LENGTH_SHORT).show();
      return;
    }

    if (mCurrentBuilding == null) {
      Toast.makeText(getBaseContext(), "Select a building before recording...", Toast.LENGTH_SHORT).show();
      return;
    }

    // Mark user as nearby — the logger is used on-site by design
    userIsNearby = true;

    File appStorageDir = getExternalFilesDir(null);
    String defaultFolder = (appStorageDir != null) ? appStorageDir.getAbsolutePath() : getFilesDir().getAbsolutePath();

    folder_path = preferences.getString("folder_browser", defaultFolder);
    File fDir = new File(folder_path);
    if (!fDir.exists()) {
      fDir.mkdirs();
    }
    if (!fDir.canWrite()) {
      folder_path = defaultFolder;
      fDir = new File(folder_path);
      fDir.mkdirs();
      SharedPreferences.Editor ed = preferences.edit();
      ed.putString("folder_browser", defaultFolder);
      ed.commit();
    }

    filename_rss = preferences.getString("filename_log", "anyplace_rss.txt");
    if (filename_rss == null || filename_rss.isEmpty() || filename_rss.equals("n/a")) {
      filename_rss = "anyplace_rss.txt";
      SharedPreferences.Editor ed = preferences.edit();
      ed.putString("filename_log", filename_rss);
      ed.commit();
    }

    disableRecordButton();
    // start the TASK
    mCurrentSamplesTaken = 0;
    mIsSamplingActive = true;
    updateInfoView();
    Toast.makeText(getBaseContext(), "Sampling started! Stand at position or walk, then tap Stop to save samples.", Toast.LENGTH_LONG).show();
  }

  private void saveRecordingToLine(LatLng latlng) {
    if (latlng == null || mCurrentFloor == null || mCurrentBuilding == null) {
      if (mSamplingProgressDialog != null) {
        mSamplingProgressDialog.dismiss();
        mSamplingProgressDialog = null;
      }
      enableRecordButton();
      Toast.makeText(this, "Cannot save: missing location or building data.", Toast.LENGTH_SHORT).show();
      return;
    }

    logger.save(latlng.latitude + "," + latlng.longitude, folder_path, filename_rss, mCurrentFloor.floor_number,
        mCurrentBuilding.buid);

    if (mMap != null) {
      mMap.addCircle(new CircleOptions()
          .center(latlng)
          .radius(1.2)
          .strokeColor(android.graphics.Color.RED)
          .fillColor(android.graphics.Color.argb(200, 255, 0, 0))
          .strokeWidth(3.0f)
          .zIndex(10));
    }

    Toast.makeText(this, "Saved " + mCurrentSamplesTaken + " consecutive WiFi samples!", Toast.LENGTH_SHORT).show();

    if (mSamplingProgressDialog != null) {
      mSamplingProgressDialog.dismiss();
      mSamplingProgressDialog = null;
    }
    enableRecordButton();

    // Refresh and render fingerprint markers immediately after saving recording
    try {
      if (folder_path != null && filename_rss != null) {
        File localRss = new File(folder_path, filename_rss);
        new HeatmapTask().execute(localRss);
      }
    } catch (Exception ignored) {}
  }

  // ****************************************************************
  // Listener that handles clicks on map
  // ****************************************************************

  @Override
  public void onMapClick(LatLng latlng) {

    if (mIsSamplingActive) {
      saveRecordingToLine(latlng);
    }

    updateMarker(latlng);
    updateInfoView();

    if (!mIsSamplingActive) {
      showHelp("Help",
          "<b>1.</b> Please click \"START\"<br><b>2.</b> Then walk around the building in staight lines.<br><b>3.</b> Re-identify your location on the map every time you turn.");
    }

  }

  // ***************************************************************************************
  // UPLOAD RSS TASK
  // ***************************************************************************************

  private void uploadRSSLog() {
    synchronized (upInProgressLock) {
      if (upInProgress) {
        Toast.makeText(getApplicationContext(), "Upload in progress...", Toast.LENGTH_SHORT).show();
        return;
      }
    }

    if (folder_path == null || filename_rss == null) {
      Toast.makeText(getApplicationContext(), "No RSS log file to upload.", Toast.LENGTH_SHORT).show();
      return;
    }

    startUploadTask(folder_path + File.separator + filename_rss);
  }

  private void resetServerRadioMap() {
    new AlertDialog.Builder(this)
        .setTitle("Reset Server WiFi Data")
        .setMessage("Are you sure you want to delete and clear all WiFi data from the server?")
        .setPositiveButton("Clear / Delete", new DialogInterface.OnClickListener() {
          @Override
          public void onClick(DialogInterface dialog, int which) {
            AnyplaceServerAPI.resetServerRadioMap(AnyplaceLoggerActivity.this, new AnyplaceServerAPI.ResetRadioMapCallback() {
              @Override
              public void onSuccess(String message) {
                Toast.makeText(AnyplaceLoggerActivity.this, message, Toast.LENGTH_LONG).show();
                if (mCurrentBuilding != null && mCurrentFloor != null) {
                  loadMapBasicLayer(mCurrentBuilding, mCurrentFloor);
                }
              }

              @Override
              public void onError(String error) {
                Toast.makeText(AnyplaceLoggerActivity.this, "Error: " + error, Toast.LENGTH_LONG).show();
              }
            });
          }
        })
        .setNegativeButton("Cancel", null)
        .show();
  }

  private void startUploadTask(final String file_path) {
    upInProgress = true;
    final File file = new File(file_path);
    if (!file.exists() || file.length() == 0) {
      upInProgress = false;
      Toast.makeText(getApplicationContext(), "No RSS log records captured to upload!", Toast.LENGTH_SHORT).show();
      return;
    }

    AnyplaceServerAPI.uploadRSSLog(this, file, new AnyplaceServerAPI.UploadRSSCallback() {
      @Override
      public void onSuccess(String result) {
        upInProgress = false;
        file.delete();

        AlertDialog.Builder builder = new AlertDialog.Builder(AnyplaceLoggerActivity.this);
        builder.setTitle("Data Sent Successfully!");
        if (mCurrentBuilding == null)
          builder.setMessage("Data is sent success!\nVerified by Anyplace Server: " + result);
        else
          builder.setMessage("Data is sent success for building " + mCurrentBuilding.name + "!\nVerified by Anyplace Server: " + result);

        builder.setCancelable(false).setPositiveButton("OK", new DialogInterface.OnClickListener() {
          public void onClick(DialogInterface dialog, int id) {
            dialog.dismiss();
          }
        });
        AlertDialog alert = builder.create();
        alert.show();
      }

      @Override
      public void onError(String result) {
        upInProgress = false;
        AlertDialog.Builder builder = new AlertDialog.Builder(AnyplaceLoggerActivity.this);
        builder.setTitle("Upload Error");
        builder.setMessage("Failed to send RSS log data to server:\n" + result);
        builder.setPositiveButton("OK", null);
        builder.show();
      }
    });
  }

  private void showProgressBar() {
    progressBar.setVisibility(View.VISIBLE);
  }

  private void hideProgressBar() {
    progressBar.setVisibility(View.GONE);
  }

  // *****************************************************************************
  // HELPERS
  // *****************************************************************************

  private void enableRecordButton() {
    btnRecord.setText("Start WiFi Recording");
    btnRecord.setCompoundDrawablesWithIntrinsicBounds(android.R.drawable.presence_invisible, 0, 0, 0);
  }

  private void disableRecordButton() {
    btnRecord.setCompoundDrawablesWithIntrinsicBounds(android.R.drawable.presence_online, 0, 0, 0);
    btnRecord.setText("Stop WiFi Recording");
  }

  @Override
  public void onSharedPreferenceChanged(SharedPreferences sharedPreferences, String key) {
    // TODO Auto-generated method stub

    if (key.equals("walk_bar")) {
      int sensitivity = sharedPreferences.getInt("walk_bar", 26);
      int max = Integer.parseInt(getResources().getString(R.string.walk_bar_max));
      MovementDetector.setSensitivity(max - sensitivity);
    } else if (key.equals("samples_interval")) {
      wifi.startScan(sharedPreferences.getString("samples_interval", "30000"));
    }

  }

  private void showHelp(String title, String message) {
    AlertDialog.Builder adb = new AlertDialog.Builder(this);
    LayoutInflater adbInflater = LayoutInflater.from(this);
    View eulaLayout = adbInflater.inflate(cy.ac.ucy.cs.anyplace.lib.R.layout.info_window_help, null);
    final CheckBox dontShowAgain = (CheckBox) eulaLayout.findViewById(R.id.skip);
    adb.setView(eulaLayout);
    adb.setTitle(Html.fromHtml(title));
    adb.setMessage(Html.fromHtml(message));
    adb.setPositiveButton("Ok", new DialogInterface.OnClickListener() {
      public void onClick(DialogInterface dialog, int which) {
        SharedPreferences.Editor editor = preferences.edit();
        editor.putBoolean("skipHelpMessage", dontShowAgain.isChecked());
        editor.commit();
        return;
      }
    });

    Boolean skipMessage = preferences.getBoolean("skipHelpMessage", false);
    if (!skipMessage)
      adb.show();
  }

  private class HeatmapTask extends AsyncTask<File, Integer, List<LatLng>> {
    private static final boolean DEBUG = false;

    public HeatmapTask() {

    }

    private void parseRadiomapFile(File targetFile, List<LatLng> list) {
      if (targetFile == null || !targetFile.exists() || targetFile.length() == 0) return;
      try {
        java.io.BufferedReader br = new java.io.BufferedReader(new java.io.FileReader(targetFile));
        String line;
        while ((line = br.readLine()) != null) {
          if (line.startsWith("#") || line.trim().isEmpty()) continue;
          String[] tokens = line.trim().split("[,\\s]+");
          try {
            if (tokens.length >= 3 && tokens[0].length() > 9) {
              double lat = Double.parseDouble(tokens[1]);
              double lng = Double.parseDouble(tokens[2]);
              list.add(new LatLng(lat, lng));
            } else if (tokens.length >= 2) {
              double lat = Double.parseDouble(tokens[0]);
              double lng = Double.parseDouble(tokens[1]);
              list.add(new LatLng(lat, lng));
            }
          } catch (Exception ignored) {}
        }
        br.close();
      } catch (Exception e) {
        Log.e(TAG, "Error parsing radiomap file: " + e.getMessage());
      }
    }

    @Override
    protected List<LatLng> doInBackground(File... params) {
      List<LatLng> list = new ArrayList<>();

      // 1. Read from provided radiomap file parameter
      File primaryFile = null;
      if (params != null && params.length > 0 && params[0] != null) {
        primaryFile = params[0];
        parseRadiomapFile(primaryFile, list);
      }

      // 2. Read from cached server radiomap file (indoor-radiomap-mean.txt)
      if (mCurrentBuilding != null && mCurrentFloor != null) {
        try {
          File cachedServerMap = new File(getBaseContext().getExternalFilesDir(null), "radiomaps/" + mCurrentBuilding.buid + "/" + mCurrentFloor.floor_number + "/indoor-radiomap-mean.txt");
          if (cachedServerMap.exists() && !cachedServerMap.equals(primaryFile)) {
            parseRadiomapFile(cachedServerMap, list);
          }
        } catch (Exception ignored) {}
      }

      // 3. Read from local anyplace_rss.txt
      if (folder_path != null && filename_rss != null) {
        try {
          File localRss = new File(folder_path, filename_rss);
          if (localRss.exists() && !localRss.equals(primaryFile)) {
            parseRadiomapFile(localRss, list);
          }
        } catch (Exception ignored) {}
      }

      return list;
    }

    @Override
    protected void onPostExecute(List<LatLng> result) {
      if (result == null || result.isEmpty()) {
        Log.d(TAG, "No fingerprint radiomap records available for display.");
        return;
      }

      // Clear existing circles and tile overlay to avoid duplication
      if (mHeatmapOverlay != null) {
        mHeatmapOverlay.remove();
        mHeatmapOverlay = null;
      }
      for (Circle c : mFingerprintCircles) {
        if (c != null) {
          c.remove();
        }
      }
      mFingerprintCircles.clear();

      // Draw bright cyan/blue fingerprint location circles on Google Map for all sample points
      if (mMap != null) {
        for (LatLng latLng : result) {
          if (latLng != null) {
            Circle circle = mMap.addCircle(new CircleOptions()
                .center(latLng)
                .radius(1.0)
                .strokeColor(android.graphics.Color.rgb(0, 180, 255))
                .fillColor(android.graphics.Color.argb(220, 0, 150, 255))
                .strokeWidth(3.0f)
                .zIndex(10));
            mFingerprintCircles.add(circle);
          }
        }

        try {
          List<WeightedLatLng> weightedList = new ArrayList<>();
          for (LatLng latLng : result) {
            weightedList.add(new WeightedLatLng(latLng));
          }

          int[] colors = {
              android.graphics.Color.rgb(0, 150, 255),  // Deep Blue
              android.graphics.Color.rgb(0, 230, 255),  // Bright Cyan
              android.graphics.Color.rgb(50, 255, 100), // Lime Green
              android.graphics.Color.rgb(255, 200, 0)   // Yellow
          };
          float[] startPoints = { 0.2f, 0.5f, 0.8f, 1.0f };
          com.google.maps.android.heatmaps.Gradient gradient = new com.google.maps.android.heatmaps.Gradient(colors, startPoints);

          mProvider = new HeatmapTileProvider.Builder()
              .weightedData(weightedList)
              .gradient(gradient)
              .radius(35)
              .opacity(0.75)
              .build();

          mHeatmapOverlay = mMap.addTileOverlay(new TileOverlayOptions().tileProvider(mProvider).zIndex(1));
        } catch (Exception e) {
          Log.e(TAG, "Error displaying heatmap tile overlay: " + e.getMessage());
        }
      }
    }

  }

  interface PreviousRunningTask {
    void disableSuccess();
  }
}
