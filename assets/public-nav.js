(function () {
  var menuToggle = document.getElementById('menuToggle');
  var mobileSidebar = document.getElementById('mobileSidebar');
  var sidebarOverlay = document.getElementById('sidebarOverlay');
  var sidebarClose = document.getElementById('sidebarClose');
  var sidebarLinks = document.querySelectorAll('.sidebar-nav a');

  if (!menuToggle || !mobileSidebar || !sidebarOverlay || !sidebarClose) return;

  function openSidebar() {
    mobileSidebar.classList.add('active');
    sidebarOverlay.classList.add('active');
    document.body.classList.add('menu-open');
    menuToggle.setAttribute('aria-expanded', 'true');
  }

  function closeSidebar() {
    mobileSidebar.classList.remove('active');
    sidebarOverlay.classList.remove('active');
    document.body.classList.remove('menu-open');
    menuToggle.setAttribute('aria-expanded', 'false');
  }

  menuToggle.addEventListener('click', openSidebar);
  sidebarClose.addEventListener('click', closeSidebar);
  sidebarOverlay.addEventListener('click', closeSidebar);

  sidebarLinks.forEach(function (link) {
    link.addEventListener('click', closeSidebar);
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') closeSidebar();
  });

  window.addEventListener('resize', function () {
    if (window.innerWidth > 768) closeSidebar();
  });
}());
