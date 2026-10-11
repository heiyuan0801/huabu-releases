# 应用视觉资源

这些资源使用 Codex 内置 GPT 图片生成工具制作。`studio-*` 仅用于创作入口装饰，不作为用户作品、生成结果或社区数据。

- `app-icon.png`：通用不透明图标母版。
- `app-icon-macos.png`：保留相同标志的 macOS 透明圆角图标。
- `studio-image.png`、`studio-video.png`、`studio-chat.png`：透明背景入口插画。

四个平台的图标尺寸由 `flutter_launcher_icons` 根据 `pubspec.yaml` 生成；运行 `dart run flutter_launcher_icons` 可重新生成。保留母版，避免手动编辑平台尺寸文件。

## 最终生成提示词

### 通用图标

Use case: logo-brand. Asset type: production application icon master for a cross-platform Chinese AI creation app named 未来画布 (Future Canvas). Create ONE square icon, a clean original abstract folded canvas/ribbon mark suggesting imagination opening into a portal, bold legible silhouette with 2-3 broad interlocking planes, centered and balanced with generous safe space so it remains recognizable at 16px. Premium modern creative-studio aesthetic, refined dimensional highlights, smooth blue (#3788FF) to violet (#7958FF) gradient on the mark, a very subtle cyan edge. Deep navy #0B0D14 square full-bleed background, soft depth and a restrained glow, crisp professional edges. The mark occupies about 62% of square width. Not a letter, not a camera aperture, no tiny decoration. Deliver the icon artwork only, straight-on, square, high resolution. No wordmark, no Chinese or Latin letters, no frame, no watermark, no mockup device, no scene. Leave the background square and opaque: platforms will apply their own corner masks; do not paint a rounded outer square.

### macOS 图标变体

以 `app-icon.png` 为参考图片，启用透明背景：

Edit the attached application icon for macOS packaging. Preserve exactly the existing original blue-violet folded-canvas mark, its shape, gradients, size relative to its background, and deep navy background color. Put the entire existing square artwork onto one centered rounded macOS-style squircle plate occupying 88% of the image width and height with equal clear margins on all sides. Corners smoothly rounded in the familiar macOS app icon style. The area outside the plate must be fully alpha-transparent. Keep the mark unchanged, centered, crisp and readable, no added objects, no words, no logo text, no watermark, no mockup scene, straight-on square icon artwork. A very restrained soft shadow under the plate is fine; do not use a big glow.

### 图片入口

Use case: decorative website/app hero artwork, not user-generated content. Create one premium studio illustration for an AI image-creation entry, a luminous translucent blue-violet folded photographic print showing an original dreamy moonlit mountain and tiny warm sun, a second smaller print behind it, floating on a completely transparent background. Crisp dimensional product illustration, refined glass and matte paper, cyan blue #3788FF and violet #7958FF with restrained peach accent. Centered square composition, compact silhouette, safe margins, legible at 100px. No text, no logos, no letters, no watermark, no app UI, no outer frame. True alpha transparency outside the object.

### 视频入口

Use case: decorative website/app hero artwork, not user-generated content. Create one premium studio illustration for an AI video-creation entry, an original sculptural blue-violet cinema clapperboard with a smooth luminous translucent play triangle, subtle amber-lit inset, floating on a completely transparent background. Refined glass and matte metal, cyan blue #3788FF and violet #7958FF with restrained peach accent. Centered square composition, compact silhouette, safe margins, legible at 100px, visually coherent with a modern AI creative studio. No text, no numbers, no logos, no letters, no watermark, no app UI, no outer frame. True alpha transparency outside the object.

### 聊天入口

Use case: decorative website/app hero artwork, not user-generated content. Create one premium studio illustration for an AI chat entry, two original smooth dimensional overlapping speech bubbles, one luminous translucent cyan-blue and one violet glass, with three large subtle raised dots in the front bubble. Floating on a completely transparent background. Refined glass and matte finish, cyan blue #3788FF and violet #7958FF, a restrained peach highlight. Centered square composition, compact silhouette, safe margins, legible at 100px, visually coherent with a modern AI creative studio. No text, no logos, no letters, no watermark, no app UI, no outer frame. True alpha transparency outside the object.
