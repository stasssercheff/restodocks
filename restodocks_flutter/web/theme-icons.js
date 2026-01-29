// Dynamic icon switching based on color scheme
(function() {
  function updateIcons() {
    const isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;

    // Update favicon
    const favicon = document.querySelector('link[rel="icon"]');
    if (favicon) {
      favicon.href = isDark ? 'icons/Icon-192-dark.png' : 'icons/Icon-192.png';
    }

    // Update apple-touch-icon
    const appleIcon = document.querySelector('link[rel="apple-touch-icon"]');
    if (appleIcon) {
      appleIcon.href = isDark ? 'icons/Icon-192-dark.png' : 'icons/Icon-192.png';
    }

    // Update manifest link if needed
    const manifestLink = document.querySelector('link[rel="manifest"]');
    if (manifestLink) {
      // Force reload manifest
      manifestLink.href = manifestLink.href + '?v=' + Date.now();
    }
  }

  // Update icons on load
  updateIcons();

  // Listen for theme changes
  if (window.matchMedia) {
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', updateIcons);
  }
})();