package com.dmsl.anyplace.tasks;

import java.net.SocketTimeoutException;
import java.util.ArrayList;
import java.util.List;
import org.apache.http.conn.ConnectTimeoutException;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.app.ProgressDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.os.AsyncTask;

import com.dmsl.anyplace.AnyplaceAPI;
import com.dmsl.anyplace.nav.FloorModel;
import com.dmsl.anyplace.utils.NetworkUtils;

public class FetchFloorsByBuidTask extends AsyncTask<Void, Void, String> {

	public interface FetchFloorsByBuidTaskListener {
		void onErrorOrCancel(String result);

		void onSuccess(String result, List<FloorModel> floors);
	}

	private FetchFloorsByBuidTaskListener mListener;
	private Context ctx;
	private String buid;
	private List<FloorModel> floors = new ArrayList<FloorModel>();
	private boolean success = false;
	private ProgressDialog dialog;
	private Boolean showDialog = true;

	public FetchFloorsByBuidTask(FetchFloorsByBuidTaskListener fetchFloorsByBuidTaskListener, Context ctx, String buid) {
		this.mListener = fetchFloorsByBuidTaskListener;
		this.ctx = ctx;
		this.buid = buid;
	}

	public FetchFloorsByBuidTask(FetchFloorsByBuidTaskListener fetchFloorsByBuidTaskListener, Context ctx, String buid, Boolean showDialog) {
		this(fetchFloorsByBuidTaskListener, ctx, buid);
		this.showDialog = showDialog;
	}

	@Override
	protected void onPreExecute() {
		if (showDialog) {
			dialog = new ProgressDialog(ctx);
			dialog.setIndeterminate(true);
			dialog.setTitle("Fetching Floors");
			dialog.setMessage("Please be patient...");
			dialog.setCancelable(true);
			dialog.setCanceledOnTouchOutside(false);
			dialog.setOnCancelListener(new DialogInterface.OnCancelListener() {
				@Override
				public void onCancel(DialogInterface dialog) {
					FetchFloorsByBuidTask.this.cancel(true);
				}
			});
			dialog.show();
		}
	}

	@Override
	protected String doInBackground(Void... params) {
		if (!NetworkUtils.isOnline(ctx)) {
			return "No connection available!";
		}

		try {
			JSONObject j = new JSONObject();
			j.put("username", AnyplaceAPI.getApiUsername());
			j.put("password", AnyplaceAPI.getApiPassword());
			j.put("buid", this.buid);

			String response = NetworkUtils.downloadHttpClientJsonPost(AnyplaceAPI.getFetchFloorsByBuidUrl(), j.toString());
			JSONObject json = new JSONObject(response);

			if (json.has("status") && json.getString("status").equalsIgnoreCase("error")) {
				return "Error Message: " + json.getString("message");
			}

			JSONArray floors_json = json.getJSONArray("floors");
			for (int i = 0; i < floors_json.length(); i++) {
				JSONObject obj = floors_json.getJSONObject(i);
				FloorModel f = new FloorModel();
				f.buid = obj.optString("buid", this.buid);
				f.description = obj.optString("description", "");
				f.floor_name = obj.optString("floor_name", "");
				f.floor_number = obj.optString("floor_number", "");
				f.bottom_left_lat = obj.optString("bottom_left_lat", "");
				f.bottom_left_lng = obj.optString("bottom_left_lng", "");
				f.top_right_lat = obj.optString("top_right_lat", "");
				f.top_right_lng = obj.optString("top_right_lng", "");
				floors.add(f);
			}

			success = true;
			return "Successfully fetched floors";

		} catch (ConnectTimeoutException e) {
			return "Connecting to Anyplace service is taking too long!";
		} catch (SocketTimeoutException e) {
			return "Communication with the server is taking too long!";
		} catch (JSONException e) {
			return "Not valid response from the server! Contact the admin.";
		} catch (Exception e) {
			return "Error fetching floors. Exception[ " + e.getMessage() + " ]";
		}
	}

	@Override
	protected void onPostExecute(String result) {
		if (dialog != null) {
			try {
				if (dialog.isShowing())
					dialog.dismiss();
			} catch (Exception e) {

			}
		}

		if (success) {
			mListener.onSuccess(result, floors);
		} else {
			mListener.onErrorOrCancel(result);
		}
	}

	@Override
	protected void onCancelled(String result) {
		if (dialog != null) {
			try {
				if (dialog.isShowing())
					dialog.dismiss();
			} catch (Exception e) {

			}
		}

		mListener.onErrorOrCancel(result);
	}
}
