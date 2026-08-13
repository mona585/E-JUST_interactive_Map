package cy.ac.ucy.cs.anyplace.logger;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;

import androidx.appcompat.app.ActionBar;
import androidx.appcompat.app.AppCompatActivity;
import androidx.preference.Preference;
import androidx.preference.PreferenceFragmentCompat;

import java.io.File;

public class SettingsActivity extends AppCompatActivity {
  private final String TAG = SettingsActivity.class.getSimpleName();
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setContentView(R.layout.settings_activity);
    getSupportFragmentManager()
            .beginTransaction()
            .replace(R.id.settings, new SettingsFragment())
            .commit();
    ActionBar actionBar = getSupportActionBar();
    if (actionBar != null) {
      actionBar.setDisplayHomeAsUpEnabled(true);
    }

  }


  public static class SettingsFragment extends PreferenceFragmentCompat {
    private static final String TAG = SettingsFragment.class.getSimpleName();

    private void deleteFolder(File fileOrDirectory) {
      if (fileOrDirectory == null || !fileOrDirectory.exists()) return;
      if (fileOrDirectory.isDirectory()) {
        File[] children = fileOrDirectory.listFiles();
        if (children != null) {
          for (File child : children) {
            deleteFolder(child);
          }
        }
      }
      fileOrDirectory.delete();
    }

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
      setPreferencesFromResource(R.xml.preferences_anyplace, rootKey);

      Preference clearRadioPref = findPreference("clear_radiomaps");
      if (clearRadioPref != null) {
        clearRadioPref.setOnPreferenceClickListener(new Preference.OnPreferenceClickListener() {
          @Override
          public boolean onPreferenceClick(Preference preference) {
            try {
              if (getContext() != null) {
                File extRadioMaps = new File(getContext().getExternalFilesDir(null), "radiomaps");
                deleteFolder(extRadioMaps);
                File localRadioMaps = new File(getContext().getFilesDir(), "radiomaps");
                deleteFolder(localRadioMaps);
                Toast.makeText(getContext(), "Cached radiomaps deleted successfully!", Toast.LENGTH_SHORT).show();
              }
            } catch (Exception e) {
              if (getContext() != null) {
                Toast.makeText(getContext(), "Error clearing radiomaps: " + e.getMessage(), Toast.LENGTH_SHORT).show();
              }
            }
            return true;
          }
        });
      }

      Preference clearFloorPref = findPreference("clear_floorplans");
      if (clearFloorPref != null) {
        clearFloorPref.setOnPreferenceClickListener(new Preference.OnPreferenceClickListener() {
          @Override
          public boolean onPreferenceClick(Preference preference) {
            try {
              if (getContext() != null) {
                File extFloorPlans = new File(getContext().getExternalFilesDir(null), "floor_plans");
                deleteFolder(extFloorPlans);
                File localFloorPlans = new File(getContext().getFilesDir(), "floor_plans");
                deleteFolder(localFloorPlans);
                Toast.makeText(getContext(), "Cached floorplans deleted successfully!", Toast.LENGTH_SHORT).show();
              }
            } catch (Exception e) {
              if (getContext() != null) {
                Toast.makeText(getContext(), "Error clearing floorplans: " + e.getMessage(), Toast.LENGTH_SHORT).show();
              }
            }
            return true;
          }
        });
      }

      Preference refBldPref = findPreference("refresh_building");
      if (refBldPref != null) {
        refBldPref.setOnPreferenceClickListener(new Preference.OnPreferenceClickListener() {
          @Override
          public boolean onPreferenceClick(Preference preference) {
            if (getActivity() != null) {
              Intent returnIntent = new Intent();
              returnIntent.putExtra("action", LoggerPrefs.Action.REFRESH_BUILDING);
              getActivity().setResult(RESULT_OK, returnIntent);
              getActivity().finish();
            }
            return true;
          }
        });
      }
    }
  }
}