import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import com.android.build.api.dsl.ApplicationExtension

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

configure<ApplicationExtension> {
    namespace = "com.ghandour.na2slna"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.ghandour.na2slna"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyProps = Properties()
            val keyPropsFile = rootProject.file("key.properties")
            if (keyPropsFile.exists()) {
                keyProps.load(keyPropsFile.inputStream())
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// Source - https://stackoverflow.com/a/70313152
// Posted by kunlinwang, modified by community. See post 'Timeline' for change history
// Retrieved 2026-10-23, License - CC BY-SA 4.0

afterEvaluate {
    if (project.hasProperty("android.injected.signing.store.file")) {
        println ("key store path: ${project.property("android.injected.signing.store.file")}")
    }
    if (project.hasProperty("android.injected.signing.store.password")) {
        println ("key store password: ${project.property("android.injected.signing.store.password")}")
    }
    if (project.hasProperty("android.injected.signing.key.alias")) {
        println ("key alias: ${project.property("android.injected.signing.key.alias")}")
    }
    if (project.hasProperty("android.injected.signing.key.password")) {
        println ("key password: ${project.property("android.injected.signing.key.password")}")
    }
}


// Fixed top-level Kotlin configuration signature block
kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
