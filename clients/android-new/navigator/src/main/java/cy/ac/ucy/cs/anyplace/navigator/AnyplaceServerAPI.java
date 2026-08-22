package cy.ac.ucy.cs.anyplace.navigator;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import cy.ac.ucy.cs.anyplace.lib.android.cache.AnyplaceCache;
import cy.ac.ucy.cs.anyplace.lib.android.nav.BuildingModel;
import cy.ac.ucy.cs.anyplace.lib.android.nav.FloorModel;
import cy.ac.ucy.cs.anyplace.lib.android.nav.PoisModel;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchBuildingsTask.FetchBuildingsTaskListener;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchFloorsByBuidTask.FetchFloorsByBuidTaskListener;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchFloorPlanTask.FetchFloorPlanTaskListener;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchPoisByBuidTask;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

public class AnyplaceServerAPI {
    private static final String TAG = "AnyplaceServerAPI";
    public static final String SERVER_HOST = "ap.cs.ucy.ac.cy";
    public static final String SERVER_PORT = "44";
    public static final String BASE_URL = "https://ap.cs.ucy.ac.cy:44/api";
    public static final String ACCESS_TOKEN = "apLocal_32fcXaEx8C9p7SyVyll4azWVBzLmVgF503dkiHO1kWPGItK9pXeOxdQC5eZB3KY5qAzvAlv6lrCNZaypMkiCwlzCxbETqrVkhezGnJ4TUyadGXDmuahcVVX9gdY6UficdgFX27mj3t9wKghRe8IVsQMJibHsAOry2xrAM0ACmpXmSjlvyrZk0x6q8rzHvmqhcykScHH4r3IW1M3EjKt7Q0eWlmZwoFzvjFuynYGK0Yifz3hkIZmdkY7JkiNMPNRTJ6bCy2lTPmcfkKrK54YQWV3CSkILCogT8qhKmDXyQHmekefHnIjkuUeel1j7RHQPUxwJkyTdbKaG7ZgXlgg4UFfdR6Lkn6PvbqtFFv2ciKpu6gcRPPp3sR67JTofZYWB1naocPdKrPrNMnoauarFlEAD6DBDY9910LF3QMg3eh7lMpbeBrCQWYucNFQEaEZh3sqH8OiKbplaQ0fr04oz1rIr7ycxdrXFmZ3K590EG0ZkutRmKu4Iap";

