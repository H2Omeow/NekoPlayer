pluginManagement {
    repositories {
        // Maven Central redirected the large Kotlin compiler artifact to a
        // GitHub release asset that returned 504 during CI. The mirror keeps
        // resolution off the GitHub CDN; the official repositories remain as
        // fallbacks.
        maven("https://repo.huaweicloud.com/repository/maven/")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven("https://repo.huaweicloud.com/repository/maven/")
        google()
        mavenCentral()
    }
}
rootProject.name = "NekoPlayer"
include(":app")
