# Etapa 1: Construcción del JAR con Gradle Wrapper
FROM gradle:8.5-jdk21 AS builder
WORKDIR /app
COPY . .
RUN chmod +x gradlew
RUN ./gradlew clean build -x test --stacktrace --info

# Etapa 2: Imagen final con JDK 21 
FROM eclipse-temurin:21-jdk-alpine
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 9090
ENTRYPOINT ["java", "-jar", "app.jar"]