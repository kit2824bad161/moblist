allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val javaCompile = project.tasks.withType<JavaCompile>().findByName("compileDebugJavaWithJavac")
            ?: project.tasks.withType<JavaCompile>().firstOrNull()
        val target = javaCompile?.targetCompatibility ?: "17"
        val normalized = when (target) {
            "1.8", "8" -> "1.8"
            "11" -> "11"
            "17" -> "17"
            "21" -> "21"
            else -> "17"
        }
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(normalized))
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

