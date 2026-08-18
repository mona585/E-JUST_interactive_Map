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

import cy.ac.ucy.cs.anyplace.logger.AndroidFileBrowser;


import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.SharedPreferences.OnSharedPreferenceChangeListener;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.preference.Preference;
import android.preference.PreferenceActivity;
import android.preference.Preference.OnPreferenceClickListener;
import android.provider.MediaStore.MediaColumns;

public class LoggerPrefs extends PreferenceActivity implements OnSharedPreferenceChangeListener {

	private static final int SELECT_IMAGE = 7;
	private static final int SELECT_PATH = 8;

	public enum Action {
		REFRESH_BUILDING
	}
	
	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);

		getPreferenceManager().setSharedPreferencesName(getString(R.string.preferences_file));
		addPreferencesFromResource(cy.ac.ucy.cs.anyplace.lib.R.xml.preferences_logger);

		getPreferenceManager().getSharedPreferences().registerOnSharedPreferenceChangeListener(this);

		Preference folderPref = findPreference("folder_browser");
		if (folderPref != null) {
			folderPref.setOnPreferenceClickListener(new OnPreferenceClickListener() {
				@Override
				public boolean onPreferenceClick(Preference preference) {
					Intent i = new Intent(getBaseContext(), AndroidFileBrowser.class);
					Bundle extras = new Bundle();
					extras.putBoolean("selectFolder", true);
					SharedPreferences preferences = getSharedPreferences(getString(R.string.preferences_file), MODE_PRIVATE);
					extras.putString("defaultPath", preferences.getString("folder_browser", ""));
					i.putExtras(extras);
					startActivityForResult(i, SELECT_PATH);
					return true;
				}
			});
		}

		Preference addBldPref = findPreference("add_building");
		if (addBldPref != null) {
			addBldPref.setOnPreferenceClickListener(new OnPreferenceClickListener() {
				@Override
				public boolean onPreferenceClick(Preference preference) {
					Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(BuildConfig.PUBLIC_BASE_URL + "/architect/"));
					startActivity(browserIntent);
					return true;
				}
			});
		}

		Preference refBldPref = findPreference("refresh_building");
		if (refBldPref != null) {
			refBldPref.setOnPreferenceClickListener(new OnPreferenceClickListener() {
				@Override
				public boolean onPreferenceClick(Preference preference) {
					Intent returnIntent = new Intent();
					returnIntent.putExtra("action", Action.REFRESH_BUILDING);
					setResult(RESULT_OK, returnIntent);
					finish();
					return true;
				}
			});
		}

		updateSummaries();
	}

	private void updateSummaries() {
		SharedPreferences sp = getPreferenceManager().getSharedPreferences();
		if (sp == null) return;

		Preference intervalPref = findPreference("samples_interval");
		if (intervalPref != null) {
			intervalPref.setSummary("Sampling Interval: " + sp.getString("samples_interval", "1000") + " ms");
		}

		Preference folderPref = findPreference("folder_browser");
		if (folderPref != null) {
			folderPref.setSummary("Storage Path: " + sp.getString("folder_browser", getFilesDir().getAbsolutePath()));
		}

		Preference logPref = findPreference("filename_log");
		if (logPref != null) {
			logPref.setSummary("Log Filename: " + sp.getString("filename_log", "anyplace_rss.txt"));
		}

		Preference userPref = findPreference("username");
		if (userPref != null) {
			userPref.setSummary("Username: " + sp.getString("username", "anonymous"));
		}
	}

	@Override
	public void onActivityResult(int requestCode, int resultCode, Intent data) {
		super.onActivityResult(requestCode, resultCode, data);

		if (requestCode == SELECT_PATH && resultCode == Activity.RESULT_OK && data != null) {
			Uri selectedFolder = data.getData();
			if (selectedFolder != null) {
				String path = selectedFolder.toString();
				SharedPreferences preferences = getSharedPreferences(getString(R.string.preferences_file), MODE_PRIVATE);
				SharedPreferences.Editor editor = preferences.edit();
				editor.putString("folder_browser", path);
				editor.commit();
				updateSummaries();
			}
		}
	}

	@Override
	protected void onResume() {
		super.onResume();
		getPreferenceScreen().getSharedPreferences().registerOnSharedPreferenceChangeListener(this);
		updateSummaries();
	}

	@Override
	protected void onDestroy() {
		getPreferenceManager().getSharedPreferences().unregisterOnSharedPreferenceChangeListener(this);
		super.onDestroy();
	}

	@Override
	protected void onPause() {
		super.onPause();
		getPreferenceScreen().getSharedPreferences().unregisterOnSharedPreferenceChangeListener(this);
	}

	@Override
	public void onSharedPreferenceChanged(SharedPreferences sharedPreferences, String key) {
		updateSummaries();
	}
}
