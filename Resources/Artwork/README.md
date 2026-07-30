# Artwork Source

`TabList-AppIcon-Source.png` is original project-owned artwork created for Tab-List on July 30, 2026. It was not copied from AltTab or another application.

The source image is intentionally outside the application resource target. `Scripts/generate_app_icons.swift` removes only the near-black background connected to the canvas corners, creates a soft alpha edge, and produces the complete macOS rendition set in `Resources/TabList/Assets.xcassets/AppIcon.appiconset`.

Regenerate and visually review every icon rendition after changing the source or conversion algorithm. Reference screenshots under `reference/` are behavioral design evidence and must never be used as distributable artwork.
