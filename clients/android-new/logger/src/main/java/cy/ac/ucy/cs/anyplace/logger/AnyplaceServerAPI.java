package cy.ac.ucy.cs.anyplace.logger;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.TimeUnit;

import cy.ac.ucy.cs.anyplace.lib.android.cache.AnyplaceCache;
import cy.ac.ucy.cs.anyplace.lib.android.nav.BuildingModel;
import cy.ac.ucy.cs.anyplace.lib.android.nav.FloorModel;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchBuildingsTask.FetchBuildingsTaskListener;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchFloorsByBuidTask.FetchFloorsByBuidTaskListener;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

import android.util.Base64;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileWriter;
import cy.ac.ucy.cs.anyplace.lib.android.tasks.FetchFloorPlanTask.FetchFloorPlanTaskListener;

public class AnyplaceServerAPI {
    private static final String TAG = "AnyplaceServerAPI";
    public static final String SERVER_HOST = BuildConfig.SERVER_HOST;
    public static final String SERVER_PORT = BuildConfig.SERVER_PORT;
    public static final String BASE_URL = BuildConfig.API_BASE_URL;
    public static final String ACCESS_TOKEN = BuildConfig.BOOTSTRAP_ACCESS_TOKEN;

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

    public interface FetchRadioMapCallback {
        void onSuccess(File file);
        void onError(String error);
    }

    public static void fetchRadioMap(final Context ctx, final String buid, final String floor_number, final String lat, final String lon, final FetchRadioMapCallback callback) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    JSONObject jsonReq = new JSONObject();
                    jsonReq.put("access_token", ACCESS_TOKEN);
                    jsonReq.put("buid", buid);
                    jsonReq.put("floor_number", floor_number);
                    jsonReq.put("floor", floor_number);
                    jsonReq.put("coordinates_lat", lat != null ? lat : "0");
                    jsonReq.put("coordinates_lon", lon != null ? lon : "0");

                    RequestBody body = RequestBody.create(jsonReq.toString(), MediaType.parse("application/json; charset=utf-8"));
                    Request request = new Request.Builder()
                            .url(BASE_URL + "/radiomap/floor")
                            .post(body)
                            .build();

                    Response response = client.newCall(request).execute();
                    String respStr = response.body() != null ? response.body().string() : "";
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
                                File destDir = new File(ctx.getExternalFilesDir(null), "radiomaps/" + buid + "/" + floor_number);
                                destDir.mkdirs();
                                final File radioFile = new File(destDir, "indoor-radiomap-mean.txt");
                                FileOutputStream fos = new FileOutputStream(radioFile);
                                fos.write(dlResp.body().bytes());
                                fos.close();

                                new Handler(Looper.getMainLooper()).post(new Runnable() {
                                    @Override
                                    public void run() {
                                        if (callback != null) {
                                            callback.onSuccess(radioFile);
                                        }
                                    }
                                });
                                return;
                            }
                        }
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error fetching radio map: " + e.getMessage(), e);
                }

                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        if (callback != null) {
                            callback.onError("No server radiomap found.");
                        }
                    }
                });
            }
        }).start();
    }

    public interface UploadRSSCallback {
        void onSuccess(String message);
        void onError(String error);
    }

    public static void uploadRSSLog(final Context ctx, final File logFile, final UploadRSSCallback callback) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    if (logFile == null || !logFile.exists() || logFile.length() == 0) {
                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                if (callback != null) {
                                    callback.onError("No RSS log records found to upload.");
                                }
                            }
                        });
                        return;
                    }

                    RequestBody fileBody = RequestBody.create(logFile, MediaType.parse("text/plain"));
                    okhttp3.MultipartBody requestBody = new okhttp3.MultipartBody.Builder()
                            .setType(okhttp3.MultipartBody.FORM)
                            .addFormDataPart("radiomap", logFile.getName(), fileBody)
                            .build();

                    Request request = new Request.Builder()
                            .url(BASE_URL + "/radiomap/upload")
                            .addHeader("access_token", ACCESS_TOKEN)
                            .post(requestBody)
                            .build();

                    Response response = client.newCall(request).execute();
                    final String respStr = response.body() != null ? response.body().string() : "";

                    boolean isSuccess = false;
                    String serverMessage = "Data is sent successfully!";

                    try {
                        JSONObject jsonObj = new JSONObject(respStr);
                        String status = jsonObj.optString("status");
                        serverMessage = jsonObj.optString("message", serverMessage);
                        if ("success".equalsIgnoreCase(status) || jsonObj.optInt("status_code", 0) == 200) {
                            isSuccess = true;
                        }
                    } catch (Exception parseEx) {
                        if (response.isSuccessful()) {
                            isSuccess = true;
                        } else {
                            serverMessage = "Response: " + respStr;
                        }
                    }

                    final boolean finalSuccess = isSuccess;
                    final String finalMsg = serverMessage;

                    new Handler(Looper.getMainLooper()).post(new Runnable() {
                        @Override
                        public void run() {
                            if (callback != null) {
                                if (finalSuccess) {
                                    callback.onSuccess(finalMsg);
                                } else {
                                    callback.onError(finalMsg);
                                }
                            }
                        }
                    });
                } catch (final Exception e) {
                    Log.e(TAG, "Error uploading RSS log: " + e.getMessage(), e);
                    new Handler(Looper.getMainLooper()).post(new Runnable() {
                        @Override
                        public void run() {
                            if (callback != null) {
                                callback.onError("Upload failed: " + e.getMessage());
                            }
                        }
                    });
                }
            }
        }).start();
    }

    public interface ResetRadioMapCallback {
        void onSuccess(String message);
        void onError(String error);
    }

    public static void resetServerRadioMap(final Context ctx, final ResetRadioMapCallback callback) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    File emptyLogFile = new File(ctx.getCacheDir(), "empty_reset_rss.txt");
                    FileWriter fw = new FileWriter(emptyLogFile);
                    fw.write("# Timestamp, X, Y, HEADING, MAC Address of AP, RSS, Floor, BUID\n");
                    fw.close();

                    uploadRSSLog(ctx, emptyLogFile, new UploadRSSCallback() {
                        @Override
                        public void onSuccess(String message) {
                            if (callback != null) {
                                callback.onSuccess("Server WiFi data cleared successfully.");
                            }
                        }

                        @Override
                        public void onError(String error) {
                            if (callback != null) {
                                callback.onError(error);
                            }
                        }
                    });
                } catch (final Exception e) {
                    new Handler(Looper.getMainLooper()).post(new Runnable() {
                        @Override
                        public void run() {
                            if (callback != null) {
                                callback.onError("Reset failed: " + e.getMessage());
                            }
                        }
                    });
                }
            }
        }).start();
    }
}
