allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// flutter_google_places_sdk_android 0.2.2 (la última compatible con
// flutter_google_places_sdk 0.4.x) usa métodos que Places SDK 5.x eliminó
// (getAddress, getLatLng…). Se fija la última 4.x, que los mantiene y ya
// soporta la Places API (New). Quitar al actualizar el paquete.
subprojects {
    configurations.all {
        resolutionStrategy.force("com.google.android.libraries.places:places:4.4.1")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
