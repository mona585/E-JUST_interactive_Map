package cy.ac.ucy.cs.anyplace.logger;

import android.app.Application;

import cy.ac.ucy.cs.anyplace.lib.Anyplace;
import cy.ac.ucy.cs.anyplace.lib.android.LOG;

public class AnyplaceApp extends Application {
  private Anyplace client = null;

  public void initializeAnyplace(){
    //TODO: initialize with shared preferences

     this.client = new Anyplace(BuildConfig.SERVER_HOST, BuildConfig.SERVER_PORT,
         getApplicationContext().getCacheDir().getAbsolutePath());

  }

  public Anyplace getAnyplace() {
    if (client == null){
      LOG.e("Anyplace not initialized");

    }
    return client;
  }
}
