# ClipShelf icon

Generated with the built-in imagegen tool, then resized into the macOS iconset sizes using `sips` and packaged as ICNS. The script uses `iconutil`, with a direct PNG-container packer when `iconutil` is unavailable in a restricted environment. The PNG retains transparency outside the rounded tile.

- `AppIcon-source.png`: original generated artwork, 1254 × 1254.
- `AppIcon.icns`: application icon, 16 through 1024 pixels.
- `../scripts/build-icon.sh`: regenerates the icon package from the source.

Final generation prompt:

> Use case: logo-brand. Asset type: a polished native macOS application icon for ClipShelf, a minimal developer clipboard history app. Generate ONE square app icon, straight-on, centered, no mockup, no scene, no text or letters or watermark. Transparent canvas outside the rounded-square icon tile, generous standard macOS icon padding (~8% on each side). The tile is deep charcoal smoky frosted glass with rounded macOS squircle corners, subtle inset bevel and delicate top-left edge highlights. Centerpiece: a distinctive, very simple stack of three overlapping clipboard/snippet cards, slightly staggered toward the upper right, rear two cards dark translucent glass with subtle mint edges. Front card is a luminous mint-green rounded rectangle with a small dark inset clipboard tab at its top and two bold short dark horizontal code-like lines, no tiny details. Sophisticated mint/seafoam and charcoal palette to match a dark glass utility interface. Restrained dimensionality, soft internal lighting, crisp silhouette, extremely readable at 32px. High quality app-store icon craftsmanship, uncluttered, no surrounding decoration, no excessive glow. Square composition with alpha transparency beyond the outer tile.
