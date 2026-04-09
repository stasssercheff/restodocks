/// Синхронизация прокрутки с document (мобильный Chrome/Safari) — только web.
void mobileBrowserChromeNudgeFromFlutterScroll() {}

/// Сразу после входа в альбом на телефоне — лучший доступный нудж (гарантий нет).
void mobileBrowserChromeNudgeOnLandscapeIfPhone() {}

/// Сдвиг window.scroll по вертикали (альбом в обычной вкладке): жест вверх от нижней панели.
void mobileBrowserChromeScrollDocumentBy(double deltaY) {}
