from pathlib import Path

path = Path('LandlineMac/ContentView.swift')
text = path.read_text()

old = '''    private var isMuted: Bool { micState == .muted }\n    private var isTalking: Bool { micState == .talking }\n    private var isModalPresented: Bool { showProfile || showAddUser }\n\n    private var modalVeilOpacity: Double {\n'''
new = '''    private var isMuted: Bool { micState == .muted }\n    private var isTalking: Bool { micState == .talking }\n    private var isModalPresented: Bool { showProfile || showAddUser }\n\n    // Match the two sheets by travel speed rather than raw duration.\n    // Profile travels 672 pt in 0.28 s; Add User travels 480 pt in 0.20 s.\n    // Both therefore move at approximately 2400 pt/s.\n    private let profileSheetAnimationDuration = 0.28\n    private let addUserSheetAnimationDuration = 0.20\n\n    private var modalVeilOpacity: Double {\n'''
if old not in text:
    raise SystemExit('Animation constant insertion point not found')
text = text.replace(old, new, 1)

old = '''            ModalBackdropBlurView()\n                .frame(width: 320, height: 672)\n                .opacity(isModalPresented ? 0.62 : 0)\n                .allowsHitTesting(false)\n                .animation(.easeOut(duration: 0.28), value: showProfile)\n                .animation(.easeOut(duration: 0.10), value: showAddUser)\n                .zIndex(19)\n'''
new = '''            ModalBackdropBlurView()\n                .frame(width: 320, height: 672)\n                // The pre-polish treatment targeted a 25 pt blur. Keep the\n                // edge-safe backdrop implementation, but blend it at 75% to\n                // approximate that treatment at roughly 25% less strength.\n                .opacity(isModalPresented ? 0.75 : 0)\n                .allowsHitTesting(false)\n                .animation(.easeOut(duration: profileSheetAnimationDuration), value: showProfile)\n                .animation(.easeOut(duration: addUserSheetAnimationDuration), value: showAddUser)\n                .zIndex(19)\n'''
if old not in text:
    raise SystemExit('Modal backdrop block not found')
text = text.replace(old, new, 1)

old = '''                .animation(.easeOut(duration: 0.28), value: showProfile)\n                .animation(.easeOut(duration: 0.10), value: showAddUser)\n                .zIndex(20)\n'''
new = '''                .animation(.easeOut(duration: profileSheetAnimationDuration), value: showProfile)\n                .animation(.easeOut(duration: addUserSheetAnimationDuration), value: showAddUser)\n                .zIndex(20)\n'''
if old not in text:
    raise SystemExit('Modal veil animation block not found')
text = text.replace(old, new, 1)

old = '''            .allowsHitTesting(showProfile)\n            .animation(.easeOut(duration: 0.28), value: showProfile)\n            .zIndex(21)\n'''
new = '''            .allowsHitTesting(showProfile)\n            .animation(.easeOut(duration: profileSheetAnimationDuration), value: showProfile)\n            .zIndex(21)\n'''
if old not in text:
    raise SystemExit('Profile sheet animation block not found')
text = text.replace(old, new, 1)

old = '''            .allowsHitTesting(showAddUser)\n            .animation(.easeOut(duration: 0.10), value: showAddUser)\n            .zIndex(22)\n'''
new = '''            .allowsHitTesting(showAddUser)\n            .animation(.easeOut(duration: addUserSheetAnimationDuration), value: showAddUser)\n            .zIndex(22)\n'''
if old not in text:
    raise SystemExit('Add User sheet animation block not found')
text = text.replace(old, new, 1)

old = '''                    try? await Task.sleep(for: .milliseconds(110))\n'''
new = '''                    try? await Task.sleep(for: .milliseconds(210))\n'''
if old not in text:
    raise SystemExit('Add User focus delay not found')
text = text.replace(old, new, 1)

path.write_text(text)
