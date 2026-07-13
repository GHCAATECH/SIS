(function () {
  function closeMenu(toggle, panel, backdrop) {
    panel.classList.remove('open');
    backdrop.classList.remove('open');
    toggle.setAttribute('aria-expanded', 'false');
    document.body.classList.remove('public-nav-open');
  }

  document.querySelectorAll('[data-public-menu-toggle]').forEach(function (toggle) {
    var panelId = toggle.getAttribute('aria-controls');
    var panel = document.getElementById(panelId);
    var backdrop = document.querySelector('[data-public-menu-backdrop]');
    if (!panel || !backdrop) return;

    toggle.addEventListener('click', function () {
      var isOpen = panel.classList.toggle('open');
      backdrop.classList.toggle('open', isOpen);
      toggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      document.body.classList.toggle('public-nav-open', isOpen);
    });

    backdrop.addEventListener('click', function () {
      closeMenu(toggle, panel, backdrop);
    });

    panel.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        closeMenu(toggle, panel, backdrop);
      });
    });

    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && panel.classList.contains('open')) {
        closeMenu(toggle, panel, backdrop);
      }
    });
  });
}());
