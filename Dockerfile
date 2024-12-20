# Use Maven and OpenJDK 11 to build the app
FROM maven:3-eclipse-temurin-11-alpine AS app-builder
RUN apk add --no-cache git
WORKDIR /build

# Copy the local source code into the Docker image
# Assume the source code is in the current directory
COPY . /build/veraPDF-rest

WORKDIR /build/veraPDF-rest

# Set the default branch for the repository
ARG GH_CHECKOUT
ENV GH_CHECKOUT=${GH_CHECKOUT:-master}

# Checkout the specific branch/tag/commit and build the app
RUN git checkout ${GH_CHECKOUT} && mvn clean package

# Now create a custom Java JRE for the Alpine image
FROM eclipse-temurin:11-jdk-alpine as jre-builder

# Create a custom Java runtime
RUN "$JAVA_HOME/bin/jlink" \
         --add-modules java.base,java.logging,java.xml,java.management,java.sql,java.desktop,jdk.crypto.ec \
         --strip-debug \
         --no-man-pages \
         --no-header-files \
         --compress=2 \
         --output /javaruntime

# Now create the final application image
FROM alpine:3

# Specify the veraPDF REST version
ARG VERAPDF_REST_VERSION
ENV VERAPDF_REST_VERSION=${VERAPDF_REST_VERSION:-1.27.1}

# Install dumb-init for process management
ADD --link https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_x86_64 /usr/local/bin/dumb-init 
RUN chmod +x /usr/local/bin/dumb-init

# Copy the custom Java runtime from the jre-builder stage
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${JAVA_HOME}/bin:${PATH}"
COPY --from=jre-builder /javaruntime $JAVA_HOME

# Create an unprivileged user for running the service
RUN addgroup -S verapdf-rest && adduser --system -D --home /opt/verapdf-rest -G verapdf-rest verapdf-rest
RUN mkdir --parents /var/opt/verapdf-rest/logs && chown -R verapdf-rest:verapdf-rest /var/opt/verapdf-rest

USER verapdf-rest
WORKDIR /opt/verapdf-rest

# Copy the application JAR and configuration files from the build stage
COPY --from=app-builder /build/veraPDF-rest/target/verapdf-rest-${VERAPDF_REST_VERSION}.jar /opt/verapdf-rest/verapdf-rest.jar
COPY --from=app-builder /build/veraPDF-rest/server.yml /var/opt/verapdf-rest/config/
COPY --from=app-builder /build/veraPDF-rest/config /opt/verapdf-rest/config/

VOLUME /var/opt/verapdf-rest
EXPOSE 8080

# Use dumb-init to handle PID 1 and manage Java process
ENTRYPOINT [ "dumb-init", "--" ]
CMD ["java", "-Djava.awt.headless=true", "-jar", "/opt/verapdf-rest/verapdf-rest.jar", "server", "/var/opt/verapdf-rest/config/server.yml"]
