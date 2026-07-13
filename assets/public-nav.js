(function () {
  var mobileMenuButton = document.getElementById('mobileMenuButton');
  var mobileCloseButton = document.getElementById('mobileCloseButton');
  var mobileSidebar = document.getElementById('mobileSidebar');
  var mobileOverlay = document.getElementById('mobileOverlay');
  var mobileLinks = document.querySelectorAll('.mobile-navigation a');

  if (!mobileMenuButton || !mobileCloseButton || !mobileSidebar || !mobileOverlay) return;

  function openMobileMenu() {
    mobileSidebar.classList.add('active');
    mobileOverlay.classList.add('active');
    document.body.classList.add('menu-open');
    mobileMenuButton.setAttribute('aria-expanded', 'true');
  }

  function closeMobileMenu() {
    mobileSidebar.classList.remove('active');
    mobileOverlay.classList.remove('active');
    document.body.classList.remove('menu-open');
    mobileMenuButton.setAttribute('aria-expanded', 'false');
  }

  mobileMenuButton.addEventListener('click', openMobileMenu);
  mobileCloseButton.addEventListener('click', closeMobileMenu);
  mobileOverlay.addEventListener('click', closeMobileMenu);

  mobileLinks.forEach(function (link) {
    link.addEventListener('click', closeMobileMenu);
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') closeMobileMenu();
  });

  window.addEventListener('resize', function () {
    if (window.innerWidth > 850) closeMobileMenu();
  });
}());
