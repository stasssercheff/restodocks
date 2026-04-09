// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:shared_preferences/shared_preferences.dart';

const _lsKey = 'restodocks_landscape_chrome_aggressive';
const _prefsKey = 'mobile_web_aggressive_chrome_landscape';

Future<bool> loadMobileWebChromeAggressiveLandscape() async {
  final p = await SharedPreferences.getInstance();
  if (!p.containsKey(_prefsKey)) {
    final fromLs = _readLs();
    await p.setBool(_prefsKey, fromLs);
    return fromLs;
  }
  final v = p.getBool(_prefsKey) ?? false;
  _writeLs(v);
  return v;
}

Future<void> saveMobileWebChromeAggressiveLandscape(bool value) async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_prefsKey, value);
  _writeLs(value);
  applyMobileWebChromeAggressiveToPage(value);
}

bool _readLs() {
  try {
    return html.window.localStorage[_lsKey] == '1';
  } catch (_) {
    return false;
  }
}

void _writeLs(bool value) {
  try {
    if (value) {
      html.window.localStorage[_lsKey] = '1';
    } else {
      html.window.localStorage.remove(_lsKey);
    }
  } catch (_) {}
}

void applyMobileWebChromeAggressiveToPage(bool enabled) {
  try {
    html.window.dispatchEvent(
      html.CustomEvent('restodocks-chrome-aggressive', detail: enabled),
    );
  } catch (_) {}
}
