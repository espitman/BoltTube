plugins {
    id("org.jetbrains.kotlin.jvm") version "1.9.24"
    id("org.jetbrains.kotlin.plugin.serialization") version "1.9.24"
    id("io.ktor.plugin") version "2.3.12"
    application
}

group = "ir.boum.bolttube"
version = "1.0.0"

application {
    mainClass.set("ir.boum.bolttube.server.MacServerKt")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("io.ktor:ktor-server-core-jvm:2.3.12")
    implementation("io.ktor:ktor-server-netty-jvm:2.3.12")
    implementation("io.ktor:ktor-server-content-negotiation-jvm:2.3.12")
    implementation("io.ktor:ktor-server-call-logging-jvm:2.3.12")
    implementation("io.ktor:ktor-server-cors-jvm:2.3.12")
    implementation("io.ktor:ktor-server-partial-content-jvm:2.3.12")
    implementation("io.ktor:ktor-serialization-kotlinx-json-jvm:2.3.12")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    implementation("ch.qos.logback:logback-classic:1.5.6")
}
