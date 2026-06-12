import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Load release signing config from keystore.properties.
val keystoreProps = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = "com.finix.omniverse"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.finix.omniverse"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "2.1.0"
        // Works on phones, tablets, and Android TV — single universal APK.
    }

    signingConfigs {
        create("release") {
            if (keystoreProps.getProperty("storeFile") != null) {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false   // keep one clean universal apk; scrapers rely on reflection-free code
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            applicationIdSuffix = ""
        }
    }

    // Force a single universal APK (no per-ABI splits).
    splits {
        abi { isEnable = false }
        density { isEnable = false }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")

    // Compose UI
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.navigation:navigation-compose:2.8.4")

    // Compose for Android TV (D-pad focus, TV-styled surfaces)
    implementation("androidx.tv:tv-material:1.0.0")

    // Media3 / ExoPlayer (HLS, DASH, progressive)
    implementation("androidx.media3:media3-exoplayer:1.5.0")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.0")
    implementation("androidx.media3:media3-exoplayer-dash:1.5.0")
    implementation("androidx.media3:media3-ui:1.5.0")
    implementation("androidx.media3:media3-datasource-okhttp:1.5.0")

    // Networking + JSON
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // HTML scraping (HiAnime, yarrlist, onepace, vidsrc)
    implementation("org.jsoup:jsoup:1.18.1")

    // Images
    implementation("io.coil-kt:coil-compose:2.7.0")
    // Palette — derive hero text colour from the banner image.
    implementation("androidx.palette:palette-ktx:1.0.0")

    // Secure key storage
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // QR (sync QR generation) + camera scanner
    implementation("com.google.zxing:core:3.5.3")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")

    // Splash screen (API 23+ compat)
    implementation("androidx.core:core-splashscreen:1.0.1")
}
