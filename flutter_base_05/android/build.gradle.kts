allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Play requires Billing Library 8.0.0+. in_app_purchase_android 0.4.0+5 declares 7.1.1.
subprojects {
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.android.billingclient" && requested.name.startsWith("billing")) {
                useVersion("9.1.0")
                because("Google Play requires Billing Library 8.0.0 or later")
            }
        }
    }

    plugins.withId("com.android.library") {
        if (project.name != "in_app_purchase_android") {
            return@withId
        }
        // Stage Java sources in this project's build dir. Do not edit the Pub cache copy.
        afterEvaluate {
            val pubspec = project.projectDir.parentFile.resolve("pubspec.yaml")
            val pubspecText = if (pubspec.exists()) pubspec.readText() else ""
            if (!pubspecText.contains("version: 0.4.0+5")) {
                throw GradleException(
                    "Play Billing patch only matches in_app_purchase_android 0.4.0+5 " +
                        "(found ${pubspec.absolutePath})"
                )
            }
            val patchedHandler =
                rootProject.file("patches/in_app_purchase_android/MethodCallHandlerImpl.java")
            if (!patchedHandler.exists()) {
                throw GradleException("Missing Play Billing patch: ${patchedHandler.absolutePath}")
            }
            val staging =
                rootProject.layout.buildDirectory
                    .dir("in_app_purchase_android_src/java")
                    .get()
                    .asFile
            val originalJava = project.file("src/main/java")
            if (staging.exists()) {
                staging.deleteRecursively()
            }
            originalJava.copyRecursively(staging, overwrite = true)
            patchedHandler.copyTo(
                staging.resolve(
                    "io/flutter/plugins/inapppurchase/MethodCallHandlerImpl.java"
                ),
                overwrite = true,
            )
            val androidExt = extensions.getByName("android")
            val sourceSets = androidExt.javaClass.getMethod("getSourceSets").invoke(androidExt)
            val main =
                sourceSets.javaClass
                    .getMethod("getByName", String::class.java)
                    .invoke(sourceSets, "main")
            val javaSet = main.javaClass.getMethod("getJava").invoke(main)
            javaSet.javaClass
                .getMethod("setSrcDirs", Iterable::class.java)
                .invoke(javaSet, listOf(staging))
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