    private static final OkHttpClient client = new OkHttpClient.Builder()
            .connectTimeout(45, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .writeTimeout(45, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build();

    public static void fetchBuildings(final Context ctx, final FetchBuildingsTaskListener listener) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final List<BuildingModel> buildings = new ArrayList<>();
                try {
                    JSONObject jsonReq = new JSONObject();
                    jsonReq.put("access_token", ACCESS_TOKEN);

                    RequestBody body = RequestBody.create(jsonReq.toString(), MediaType.parse("application/json; charset=utf-8"));
                    Request request = new Request.Builder()
                            .url(BASE_URL + "/mapping/space/public")
                            .post(body)
                            .build();

                    Response response = client.newCall(request).execute();
                    String respStr = response.body() != null ? response.body().string() : "";

                    JSONObject json = new JSONObject(respStr);
                    JSONArray spaces = null;
                    if (json.has("spaces")) {
                        spaces = json.getJSONArray("spaces");
                    } else if (json.has("buildings")) {
                        spaces = new JSONArray(json.getString("buildings"));
                    }

                    if (spaces != null) {
                        for (int i = 0; i < spaces.length(); i++) {
                            JSONObject obj = spaces.getJSONObject(i);
                            BuildingModel b = new BuildingModel();
                            b.buid = obj.optString("buid");
                            b.name = obj.optString("name");
                            b.setPosition(obj.optString("coordinates_lat"), obj.optString("coordinates_lon"));
                            buildings.add(b);
                        }
                        Collections.sort(buildings);
                        AnyplaceCache.getInstance(ctx).setSpinnerBuildings(ctx, buildings);

                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                if (listener != null) {
                                    listener.onSuccess("Successfully fetched buildings", buildings);
                                }
                            }
                        });
                        return;
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error fetching buildings: " + e.getMessage(), e);
                }

                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        if (listener != null) {
                            listener.onErrorOrCancel("Failed to fetch buildings");
                        }
                    }
                });
            }
        }).start();
    }

    public static void fetchFloors(final Context ctx, final String buid, final FetchFloorsByBuidTaskListener listener) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final List<FloorModel> floors = new ArrayList<>();
                try {
                    JSONObject jsonReq = new JSONObject();
                    jsonReq.put("access_token", ACCESS_TOKEN);
                    jsonReq.put("buid", buid);

                    RequestBody body = RequestBody.create(jsonReq.toString(), MediaType.parse("application/json; charset=utf-8"));
                    Request request = new Request.Builder()
                            .url(BASE_URL + "/mapping/floor/all")
                            .post(body)
                            .build();

                    Response response = client.newCall(request).execute();
                    String respStr = response.body() != null ? response.body().string() : "";

                    JSONObject json = new JSONObject(respStr);
                    if (json.has("floors")) {
                        JSONArray array = json.getJSONArray("floors");
                        for (int i = 0; i < array.length(); i++) {
                            JSONObject obj = array.getJSONObject(i);
                            FloorModel f = new FloorModel();
                            f.buid = obj.optString("buid");
                            f.floor_name = obj.optString("floor_name");
                            f.floor_number = obj.optString("floor_number");
                            f.description = obj.optString("description");
                            f.bottom_left_lat = obj.optString("bottom_left_lat");
                            f.bottom_left_lng = obj.optString("bottom_left_lng");
                            f.top_right_lat = obj.optString("top_right_lat");
                            f.top_right_lng = obj.optString("top_right_lng");
                            floors.add(f);
                        }
                        Collections.sort(floors);
                        BuildingModel selectedB = AnyplaceCache.getInstance(ctx).getSelectedBuilding();
                        if (selectedB != null && selectedB.buid.equals(buid)) {
                            selectedB.getFloors().clear();
                            selectedB.getFloors().addAll(floors);
                        }
                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                if (listener != null) {
                                    listener.onSuccess("Successfully fetched floors", floors);
                                }
                            }
                        });
                        return;
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error fetching floors: " + e.getMessage(), e);
                }

                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        if (listener != null) {
                            listener.onErrorOrCancel("Failed to fetch floors");
                        }
                    }
                });
            }
        }).start();
    }

    public static void fetchFloorPlan(final Context ctx, final String buid, final String floor_number, final FetchFloorPlanTaskListener listener) {
        if (listener != null) {
            new Handler(Looper.getMainLooper()).post(new Runnable() {
                @Override
                public void run() {
                    listener.onPrepareLongExecute();
                }
            });
        }

        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    JSONObject jsonReq = new JSONObject();
                    jsonReq.put("access_token", ACCESS_TOKEN);

                    RequestBody body = RequestBody.create(jsonReq.toString(), MediaType.parse("application/json; charset=utf-8"));
                    Request request = new Request.Builder()
                            .url(BASE_URL + "/floorplans64/" + buid + "/" + floor_number)
                            .post(body)
                            .build();

                    Response response = client.newCall(request).execute();
                    String rawResp = response.body() != null ? response.body().string() : "";
                    if (rawResp.startsWith("\"")) {
                        rawResp = rawResp.substring(1);
                    }
                    if (rawResp.endsWith("\"")) {
                        rawResp = rawResp.substring(0, rawResp.length() - 1);
                    }
                    rawResp = rawResp.trim();

                    if (!rawResp.isEmpty() && !rawResp.startsWith("{")) {
                        try {
                            byte[] imageBytes = Base64.decode(rawResp, Base64.DEFAULT);
                            File destDir = new File(ctx.getExternalFilesDir(null), "floor_plans/" + buid + "/" + floor_number);
                            destDir.mkdirs();

                            final File pngFile = new File(destDir, "floor_plan.png");
                            FileOutputStream fos = new FileOutputStream(pngFile);
                            fos.write(imageBytes);
                            fos.close();

                            final File zipFile = new File(destDir, "tiles_archive.zip");
                            FileOutputStream zipFos = new FileOutputStream(zipFile);
                            zipFos.write(imageBytes);
                            zipFos.close();

                            File okFile = new File(destDir, "ok.txt");
                            FileWriter fw = new FileWriter(okFile);
                            fw.write("ok;version:0;");
                            fw.close();

                            new Handler(Looper.getMainLooper()).post(new Runnable() {
                                @Override
                                public void run() {
                                    if (listener != null) {
                                        listener.onSuccess("Successfully fetched floor plan", zipFile);
                                    }
                                }
                            });
                            return;
                        } catch (Exception b64ex) {
                            Log.e(TAG, "Base64 decode error: " + b64ex.getMessage());
                        }
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error fetching floor plan: " + e.getMessage(), e);
                }

                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        if (listener != null) {
                            listener.onErrorOrCancel("Failed to download floor plan");
                        }
                    }
                });
            }
        }).start();
    }

    public static void fetchPoisByBuid(final Context ctx, final String buid, final FetchPoisByBuidTask.FetchPoisListener listener) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final Map<String, PoisModel> poisMap = new HashMap<>();
                try {
                    JSONObject jsonReq = new JSONObject();
                    jsonReq.put("access_token", ACCESS_TOKEN);
                    jsonReq.put("buid", buid);

                    RequestBody body = RequestBody.create(jsonReq.toString(), MediaType.parse("application/json; charset=utf-8"));
                    Request request = new Request.Builder()
                            .url(BASE_URL + "/mapping/pois/space/all")
                            .post(body)
                            .build();

                    Response response = client.newCall(request).execute();
                    String respStr = response.body() != null ? response.body().string() : "";

                    JSONObject json = new JSONObject(respStr);
                    if (json.has("pois")) {
                        JSONArray array = json.getJSONArray("pois");
                        for (int i = 0; i < array.length(); i++) {
                            JSONObject obj = array.getJSONObject(i);
                            if ("None".equalsIgnoreCase(obj.optString("pois_type"))) {
                                continue;
                            }
                            PoisModel poi = new PoisModel();
                            poi.lat = obj.optString("coordinates_lat");
                            poi.lng = obj.optString("coordinates_lon");
                            poi.buid = obj.optString("buid");
                            poi.floor_name = obj.optString("floor_name");
                            poi.floor_number = obj.optString("floor_number");
                            poi.description = obj.optString("description");
                            poi.name = obj.optString("name");
                            poi.pois_type = obj.optString("pois_type");
                            poi.puid = obj.optString("puid");
                            if (obj.has("is_building_entrance")) {
                                poi.is_building_entrance = obj.optBoolean("is_building_entrance");
                            }
                            poisMap.put(poi.puid, poi);
                        }

                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                if (listener != null) {
                                    listener.onSuccess("Successfully fetched POIs", poisMap);
                                }
                            }
                        });
                        return;
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error fetching POIs: " + e.getMessage(), e);
                }

                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        if (listener != null) {
                            listener.onErrorOrCancel("Failed to fetch POIs");
                        }
                    }
                });
            }
        }).start();
    }

    public static void fetchNavRouteXY(final Context ctx, final String buid, final String poid, final String lat, final String lng, final String floor, final cy.ac.ucy.cs.anyplace.lib.android.tasks.NavIndoorTask.NavRouteListener listener) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final List<cy.ac.ucy.cs.anyplace.lib.android.nav.PoisNav> mPuids = new ArrayList<>();
                try {
                    JSONObject jsonReq = new JSONObject();
                    jsonReq.put("access_token", ACCESS_TOKEN);
                    jsonReq.put("buid", buid);
                    jsonReq.put("pois_to", poid);
                    jsonReq.put("coordinates_lat", lat);
                    jsonReq.put("coordinates_lon", lng);
                    jsonReq.put("floor_number", floor);

                    RequestBody body = RequestBody.create(jsonReq.toString(), MediaType.parse("application/json; charset=utf-8"));
                    Request request = new Request.Builder()
                            .url(BASE_URL + "/navigation/route/coordinates")
                            .post(body)
                            .build();

                    Response response = client.newCall(request).execute();
                    String respStr = response.body() != null ? response.body().string() : "";

                    JSONObject json = new JSONObject(respStr);
                    if (json.has("status") && json.getString("status").equalsIgnoreCase("error")) {
                        final String msg = json.optString("message", "Error calculating route");
                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                if (listener != null) listener.onNavRouteErrorOrCancel(msg);
                            }
                        });
                        return;
                    }

                    if (json.has("pois")) {
                        JSONArray pois = json.getJSONArray("pois");
                        for (int i = 0; i < pois.length(); i++) {
                            JSONObject cp = pois.getJSONObject(i);
                            cy.ac.ucy.cs.anyplace.lib.android.nav.PoisNav navp = new cy.ac.ucy.cs.anyplace.lib.android.nav.PoisNav();
                            navp.lat = cp.optString("lat");
                            navp.lon = cp.optString("lon");
                            navp.puid = cp.optString("puid");
                            navp.buid = cp.optString("buid");
                            navp.floor_number = cp.optString("floor_number");
                            mPuids.add(navp);
                        }

                        if (mPuids.isEmpty()) {
                            new Handler(Looper.getMainLooper()).post(new Runnable() {
                                @Override
                                public void run() {
                                    if (listener != null) listener.onNavRouteErrorOrCancel("No valid path exists to the POI selected!");
                                }
                            });
                            return;
                        }

                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                if (listener != null) listener.onNavRouteSuccess("Successfully plotted navigation route!", mPuids);
                            }
                        });
                        return;
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in fetchNavRouteXY: " + e.getMessage(), e);
                }

                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        if (listener != null) listener.onNavRouteErrorOrCancel("Failed to calculate navigation route.");
                    }
                });
            }
        }).start();
    }

    public static void downloadRadioMapForFloor(final Context ctx, final String buid, final String floor_number, final cy.ac.ucy.cs.anyplace.lib.android.tasks.DownloadRadioMapTaskBuid.DownloadRadioMapListener listener) {
        if (listener != null) {
            new Handler(Looper.getMainLooper()).post(new Runnable() {
                @Override
                public void run() {
                    listener.onPrepareLongExecute();
                }
            });
        }

        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    File root = cy.ac.ucy.cs.anyplace.lib.android.utils.AnyplaceUtils.getRadioMapFolder(ctx, buid, floor_number);
                    File okFile = new File(root, "ok.txt");
                    File meanFile = new File(root, cy.ac.ucy.cs.anyplace.lib.android.utils.AnyplaceUtils.getRadioMapFileName(floor_number));

                    if (okFile.exists() && meanFile.exists() && meanFile.length() > 0) {
                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                if (listener != null) listener.onSuccess("Radio map read from cache.");
                            }
                        });
                        return;
                    }

                    BuildingModel b = AnyplaceCache.getInstance(ctx).getSelectedBuilding();
                    String lat = b != null ? b.getLatitudeString() : "0";
                    String lon = b != null ? b.getLongitudeString() : "0";

                    JSONObject jsonReq = new JSONObject();
                    jsonReq.put("access_token", ACCESS_TOKEN);
                    jsonReq.put("buid", buid);
                    jsonReq.put("floor_number", floor_number);
                    jsonReq.put("floor", floor_number);
                    jsonReq.put("coordinates_lat", lat);
                    jsonReq.put("coordinates_lon", lon);

                    RequestBody body = RequestBody.create(jsonReq.toString(), MediaType.parse("application/json; charset=utf-8"));
                    Request request = new Request.Builder()
                            .url(BASE_URL + "/radiomap/floor")
                            .post(body)
                            .build();

                    Response response = client.newCall(request).execute();
                    String respStr = response.body() != null ? response.body().string() : "";

                    if (respStr.startsWith("{")) {
                        JSONObject resObj = new JSONObject(respStr);
                        if (resObj.optString("status").equals("success")) {
                            final String mapUrl = resObj.optString("map_url_mean");
                            if (mapUrl != null && !mapUrl.isEmpty()) {
                                String downloadUrl = mapUrl;
                                if (downloadUrl.contains("/radiomaps_frozen/")) {
                                    int idx = downloadUrl.indexOf("/radiomaps_frozen/");
                                    downloadUrl = BASE_URL + downloadUrl.substring(idx);
                                }
                                Request dlReq = new Request.Builder()
                                        .url(downloadUrl)
                                        .post(RequestBody.create("{}".getBytes(), MediaType.parse("application/json")))
                                        .build();
                                Response dlResp = client.newCall(dlReq).execute();
                                if (dlResp.isSuccessful() && dlResp.body() != null) {
                                    root.mkdirs();
                                    FileOutputStream fos = new FileOutputStream(meanFile);
                                    fos.write(dlResp.body().bytes());
                                    fos.close();

                                    FileWriter okFw = new FileWriter(okFile);
                                    okFw.write("ok;version:0;");
                                    okFw.close();

                                    new Handler(Looper.getMainLooper()).post(new Runnable() {
                                        @Override
                                        public void run() {
                                            if (listener != null) listener.onSuccess("Successfully downloaded radiomap!");
                                        }
                                    });
                                    return;
                                }
                            }
                        } else if (resObj.has("status") && "error".equalsIgnoreCase(resObj.getString("status"))) {
                            final String msg = resObj.optString("message", "No radiomap for this floor");
                            new Handler(Looper.getMainLooper()).post(new Runnable() {
                                @Override
                                public void run() {
                                    if (listener != null) listener.onErrorOrCancel(msg);
                                }
                            });
                            return;
                        }
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error downloading radiomap: " + e.getMessage(), e);
                }

                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        if (listener != null) listener.onErrorOrCancel("No radiomap found for this floor.");
                    }
                });
            }
        }).start();
    }
}
