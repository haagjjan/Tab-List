# Build Setup after every core code change

This documents the setup process to use, to have a clean build after every major code change

## Correct workflow after every code change

### 1. Stop the previous build

In Xcode, press the square Stop button or `Cmd-.`.

Then verify:

```sh
pkill -x TabList 2>/dev/null || true
pgrep -x TabList || echo "Ready to rebuild"
```

Do not rely on closing the Settings window.

### 2. Regenerate the project only when necessary

Run XcodeGen when you changed:

- `project.yml`
- package dependencies
- target configuration
- resource declarations
- file or target structure

```sh
cd /Users/janva/Projects/Tab-List
xcodegen generate
```

For ordinary changes inside an existing Swift file, this is unnecessary.

### 3. Select the canonical manual-test build

In Xcode, select:

- Scheme: `TabList`
- Destination: `My Mac`
- Build configuration: `Debug`

Do not manually run:

- `TabList-CI`
- the Release application
- anything found through Spotlight
- anything under `build/DerivedData`

### 4. Build and launch

Press `Cmd-R`.

Always launch the development application from Xcode. This establishes one canonical application path:

```text
~/Library/Developer/Xcode/DerivedData/TabList-…/Build/Products/Debug/TabList.app
```

### 5. Restore permissions

The current Debug build uses ad-hoc signing. Its signing identity changes when the executable changes, which can make Accessibility appear granted in System Settings while the newly built executable is not trusted.

If Accessibility is not recognized:

1. Stop Tab‑List.
2. Run:

```sh
cd /Users/janva/Projects/Tab-List
Scripts/reset_debug_accessibility.sh
```

3. Press `Cmd-R`.
4. Select **Request Accessibility**.
5. Enable the newly listed Tab‑List entry.
6. Stop and restart the application once.

For Thumbnail mode, if required:

```sh
tccutil reset ScreenCapture com.haagjjan.TabList
```

Then launch again, select **Enable Thumbnails**, grant Screen Recording, and restart Tab‑List.

### 6. Test the change

Check that only one process exists before testing:

```sh
pgrep -afil '/TabList.app/Contents/MacOS/TabList'
```

There should be exactly one result, pointing to the Xcode Debug product.
sd
### 7. Finish the test session

Use one of:

- Xcode’s Stop button
- `Cmd-.`
- Tab‑List menu-bar menu → **Quit Tab‑List**

Then verify:

```sh
pgrep -x TabList || echo "Tab-List stopped correctly"
```

## Running the full automated suite

Do not run the interactive Debug application and CI simultaneously.

```sh
cd /Users/janva/Projects/Tab-List

pkill -x TabList 2>/dev/null || true
Scripts/ci.sh
pkill -x TabList 2>/dev/null || true
```

The final `pkill` prevents a UI-test-launched accessory process from remaining active.

For normal development, the rule is simple: **one Xcode Debug build, launched only through `Cmd-R`, with Launch at Login disabled.**