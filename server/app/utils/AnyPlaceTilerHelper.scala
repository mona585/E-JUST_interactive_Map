package utils

import java.io._
import java.nio.file.Files

import javax.inject.{Inject, Singleton}
import play.api.Configuration
import play.api.mvc.{AbstractController, ControllerComponents}

@Singleton
class AnyPlaceTilerHelper @Inject()(cc: ControllerComponents,
                                conf: Configuration,
                                api: AnyplaceServerAPI)
  extends AbstractController(cc) {

    private val ANYPLACE_TILER_SCRIPT_START =  "start-anyplace-tiler.sh"
    private val FLOOR_PLANS_ROOT_DIR = "floor_plans" + File.separatorChar
    private val FLOOR_TILES_DIR = "static_tiles" + File.separatorChar

    val FLOOR_TILES_ZIP_NAME = "tiles_archive.zip"

    def getTilerScriptStart(): String = {
        conf.get[String]("tilerRootDir")  + File.separatorChar + ANYPLACE_TILER_SCRIPT_START
    }

    def getRootFloorPlansDir(): String = {
        val configured = conf.get[String]("floorPlansRootDir")
        val dir = new File(configured)
        if (!dir.exists() && new File("/opt/anyplace/floorplans").exists()) {
            "/opt/anyplace/floorplans" + File.separatorChar
        } else {
            configured + File.separatorChar
        }
    }

    private def requireSafeSegment(value: String, label: String): String = {
        if (!Utils.isSafePathSegment(value))
            throw new IllegalArgumentException("Invalid " + label + " identifier.")
        value
    }

    def getRootFloorPlansDirFor(buid: String): String = {
        getRootFloorPlansDir() + requireSafeSegment(buid, "building") + File.separatorChar
    }

    def getRootFloorPlansDirFor(buid: String, floor: String): String = {
        getRootFloorPlansDir() + requireSafeSegment(buid, "building") + File.separatorChar +
          "fl_" + requireSafeSegment(floor, "floor") + File.separatorChar
    }

    def getFloorPlanFor(buid: String, floor: String): String = {
        getRootFloorPlansDirFor(buid, floor) + "fl_" + floor
    }

    def getFloorTilesDirFor(buid: String, floor: String): String = {
        getRootFloorPlansDirFor(buid, floor) + FLOOR_TILES_DIR
    }

    def getFloorTilesZipFor(buid: String, floor: String): String = {
        getRootFloorPlansDirFor(buid, floor) + FLOOR_TILES_DIR +
          FLOOR_TILES_ZIP_NAME
    }

    // CHECK:PM
    def getFloorTilesZipLinkFor(buid: String, floor: String): String = {
        if (buid.trim().isEmpty || floor.trim().isEmpty) {
            return null
        }
        api.urlPath("api", "floortiles", buid, floor, FLOOR_TILES_ZIP_NAME)
    }

    /**
     * Stores floorplan(images) to fileSystem.
     * @param buid
     * @param floor_number
     * @param file
     * @return
     */
    def storeFloorPlanToServer(buid: String, floor_number: String, file: File): File = {
        LOG.D2("storeFloorPlanToServer")
        val dirS = getRootFloorPlansDirFor(buid, floor_number)
        if (!Utils.isWithinRoot(getRootFloorPlansDir(), dirS))
            throw new IllegalArgumentException("Invalid building or floor identifier.")
        val dir = new File(dirS)

        LOG.D3("storeFloorPlanToServer: dir: " + dir.getAbsolutePath)
        LOG.D3("storeFloorPlanToServer: file: " + file.getAbsolutePath)
        LOG.D3("storeFloorPlanToServer: file size: " + file.length())
        dir.mkdirs()
        if (!dir.isDirectory || !dir.canWrite || !dir.canExecute) {
            throw new AnyPlaceException("Floor plans directory is inaccessible!")
        }
        val name = "fl" + "_" + floor_number
        val dest_f = new File(dir, name)
        var fout: FileOutputStream = null
        fout = new FileOutputStream(dest_f)
        Files.copy(file.toPath, fout)
        fout.close()
        dest_f
    }

    // Asynchronously tiles the given floorplan image.
    //
    // Tiling a large floorplan image is slow (it may take minutes), so this
    // method spawns the tiler subprocess and returns WITHOUT waiting for it to
    // finish. This avoids the enclosing HTTP request blocking for the whole
    // tiling duration and timing out on the client side (504) even though the
    // tiles are ultimately generated on disk.
    //
    // Tiles are served from disk by URL later (after the process finishes), so
    // an early return is safe: the floorplan document and source image are
    // already saved before this is called. To still surface immediate startup
    // failures (missing/unexecutable script, permission errors) we give the
    // process a short bounded grace period; if it exits with a non-zero code
    // during that window we report an error, otherwise we assume tiling has
    // started and return successfully.
    private def tileImageAsync(imageFile: File, lat: String, lng: String, zoom: Option[String]): Boolean = {
        if (!imageFile.isFile || !imageFile.canRead()) {
            return false
        }
        val imageDir = imageFile.getParentFile
        if (!imageDir.isDirectory || !imageDir.canWrite() || !imageDir.canRead()) {
            throw new AnyPlaceException("Server do not have the permissions to tile the passed argument[" +
              imageFile.toString + "]")
        }
        val args = zoom match {
            case Some(z) => Array(getTilerScriptStart(), imageFile.getAbsolutePath, lat, lng, "-DISLOG", z)
            case None    => Array(getTilerScriptStart(), imageFile.getAbsolutePath, lat, lng, "-DISLOG")
        }
        val pb = new ProcessBuilder(args: _*)
        val log = new File(imageDir, "anyplace_tiler_" + imageFile.getName + ".log")
        pb.redirectErrorStream(true)
        pb.redirectOutput(ProcessBuilder.Redirect.appendTo(log))
        // A short window to detect immediate launch failures without blocking
        // on the (slow) tiling itself.
        val graceMillis = 6000L
        try {
            val p = pb.start()
            val deadline = System.currentTimeMillis() + graceMillis
            var alive = true
            while (System.currentTimeMillis() < deadline) {
                try {
                    p.exitValue()
                    alive = false
                } catch {
                    case _: IllegalThreadStateException => alive = true
                }
                if (!alive) {
                    val code = p.exitValue()
                    if (code != 0) {
                        val err = "Tiling for image[" + imageFile.toString + "] failed with exit code[" +
                          code + "]!"
                        LOG.E(err)
                        throw new AnyPlaceException(err)
                    }
                    return true
                }
                Thread.sleep(200)
            }
            // Process is still running after the grace period -> tiling started
            // successfully; let it finish in the background.
            LOG.I("Tiling started asynchronously for image[" + imageFile.toString + "]")
            true
        } catch {
            case e: IOException => {
                val err = "Tiling for image[" + imageFile.toString + "] failed with IOException[" +
                  e.getMessage + "]!"
                LOG.E(err)
                throw new AnyPlaceException(err)
            }
            case e: InterruptedException => {
                val err = "Tiling for image[" + imageFile.toString + "] failed with InterruptedException[" +
                  e.getMessage + "]!"
                LOG.E(err)
                throw new AnyPlaceException(err)
            }
        }
    }

    def tileImage(imageFile: File, lat: String, lng: String): Boolean = {
        tileImageAsync(imageFile, lat, lng, None)
    }

    def tileImageWithZoom(imageFile: File, lat: String, lng: String, zoom: String): Boolean = {
        tileImageAsync(imageFile, lat, lng, Some(zoom))
    }

}

