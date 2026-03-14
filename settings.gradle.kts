plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.8.0"
}
rootProject.name = "Akiba"

include("akiba_framework")
project(":akiba_framework").projectDir = file("subprojects/akiba_framework")

include("akiba_db_daemon")
project(":akiba_db_daemon").projectDir = file("subprojects/akiba_db_daemon")

include("akiba_mod_utils")
project(":akiba_mod_utils").projectDir = file("subprojects/akiba_mod_utils")

include("akiba_modules")
project(":akiba_modules").projectDir = file("subprojects/akiba_modules")