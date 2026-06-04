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
