#!/bin/bash

set -e

echo "Setting up A/B testing for app icons..."

# Check if icons folder exists and has PNG files
if [ ! -d "$ICONS_FOLDER_PATH" ] || [ ! "$(ls -A "$ICONS_FOLDER_PATH"/*.png 2>/dev/null)" ]; then
  echo "⚠️  FOLDER NOT FOUND OR EMPTY - A/B TEST ICONS NOT APPLIED"
  echo "Folder '$ICONS_FOLDER_PATH' is missing or contains no PNG files"
  echo "Skipping A/B test icons setup"
  exit 0
fi

UNITY_APP_DIR="$XCODE_PROJECT_DIR"

# Find the exact paths based on the known structure
PROJECT_FILE=$(find "$XCODE_PROJECT_DIR" -name "project.pbxproj" | head -n 1)
if [ ! -f "$PROJECT_FILE" ]; then
  echo "Error: project.pbxproj not found. Listing $XCODE_PROJECT_DIR:"
  find "$XCODE_PROJECT_DIR" -name "*.xcodeproj" | sort
  exit 1
fi
echo "Found project file at: $PROJECT_FILE"

# Find Assets catalog
ASSET_CATALOG_DIR=$(find "$XCODE_PROJECT_DIR" -name "*.xcassets" | head -n 1)
if [ -z "$ASSET_CATALOG_DIR" ]; then
  echo "Warning: Could not find *.xcassets directory"
  XCODE_PROJ_DIR=$(dirname "$PROJECT_FILE")
  PARENT_DIR=$(dirname "$XCODE_PROJ_DIR")
  ASSET_CATALOG_DIR="$PARENT_DIR/Images.xcassets"
  mkdir -p "$ASSET_CATALOG_DIR"
  echo "Created asset catalog at: $ASSET_CATALOG_DIR"
else
  echo "Found asset catalog at: $ASSET_CATALOG_DIR"
fi

# Set AppIcon directory
APPICON_DIR="$ASSET_CATALOG_DIR/AppIcon.appiconset"

