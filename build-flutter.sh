#!/bin/bash
set -e  # Exit on error

echo "Installing Flutter SDK..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 flutter
export PATH="$PWD/flutter/bin:$PATH"

flutter doctor -v
flutter config --enable-web

echo "Cleaning and getting dependencies..."
flutter clean
flutter pub get

echo "Building Flutter web release..."
flutter build web --release --verbose

echo "Build complete!"