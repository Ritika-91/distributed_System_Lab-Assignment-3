# backend/Dockerfile (multi-stage)
FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /workspace

# copy only pom first for dependency caching
COPY pom.xml .
# If you have a parent with modules, adjust accordingly
RUN mvn -B -q dependency:go-offline

# copy source and build
COPY src ./src
RUN mvn -B -DskipTests package

# runtime image
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app

# Copy the built spring-boot fat jar (wildcard to avoid exact filename issues)
COPY --from=build /workspace/target/*.jar backend.jar

EXPOSE 8081
ENTRYPOINT ["java","-jar","/app/backend.jar"]
