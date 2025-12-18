FROM dart:stable AS runtime

WORKDIR /app

# Resolve package dependencies
COPY pubspec.* ./
RUN dart pub get

# Copy the rest of the source code
COPY . .

# Ensure dependencies are ready in the final image
RUN dart pub get --offline

# Expose WebSocket port
ENV PORT=8080
EXPOSE 8080

# Start the Dart WebSocket server
CMD ["dart", "app.dart"]

