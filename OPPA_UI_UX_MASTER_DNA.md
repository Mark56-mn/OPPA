# OPPA UI/UX MASTER DNA
Version: 1.0
Status: Master visual and interaction specification
Audience: Figma designers, Flutter engineers, Codex, UI agents, QA agents

## 0. Purpose
This is OPPA's visual and interaction source of truth. Build one coherent mobile-first product, not unrelated screens. The underlying functionality is shared across themes; theme changes presentation only.

## 1. Approved themes
1. Fluid Africa — warm, expressive, culturally inspired
2. OPPA Pulse — futuristic, dark, energetic
3. Everyday OPPA — clean, lightweight, practical
OPPA Pulse is the official logo/brand direction. The orb/pulse may animate, but visual presentation must never make security or financial decisions.

## 2. Product visual principles
- Mobile-first and native-feeling.
- One information architecture and one component system.
- Use semantic design tokens; do not scatter hard-coded theme values.
- Accessibility and readability outrank decoration.
- Financial screens prioritize clarity and confirmation.
- Security screens use plain language and visible status.
- Loading, empty, error, offline, disabled and success states are first-class designs.
- Do not imitate another company's proprietary interface or branding.
- 3D/Spline effects are optional presentation only and must not harm performance or accessibility.

## 3. Design token architecture
Token families: color.*, type.*, space.*, radius.*, elevation.*, motion.*, control.*.
Semantic colors: background, surface, surfaceElevated, surfaceMuted, textPrimary, textSecondary, textMuted, border, accent, accentStrong, onAccent, success, warning, danger, info, scrim.
Typography: display, headline, title, body, bodyMedium, label, caption, numericLarge, numericMedium.
Spacing baseline: 4, 8, 12, 16, 20, 24, 32, 40, 48 dp.
Touch targets: minimum 44 dp. Standard primary button target: 52 dp.
Exact brand colors, font files and measured pixel values are to be locked during the visual reference pass; agents must not invent conflicting token families.

## 4. Theme DNA
Fluid Africa: warm surfaces, expressive accents, organic shapes, human imagery, organic motion, moderate pulse/3D.
OPPA Pulse: dark layered surfaces, high contrast, restrained glow, energetic transitions, stronger orb/pulse, 3D reserved for hero moments.
Everyday OPPA: restrained surfaces, compact hierarchy, minimal motion and 3D, low-end-device performance first.
Theme belongs to the user, not the conversation. Changing theme cannot change account data, chats, wallet state, permissions or security.

## 5. Navigation
Onboarding → Home → Chat/Conversation → Contacts → Calls → Wallet → Business → Me.
Me: Profile, OPPA ID, Appearance, Devices, Privacy, Security, Notifications, Wallet settings, Account, Help & Support.
OPPA Connect: Browser, Privacy, VPN (future).
Business: Inbox, Customers, Products, Orders, Payments, Analytics.
Control Center: Dashboard, Users, Wallet, Payments, Messaging, WhatsApp, Fraud, Security, Support, Staff, Audit.

## 6. Complete screen inventory
Authentication: Splash, Welcome, Phone number, OTP, Create profile, Choose Theme, Permissions, Device/Security setup, Completion.
Communication: Home, Chats, Conversation, New conversation, Contact profile, Group creation, Group details, Group members, Media viewer, Voice notes, Call history, Incoming call, Active voice call, Active video call, Missed call, Search, Notifications, Link preview, Report/Block.
Wallet: Wallet dashboard, Wallet onboarding, Fund wallet, Send money, Recipient selection, Amount, Transfer review, Step-up authentication, Processing, Success, Failed, Pending, Receive, Request, Transaction history, Transaction detail, Wallet settings, Limits/fees, Dispute/help.
Business: Business onboarding, Business profile, Dashboard, Inbox, Customers, Customer detail, Products, Product editor, Orders, Order detail, Payments, Payment link, Analytics.
Me/Trust: Me, Edit profile, OPPA ID, Appearance, Devices, Security Center, Security alert detail, Privacy Center, Notifications, Wallet security, Account, Data export, Account deletion, Help, FAQ, Trust Center.
Connectivity: OPPA Connect, Browser, Browser privacy, Safe browsing warning, future VPN controls.
Control Center: Dashboard, User management, User detail, Wallet operations, Payment operations, Messaging operations, WhatsApp operations, Fraud/Risk, Security operations, Support, Staff/RBAC, Audit viewer, Emergency Center, System health.

## 7. Universal screen anatomy
Use OS safe area, app header, primary content, contextual actions and bottom navigation where appropriate. Use keyboard-safe layouts. Use bottom sheets for short contextual actions and full-screen flows for high-risk financial/security actions. Default horizontal content inset is 16 dp unless hierarchy requires otherwise.

## 8. Component DNA
App header: title, optional subtitle/status, leading navigation and contextual action.
Primary button: high contrast, 52 dp target, theme radius, stable width during loading, readable disabled state, distinct destructive state.
Inputs: visible labels, focus state, inline validation, appropriate keyboard type, never placeholder-only.
Cards: semantic grouping, predictable padding, elevation only when needed.
Bottom sheets: drag affordance where relevant, rounded top corners, safe-area handling, explicit close/confirm.
Chat bubble: sender/receiver distinction, timestamp/status, media/reply/reaction/failed-send states.
Wallet balance card: clear amount and currency, hide/show control, recent activity. Never animate an unconfirmed balance as settled.
Security status: Protected, Action required, Review needed, Device removed, Session expired.

