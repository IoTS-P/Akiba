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
    version = "3.1.0"
}