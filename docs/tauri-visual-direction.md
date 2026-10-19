# cut / kpax visual direction

reference: D:/Projects/kpax/frontend and D:/Projects/kpaxvpn (read-only).

- black theme: #08080a / #f2f0ed / #a29fa8; light theme: #efefee / #242226 / #6e6a73.
- large self-hosted UnifrakturCook wordmark and English section headings; Nunito Sans for readable English labels and project names; restrained Newsreader for project initials.
- floating navigation, borderless matte glass panels, deep modal blur, soft monochrome light behind the workspace.
- preserve project/download/Resolve/archive behaviors. Persist appearance locally, apply the matching native title bar theme.
- remove Flutter source/build workflow; Tauri is the main Windows build and release path.

verification: theme restoration/storage tests, production build, Rust tests, native download/UI smoke test, screenshots in both themes and a modal; no live user project mutations.


copy rules: English; short action labels; no slogans, redundant folder captions, duplicated download panel or introductory paragraphs. Keep only error details and the consequences of delete/archive/restore. Premiere creation, launch and configuration removed; preserve imported files and manifests. Legacy manifests without an editor default to Resolve in memory only.

research: [generic patterns and interchangeable copy](https://blog.interfacekit.io/what-makes-a-website-look-ai-generated), [decorative filler and repeated headings](https://genjutsu.athevon.dev/docs/tells). These are design observations, not a reliable test of authorship. Gothic typography and matte blur are explicit user requirements.

verified 2026-10-19: 8 frontend tests, 23 Rust tests passed; 2 network tests ignored (previous live Drive verification retained). Native WebView smoke passed theme reload/persistence, native titlebar themes, local HTTP file download with byte comparison, modal blur, keyboard-accessible narrow-window project actions, no horizontal overflow. Removed duplicate prefixed backdrop-filter declarations: bundler previously retained only the unsupported prefixed spelling in WebView. Screenshots visually inspected in both themes and modal.


2.1.1 refinement: dialog overlay is transparent and has no filter; the dialog itself uses neutral black at 84% opacity with a 40px desaturated backdrop blur (light theme follows the light palette). Removed Sounds UI, library commands and default library setting, header theme toggle, duplicated inspector and its actions. A single project menu retains archive/restore/trash. Motion springs animate page/project/folder/modal entrances and button/nav/card interactions with reduced-motion support. Directory IPC validates the selected project path and id directly instead of rescanning all projects; entries cache lasts 30 seconds, download completion invalidates it, and manual refresh remains available.

Native QA: direct folder lookup 7ms in isolated test data; not a benchmark of the user's full catalog. 8 frontend tests and 24 Rust tests pass, 2 live network checks ignored. Native screenshots confirm sharp surroundings and black matte dialog, no inspector or Sounds navigation, theme selection through settings, narrow-window project actions. Resolve export and live cloud downloads were not repeated for this refinement.


2.2 supersedes the layout above: no top navigation or brand, sidebar creation and bottom settings, no central Projects title. Local footage frames become lazy project covers via installed ffmpeg, 2 workers maximum, 8s command timeout, disk cache with file fingerprint, no playback or network URLs. Manual refresh invalidates cached covers including empty results. Native preview and update scenarios passed; a frame was also extracted from the user's existing MP4 without changing it. Dialog tint reduced to 35% black / 48% white with 24px grayscale backdrop blur; surroundings remain sharp. Project/file scroll regions now share 14px gradient-masked backdrop edge blurs that respond to overflow and scroll offset. Final verification: 8 frontend and 26 Rust tests, 2 live tests ignored; native smoke and screenshots passed.


2.2.1: replaced the two-panel frame with a continuous ambient surface and a faint sidebar divider. Gothic sidebar projects title at 44px, no top bar. Fixed filters not returning from settings, added explicit Back to projects and settings toggle. Sidebar stays mounted across page transitions, AnimatePresence animates content only; layoutId selection highlights move between projects/filters and theme options. Native regression reproduced on 2.2.0 and passed on 2.2.1 with actual pointer hit tests, plus settled screenshots in both themes and form navigation. Confirmed both main regions have no panel box-shadow. 8 frontend tests and release/debug builds passed; backend unchanged.


2.2.2: removed ambient light orbs and outer control halos; global scrollbar visuals hidden while native scrolling remains. The sidebar controls now stick inside the project scrollport, so rows pass underneath a 26px gradient-masked backdrop blur. Local buttons/cards/fields have neutral matte blur, selected rows/filter pills have denser frosted material. FrostedSelection uses a slower damped layout spring and temporarily blurs only its background while moving (native samples 2.6px, 4.4px, 5px then settled 0px). Sticky header height sets scroll-padding-top; bottom padding protects focus from the lower fade. Native frost-smoke passed wheel, PageDown, Shift+Tab visibility, pinned controls, hidden scrollbar and animation state. Ordinary native smoke, 8 frontend tests and both builds passed.


2.2.3 supersedes moving blur: selection is now a 0.32s ease-out tween without spring or filter blur; native motion samples stayed inside endpoints. Sidebar header/footer surfaces bleed to the viewport edges with soft vertical masks, duplicate edge overlays and divider removed. Settings footer is sticky inside the list. Project view is one scrollport with a full-width sticky hero; native measurements verified its 1106px backdrop covers the entire 1106px header and exceeds its 191px height. Menu hit testing and keyboard focus passed during footage scrolling. Redundant editor badge and display names removed; internal identifiers and actual filesystem paths retained. New monochrome EH icon is generated from local UnifrakturCook; PNG/ICO/SVG, embedded Windows icon visually verified. 8 frontend and 26 Rust tests passed, 2 live checks ignored; both native smoke scripts passed.
