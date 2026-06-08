plugins {
    kotlin("jvm") version "2.3.20" apply false
    kotlin("plugin.serialization") version "2.3.20" apply false
}

subprojects {
    repositories {
        mavenCentral()
    }

    plugins.withType<JavaPlugin>().configureEach {
        dependencies {
            "implementation"(files("lib/ghidra.jar"))
        }
    }
}

allprojects {
    version = "4.0.0"
}