# Create AppIcon.appiconset if it doesn't exist
if [ ! -d "$APPICON_DIR" ]; then
  echo "Creating AppIcon.appiconset at $APPICON_DIR"
  mkdir -p "$APPICON_DIR"
  
  # Create a basic Contents.json
  cat > "$APPICON_DIR/Contents.json" << 'EOF'
{
  "images": [
    {
      "filename": "Icon-iPhone-120.png",
      "idiom": "iphone",
      "scale": "2x",
      "size": "60x60"
    },
    {
      "filename": "Icon-iPhone-180.png",
      "idiom": "iphone",
      "scale": "3x",
      "size": "60x60"
    },
    {
      "filename": "Icon-iPad-76.png",
      "idiom": "ipad",
      "scale": "1x",
      "size": "76x76"
    },
    {
      "filename": "Icon-iPad-152.png",
      "idiom": "ipad",
      "scale": "2x",
      "size": "76x76"
    },
    {
      "filename": "Icon-Store-1024.png",
      "idiom": "ios-marketing",
      "scale": "1x",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
EOF
fi

# Debug output for final paths
echo "Using paths:"
echo "- Xcode project: $XCODE_PROJECT_DIR"
echo "- Unity app: $UNITY_APP_DIR"
echo "- Asset catalog: $ASSET_CATALOG_DIR"
echo "- App icon: $APPICON_DIR"
echo "- Project file: $PROJECT_FILE"

# Process each icon in the specified folder
ALTERNATE_ICON_SETS=""
for icon_file in $ICONS_FOLDER_PATH/*.png; do
  if [ ! -f "$icon_file" ]; then
    echo "⚠️  FOLDER NOT FOUND OR EMPTY - A/B TEST ICONS NOT APPLIED"
    echo "No PNG files found in folder $ICONS_FOLDER_PATH"
    echo "Skipping A/B test icons setup"
    exit 0
  fi
  
  # Get icon name without extension
  icon_basename=$(basename "$icon_file")
  icon_name="${icon_basename%.*}"
  echo "Processing icon: $icon_name"
  
  # Create new appiconset directory within the Assets catalog
  NEW_APPICON_DIR="${ASSET_CATALOG_DIR}/${icon_name}.appiconset"
  mkdir -p "$NEW_APPICON_DIR"
  echo "Created new appiconset at: $NEW_APPICON_DIR"
  
  # Copy or create Contents.json
  if [ -f "$APPICON_DIR/Contents.json" ]; then
    # Copy the original Contents.json
    cp "$APPICON_DIR/Contents.json" "$NEW_APPICON_DIR/Contents.json"
    echo "Copied Contents.json from original AppIcon"
  else
    # Create a basic Contents.json
    cat > "$NEW_APPICON_DIR/Contents.json" << 'EOF'
{
  "images": [
    {
      "filename": "Icon-iPhone-120.png",
      "idiom": "iphone",
      "scale": "2x",
      "size": "60x60"
    },
    {
      "filename": "Icon-iPhone-180.png",
      "idiom": "iphone",
      "scale": "3x",
      "size": "60x60"
    },
    {
      "filename": "Icon-iPad-76.png",
      "idiom": "ipad",
      "scale": "1x",
      "size": "76x76"
    },
    {
      "filename": "Icon-iPad-152.png",
      "idiom": "ipad",
      "scale": "2x",
      "size": "76x76"
    },
    {
      "filename": "Icon-Store-1024.png",
      "idiom": "ios-marketing",
      "scale": "1x",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
EOF
    echo "Created new Contents.json for $icon_name"
  fi
  
  # Create icon variations
  echo "Generating icon variations for $icon_name..."
  
  # Generate all required sizes
  convert "${icon_file}" -resize 1024x1024 "${NEW_APPICON_DIR}/Icon-Store-1024.png"
  convert "${icon_file}" -resize 152x152 "${NEW_APPICON_DIR}/Icon-iPad-152.png"
  convert "${icon_file}" -resize 167x167 "${NEW_APPICON_DIR}/Icon-iPad-167.png"
  convert "${icon_file}" -resize 76x76 "${NEW_APPICON_DIR}/Icon-iPad-76.png"
  convert "${icon_file}" -resize 20x20 "${NEW_APPICON_DIR}/Icon-iPad-Notification-20.png"
  convert "${icon_file}" -resize 40x40 "${NEW_APPICON_DIR}/Icon-iPad-Notification-40.png"
  convert "${icon_file}" -resize 29x29 "${NEW_APPICON_DIR}/Icon-iPad-Settings-29.png"
  convert "${icon_file}" -resize 58x58 "${NEW_APPICON_DIR}/Icon-iPad-Settings-58.png"
  convert "${icon_file}" -resize 40x40 "${NEW_APPICON_DIR}/Icon-iPad-Spotlight-40.png"
  convert "${icon_file}" -resize 80x80 "${NEW_APPICON_DIR}/Icon-iPad-Spotlight-80.png"
  convert "${icon_file}" -resize 120x120 "${NEW_APPICON_DIR}/Icon-iPhone-120.png"
  convert "${icon_file}" -resize 180x180 "${NEW_APPICON_DIR}/Icon-iPhone-180.png"
  convert "${icon_file}" -resize 40x40 "${NEW_APPICON_DIR}/Icon-iPhone-Notification-40.png"
  convert "${icon_file}" -resize 60x60 "${NEW_APPICON_DIR}/Icon-iPhone-Notification-60.png"
  convert "${icon_file}" -resize 29x29 "${NEW_APPICON_DIR}/Icon-iPhone-Settings-29.png"
  convert "${icon_file}" -resize 58x58 "${NEW_APPICON_DIR}/Icon-iPhone-Settings-58.png"
  convert "${icon_file}" -resize 87x87 "${NEW_APPICON_DIR}/Icon-iPhone-Settings-87.png"
  convert "${icon_file}" -resize 120x120 "${NEW_APPICON_DIR}/Icon-iPhone-Spotlight-120.png"
  convert "${icon_file}" -resize 80x80 "${NEW_APPICON_DIR}/Icon-iPhone-Spotlight-80.png"
  
  echo "Icon $icon_name processed successfully"
  
  # Build a list of all icon sets for modifying the project file
  if [ -z "$ALTERNATE_ICON_SETS" ]; then
    ALTERNATE_ICON_SETS="$icon_name"
  else
    ALTERNATE_ICON_SETS="$ALTERNATE_ICON_SETS,$icon_name"
  fi
done

# If we didn't find any icons, exit gracefully
if [ -z "$ALTERNATE_ICON_SETS" ]; then
  echo "⚠️  FOLDER NOT FOUND OR EMPTY - A/B TEST ICONS NOT APPLIED"
  echo "No icons processed from folder $ICONS_FOLDER_PATH"
  echo "Skipping A/B test icons setup"
  exit 0
fi

echo "Successfully created alternate app icon sets: $ALTERNATE_ICON_SETS"

# Modify Xcode project to include all app icon assets
echo "Modifying Xcode project to include all app icon assets..."

# Back up the project file
cp "$PROJECT_FILE" "${PROJECT_FILE}.bak"

# 1. Add ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES to project.pbxproj
# This needs to be added to each buildSettings section
perl -i -pe 's/(buildSettings = \{)/\1\n\t\t\t\tASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;/g' "$PROJECT_FILE"

# 2. Find the default app icon set name - assumes AppIcon
PRIMARY_ICON_NAME="AppIcon"

# 3. Add PRIMARY_APP_ICON_SET_NAME setting to project.pbxproj
perl -i -pe 's/(ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;)/\1\n\t\t\t\tPRIMARY_APP_ICON_SET_NAME = '"$PRIMARY_ICON_NAME"';/g' "$PROJECT_FILE"

# 4. Add ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES setting to project.pbxproj
perl -i -pe 's/(PRIMARY_APP_ICON_SET_NAME = '"$PRIMARY_ICON_NAME"';)/\1\n\t\t\t\tASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "'"$ALTERNATE_ICON_SETS"'";/g' "$PROJECT_FILE"

# Verify the changes were made successfully
if grep -q "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES" "$PROJECT_FILE"; then
  echo "Successfully added ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES to project.pbxproj"
else
  echo "Failed to add ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES to project.pbxproj"
  cat "$PROJECT_FILE" | grep -A 3 "buildSettings"
  exit 1
fi

if grep -q "PRIMARY_APP_ICON_SET_NAME = $PRIMARY_ICON_NAME" "$PROJECT_FILE"; then
  echo "Successfully added PRIMARY_APP_ICON_SET_NAME = $PRIMARY_ICON_NAME to project.pbxproj"
else
  echo "Failed to add PRIMARY_APP_ICON_SET_NAME to project.pbxproj"
  exit 1
fi

if grep -q "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES" "$PROJECT_FILE"; then
  echo "Successfully added ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES to project.pbxproj"
else
  echo "Failed to add ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES to project.pbxproj"
  exit 1
fi

echo "A/B testing for app icons setup completed"

# Archive original icons for debugging
mkdir -p /tmp/ab_testing_debug/original_icons
cp -r "$ICONS_FOLDER_PATH"/*.png /tmp/ab_testing_debug/original_icons/

# Archive generated icon sets for debugging
mkdir -p /tmp/ab_testing_debug/generated_icons
cp -r "$ASSET_CATALOG_DIR"/*.appiconset /tmp/ab_testing_debug/generated_icons/