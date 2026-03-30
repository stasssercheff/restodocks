import 'dart:async';
import 'dart:html' as html;

/// При возврате на вкладку (visibilityState == visible) — обновить JWT.
StreamSubscription? subscribeAuthResumeOnVisibility(void Function() onVisible) {
  return html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') onVisible();
  });
}
