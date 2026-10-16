import com.typesafe.config.ConfigFactory

val conf = ConfigFactory.parseFile(new File("conf/app.base.conf")).resolve()
val appVersion = conf.getString("application.version")
val appName= conf.getString("application.name")

lazy val root = (project in file("."))
  .enablePlugins(PlayScala, SwaggerPlugin)
  .settings(
    name := appName,
    version := appVersion,
    maintainer := "anyplace@cs.ucy.ac.cy",
    scalaVersion := "2.13.6",
    libraryDependencies ++= Seq(
      guice,
      "com.typesafe.play" %% "play-json" % "2.10.0-RC5",
      "com.typesafe.play" %% "play" % "2.8.8",
      "org.mongodb.scala" %% "mongo-scala-driver" % "4.3.0",
      "com.typesafe.play" %% "play-specs2" % "2.8.8" % Test
    ),
    scalacOptions ++= Seq(
      "-feature",
      "-deprecation",
      "-Xfatal-warnings")
  )

resolvers ++= Seq(
  Resolver.mavenCentral,
)

swaggerRoutesFile := "api.routes"
// auto generate swagger definitions for domain classes
swaggerDomainNameSpaces := Seq("models")
swaggerPrettyJson := true

// Java 17+: old Guice/cglib needs these opens in EVERY JVM that runs app
// code — including forked tests, which inherit neither .jvmopts nor SBT_OPTS
// reliably across launchers. Keep in sync with anyplace.service's
// JDK_JAVA_OPTIONS. Heap kept modest for 1 GB build boxes (swap-backed).
Test / fork := true
Test / javaOptions ++= Seq(
  "--add-opens=java.base/java.lang=ALL-UNNAMED",
  "--add-opens=java.base/java.util=ALL-UNNAMED",
  "--add-opens=java.base/java.lang.invoke=ALL-UNNAMED",
  "--add-opens=java.base/java.io=ALL-UNNAMED",
  "-Xmx768m"
)