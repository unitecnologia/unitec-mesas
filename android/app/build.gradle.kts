import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Atualização por cima no Android exige SEMPRE a mesma assinatura.
// Credenciais ficam em android/key.properties (fora do Git). Sem o arquivo, o
// release falha de propósito — nunca assina com a chave de debug.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "br.com.unitec.unitec_mesas"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.com.unitec.unitec_mesas"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            check(keystorePropertiesFile.exists()) {
                "Falta android/key.properties. Copie de key.properties.example e aponte para a chave de release."
            }
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storePassword = keystoreProperties["storePassword"] as String
            // Caminho relativo a android/app/ (ex.: ../../ci/unitecmesas-release.p12).
            val store = file(keystoreProperties["storeFile"] as String)
            check(store.exists()) {
                "Keystore de release não encontrada: ${store.absolutePath}"
            }
            storeFile = store
            val type = keystoreProperties["storeType"] as String?
            if (!type.isNullOrBlank()) {
                storeType = type
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

android.applicationVariants.configureEach {
    val appLabel = "Unitec-Mesas"
    outputs.configureEach {
        val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
        output.outputFileName = "$appLabel-${versionName}.apk"
    }
}
