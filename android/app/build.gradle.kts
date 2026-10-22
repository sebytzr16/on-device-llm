import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Native build switches live in native/build.properties (written by the scripts
// in scripts/); Flutter does not forward Gradle -P flags.
val nativeProps = Properties().apply {
    val f = rootProject.file("../native/build.properties")
    if (f.exists()) f.inputStream().use { stream -> load(stream) }
}
val odllmVulkan: String = (project.findProperty("odllmVulkan") as String?) ?: nativeProps.getProperty("vulkan", "OFF")
val odllmOpenCL: String = (project.findProperty("odllmOpenCL") as String?) ?: nativeProps.getProperty("opencl", "OFF")
val odllmKleidiAI: String = (project.findProperty("odllmKleidiAI") as String?) ?: nativeProps.getProperty("kleidiai", "OFF")
// CPU -march for the bridge; empty keeps the CMake default (portable armv8-a, see native/CMakeLists.txt).
val odllmArch: String = (project.findProperty("odllmArch") as String?) ?: nativeProps.getProperty("arch", "")
val odllmAbis: List<String> = ((project.findProperty("odllmAbis") as String?) ?: nativeProps.getProperty("abis", "arm64-v8a")).split(",")

// Release credentials may come from an ignored android/key.properties file or
// CI environment variables. A partial configuration is rejected so a typo
// cannot silently produce an artifact signed by an unintended key.
val signingProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { stream -> load(stream) }
}
fun signingValue(property: String, environment: String): String? =
    signingProps.getProperty(property)?.takeIf { it.isNotBlank() }
        ?: System.getenv(environment)?.takeIf { it.isNotBlank() }
val releaseStoreFile = signingValue("storeFile", "ODLLM_ANDROID_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "ODLLM_ANDROID_STORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ODLLM_ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ODLLM_ANDROID_KEY_PASSWORD")
val releaseSigningValues = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val hasReleaseSigning = releaseSigningValues.all { it != null }
val hasPartialReleaseSigning = releaseSigningValues.any { it != null } && !hasReleaseSigning
val requireReleaseSigning =
    ((project.findProperty("odllmRequireReleaseSigning") as String?)
        ?: System.getenv("ODLLM_REQUIRE_RELEASE_SIGNING")
        ?: "false").toBoolean()

if (hasPartialReleaseSigning) {
    throw GradleException("Android release signing is incomplete; provide all four signing values.")
}
if (requireReleaseSigning && !hasReleaseSigning) {
    throw GradleException("Production signing is required but no complete signing configuration was provided.")
}

android {
    namespace = "app.ondevicellm.ondevice_llm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (nativeProps.getProperty("smoke", "false") == "true") "app.ondevicellm.ondevice_llm.smoke" else "app.ondevicellm.ondevice_llm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters += odllmAbis }
        externalNativeBuild {
            cmake {
                abiFilters += odllmAbis
                arguments += listOf("-DODLLM_VULKAN=$odllmVulkan", "-DODLLM_OPENCL=$odllmOpenCL", "-DODLLM_KLEIDIAI=$odllmKleidiAI", "-DCMAKE_BUILD_TYPE=Release")
                if (odllmArch.isNotEmpty()) arguments += "-DODLLM_ARM_ARCH=$odllmArch"
                targets += "ondevice_llm"
            }
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("production") {
                val configuredStore = file(releaseStoreFile!!)
                if (!configuredStore.isFile) {
                    throw GradleException("Android release keystore does not exist: $configuredStore")
                }
                storeFile = configuredStore
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Debug fallback keeps local release profiling usable. Production
            // jobs must set ODLLM_REQUIRE_RELEASE_SIGNING=true (or the Gradle
            // property) so a store artifact can never use this fallback.
            signingConfig = signingConfigs.getByName(
                if (hasReleaseSigning) "production" else "debug",
            )
        }
    }
    externalNativeBuild {
        cmake { path = file("../../native/CMakeLists.txt"); version = "3.22.1" }
    }
    packaging {
        jniLibs {
            // The OpenCL ICD loader under .tools is a link-time stub only. Shipping it
            // would shadow the vendor driver (uses-native-library) and report no GPU.
            excludes += "**/libOpenCL.so"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Same bundled Latin recognizer as before, without the legacy plugin.
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
