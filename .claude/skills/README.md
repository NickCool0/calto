# Agent skills

Skills Claude Code uses while developing calto. Directory names match each skill's `name:` frontmatter.

| Skill | Source | In git? |
|---|---|---|
| `macos-build` (upstream `build/`), `macos-patterns`, `macos-settings-ui` (upstream `settings-ui/`) | [fayazara/macos-app-skills](https://github.com/fayazara/macos-app-skills) @ `a60365a`, MIT © fayazara | yes |
| `swiftui-specialist`, `swiftui-whats-new-27`, `test-modernizer`, `audit-xcode-security-settings` | [superagents-lab/xcode27-skills](https://github.com/superagents-lab/xcode27-skills) @ `6f9ff8d` | **no** — run `scripts/fetch-skills.sh` |

The xcode27-skills content was authored by Apple and exported from Xcode 27; its redistributor grants
no license over it, so it is not committed to this MIT-licensed repository.

Not used (irrelevant to this project): `uikit-app-modernization`, `c-bounds-safety`, `device-interaction`
(iOS/C), `auto-update` (Sparkle — third-party dependency), `release` (notarization — needs a paid Apple
Developer account), `notch-ui`.
