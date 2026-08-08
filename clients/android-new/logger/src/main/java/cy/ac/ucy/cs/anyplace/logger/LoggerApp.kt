package cy.ac.ucy.cs.anyplace.logger

import cy.ac.ucy.cs.anyplace.lib.android.NavigatorAppBase
import cy.ac.ucy.cs.anyplace.lib.android.utils.LOG
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class LoggerApp : NavigatorAppBase() {

  override fun onCreate() {
    super.onCreate()
    LOG.D2()
  }
}