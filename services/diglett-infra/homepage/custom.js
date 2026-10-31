// Copied to /mnt/nas/docker/homepage by the infra Ansible role.
//
// services.yaml links to <host>.home, which resolves to a LAN-only IP. When the
// dashboard itself is opened as pokedex.wsh (over the tailnet), rewrite those
// links to <host>.wsh so they stay reachable off-LAN.
(function () {
  if (!window.location.hostname.endsWith(".wsh")) return;
  const rewrite = (root) => {
    root.querySelectorAll('a[href*=".home"]').forEach((a) => {
      try {
        const url = new URL(a.href);
        if (url.hostname.endsWith(".home")) {
          url.hostname = url.hostname.slice(0, -".home".length) + ".wsh";
          a.href = url.toString();
        }
      } catch (e) {
        // ignore unparseable hrefs
      }
    });
  };
  rewrite(document);
  new MutationObserver(() => rewrite(document)).observe(document.body, {
    childList: true,
    subtree: true,
  });
})();
