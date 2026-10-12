FROM eclipse-temurin:21-jdk-alpine AS build

WORKDIR /workspace

COPY gradlew ./gradlew
COPY gradle ./gradle
COPY services/service-b/build.gradle services/service-b/settings.gradle ./service-b/
COPY services/service-b/src ./service-b/src

WORKDIR /workspace/service-b

RUN chmod +x ../gradlew && ../gradlew clean bootJar --no-daemon

FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

ENV SERVER_PORT=9090

RUN addgroup -S spring && adduser -S spring -G spring

COPY --from=build /workspace/service-b/build/libs/*.jar app.jar

USER spring:spring

EXPOSE 9090

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
