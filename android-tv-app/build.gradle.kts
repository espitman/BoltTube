plugins {
    id("com.android.application") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "1.9.24"
    id("org.jetbrains.kotlin.plugin.serialization") version "1.9.24"
}

android {
    namespace = "ir.boum.bolttube.tv"
    compileSdk = 35

    defaultConfig {
        applicationId = "ir.boum.bolttube.tv"
        minSdk = 21
        targetSdk = 35
        versionCode = 2
        versionName = "1.0.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            storeFile = file("release.jks")
            storePassword = "bolttube123"
            keyAlias = "bolttube"
            keyPassword = "bolttube123"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    val ktorVersion = "2.3.12"
    val media3Version = "1.4.1"

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.fragment:fragment:1.5.1")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx-android:2.8.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.3")
    implementation("androidx.lifecycle:lifecycle-livedata:2.8.3")
    implementation("androidx.recyclerview:recyclerview:1.3.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.0")

    implementation("io.ktor:ktor-client-core:$ktorVersion")
    implementation("io.ktor:ktor-client-okhttp:$ktorVersion")
    implementation("io.ktor:ktor-client-content-negotiation:$ktorVersion")
    implementation("io.ktor:ktor-client-websockets:$ktorVersion")
    implementation("io.ktor:ktor-serialization-kotlinx-json:$ktorVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")

    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
    implementation("com.github.bumptech.glide:glide:4.16.0")
}
