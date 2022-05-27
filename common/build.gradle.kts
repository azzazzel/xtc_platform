/*
 * Build the "common" module.
 */

val libDir = "${rootProject.projectDir}/lib"
val xdkBin = "${rootProject.projectDir}/xdk/bin"

tasks.register("build") {
    group       = "Build"
    description = "Build this module"

    val src = fileTree("${projectDir}/src").getFiles().stream().
            mapToLong({f -> f.lastModified()}).max().orElse(0)
    val dst = file("$libDir/common.xtc").lastModified()

    if (src > dst) {
        val srcModule = "${projectDir}/src/main/x/common.x"

        project.exec {
            commandLine("$xdkBin/xtc", "-verbose",
                        "-o", "$libDir",
                        "$srcModule")
        }
    }
}