## 9. Interaction states
Every interactive component defines default, pressed, focused, disabled, loading, success, warning and error states; offline where relevant.
Every async screen defines initial, loading, loaded, empty, retryable error, terminal error, offline and permission-denied states where relevant.
Financial state machine: draft → review → authorization → processing → success/pending/failure. Never display success before server confirmation.

## 10. Motion DNA
Fluid Africa: organic and soft. OPPA Pulse: energetic and layered. Everyday OPPA: subtle and short.
Respect reduced-motion settings. Never communicate essential information only through animation. Avoid infinite animation on critical screens.

## 11. Accessibility
Minimum 44 dp targets, semantic icon labels, dynamic font scaling, adequate contrast, state not conveyed by color alone, correct screen-reader order, focus management, reduced motion, localization-ready strings, no critical text embedded in raster images, readable financial figures.

## 12. Low-data and offline UX
Cache appropriate chats/profile data, support drafts and safe outbox operations. Wallet display may show cached balance with timestamp/status; settlement remains server-authoritative. Never represent an offline transfer as completed. Clearly label Offline, Queued, Last updated or Retry.

## 13. Security Center UX
Settings → Security.
Show: phone verification, recovery status, active devices, messaging encryption status, wallet PIN/biometric status, active sessions, recent security alerts and Review security.
Sensitive flows explain why verification is required and show operation summary. Never expose private keys or secrets.

## 14. Wallet UX
Send: Wallet → Send → Recipient → Amount → Review → security/risk authorization → Processing → server-confirmed result.
Review shows recipient, amount, currency, fee, total, resulting balance where appropriate and security requirement. No client-only balance mutation.

## 15. Business UX
Business is an extension of OPPA, not a separate visual product. Prioritize inbox, customers, products/orders, payments and simple analytics. Use progressive disclosure.

## 16. Browser/Connect UX
Link previews and safe in-app link handling may be V1. Later Browser includes back, forward, refresh, domain context, share, open externally, privacy controls and safe-browsing warnings. VPN is future scope and must never appear active when it is not.

## 17. Control Center UX
Desktop/tablet responsive web. Prioritize health, search, role-based visibility, audit context and explicit confirmation.
Emergency Center actions: pause wallet transfers, pause registrations, disable WhatsApp connections, disable merchant payments, maintenance mode. Consequential actions require authorized role, confirmation, reason, audit event and dual approval where policy requires.

## 18. Visual reconstruction protocol
1. Load base tokens.
2. Load theme tokens.
3. Build shared components.
4. Build navigation shell.
5. Build screen hierarchy.
6. Implement loading/empty/error/offline/success states.
7. Apply themes without changing information architecture.
8. Render screenshots at the reference viewport.
9. Compare spacing, hierarchy, typography, icon placement, surfaces and state.
10. Fix tokens/components instead of adding one-off hacks.
11. Repeat until intentional deviations are documented.
When approved reference images exist, those references outrank guesses and their measurable DNA must be recorded here or in the project design source.

## 19. Reference DNA schema
For every approved reference screen record: screen_id, viewport_width, viewport_height, device_pixel_ratio, safe_area, theme, background, header_bounds, content_bounds, navigation_bounds, component_bounds, typography_tokens, color_tokens, corner_radii, shadows, icon_assets, image_assets, motion_notes, interaction_states and accessibility_notes.
Do not infer exact pixels from a differently sized screenshot without accounting for viewport and device scale.

## 20. Asset DNA
Official reusable assets: OPPA Pulse/orb logo, app icon, theme illustrations, avatars/placeholders, wallet/payment icons, security icons, business icons and browser icons. Prefer vector assets. Do not embed critical text in raster assets.

## 21. Copy DNA
Tone: clear, warm, confident, concise, non-technical for ordinary users and transparent around money/security.
Preferred labels: Send money, Review transfer, Confirm, Protected, Review security, Try again, You're offline, Transfer pending.
Avoid unexplained backend terminology, fear-inducing security copy, false certainty and claims that messages/transactions are invisible to OPPA unless technically true.

## 22. Agent implementation contract
Read this file before UI work. Inspect existing code first. Use one shared token system. Do not duplicate theme implementations. Preserve accessibility. Implement important states. Keep financial/security presentation server-state-driven. Use responsive layouts. Test critical navigation/flows. Compare screenshots to approved references when available. Never claim pixel-perfect fidelity without comparison evidence.

## 23. Scope
V1: onboarding, Home/Chats, conversation, contacts/groups, calls, wallet/send/receive/transactions, business, Me/settings, Security Center, notifications, admin/control center, in-app links.
V1.5: richer OPPA Browser.
V2: OPPA Connect/VPN.
Future: Mini Apps and additional platform experiences.

## 24. Definition of done
UI is complete only when required screens exist, shared components are used, all three themes are supported where applicable, critical states are designed, accessibility checks pass, navigation works, no placeholder UI remains in the claimed scope, wallet/security flows never imply unconfirmed success, responsive behavior is verified, screenshots are compared when references exist, build/typecheck/tests actually pass when executable, and known visual deviations are documented.

## 25. Relationship to engineering source of truth
UI/UX source: this file. Product/engineering sources: OPPA_MASTER_BUILD_SPEC.md, CODEX_BUILD_MAP.md, CODEX_AUTOPILOT.md, CODEX_SPEED_PROTOCOL.md and CODEX_HANDOFF.md. If sources conflict, inspect the current repository and document the conflict rather than silently choosing.