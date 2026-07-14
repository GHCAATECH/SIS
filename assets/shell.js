/* =========================================================
   AXIOMBYTE SMS — shared shell + helpers
   Usage on each page:
     <script src="assets/shell.js"></script>
     <script>Portal.init({ active: 'cass' });</script>
   ========================================================= */
(function (w) {
  'use strict';

  var SCHOOL = { code: '0021101', name: 'ASUOM SENIOR HIGH SCHOOL', user: 'Admin' };

  // Single source of truth for navigation (key = filename without .html)
  var NAV = [
    {
      title: 'AXIOMBYTE SMS',
      items: [
        { key: 'dashboard',             label: 'Dashboard',              icon: 'fa-gauge-high' },
        { key: 'registerstudent',       label: 'Register Student',       icon: 'fa-user-plus' },
        { key: 'cass',                   label: 'Capture Assessment',     icon: 'fa-clipboard-check' },
        { key: 'schemeofwork',           label: 'Scheme of Work',         icon: 'fa-book-open-reader' },
        { key: 'clearance',              label: 'Clearance',              icon: 'fa-clipboard-list' },
        { key: 'studentperprogram',      label: 'Manage Students',        icon: 'fa-users' },
        { key: 'downloadresult',         label: 'Assessment Records',     icon: 'fa-folder-open' },
        { key: 'qualitativeaccessment',  label: 'Qualitative Assessment', icon: 'fa-star-half-stroke' },
        { key: 'transcript',             label: 'Transcript',             icon: 'fa-file-lines' },
        { key: 'assessmentmonitor',      label: 'School Monitor',         icon: 'fa-chart-line' },
        { key: 'mydocuments',            label: 'My Documents',           icon: 'fa-file-shield' }
      ]
    },
    {
      title: 'Settings',
      items: [
        { key: 'schoolupdate',    label: 'Update School Info',   icon: 'fa-school' },
        { key: 'registeruser',    label: 'Add User',             icon: 'fa-user-gear' },
        { key: 'AssignPrivilege', label: 'Manage Users',         icon: 'fa-users-gear' },
        { key: 'logintrace',      label: 'Login Trace',          icon: 'fa-shoe-prints' },
        { key: 'documentmanager', label: 'Document Uploads',     icon: 'fa-file-arrow-up' },
        { key: 'departmentmanager', label: 'Add / Manage Departments', icon: 'fa-building' },
        { key: 'programmemanager', label: 'Add / Manage Programmes', icon: 'fa-book-open' },
        { key: 'subjectmanager',  label: 'Add / Manage Subjects', icon: 'fa-book' },
        { key: 'classmanager',    label: 'Add / Manage Classes', icon: 'fa-layer-group' },
        { key: 'housemanager',    label: 'Add / Manage Houses',  icon: 'fa-house-user' }
      ]
    }
  ];

  function el(html) { var d = document.createElement('div'); d.innerHTML = html.trim(); return d.firstChild; }

  function norm(value) {
    return String(value || '').trim().toLowerCase();
  }

  function isSchoolAdmin(user) {
    if (!user || user.isSuperAdmin) return false;
    return !!(
      user.isAdmin ||
      norm(user.type) === 'schooladmin' ||
      norm(user.category) === 'school administrator' ||
      norm(user.role) === 'school administrator'
    );
  }

  function currentUser() {
    try {
      var user = JSON.parse(localStorage.getItem('axiom_current_user') || 'null');
      if (user && isSchoolAdmin(user) && !user.isAdmin) {
        user.isAdmin = true;
        if (!user.type) user.type = 'staff';
        localStorage.setItem('axiom_current_user', JSON.stringify(user));
      }
      return user;
    }
    catch (e) { return null; }
  }

  function setSidebarCollapsed(collapsed) {
    document.body.classList.toggle('sidebar-collapsed', collapsed);
    try {
      localStorage.removeItem('axiom_sidebar_collapsed');
    } catch (e) {}
  }

  function savedSidebarCollapsed() {
    return false;
  }

  function allowedNav() {
    var user = currentUser();
    if (user && user.isSuperAdmin) {
      return NAV.map(function (group, index) {
        var items = group.items.slice();
        if (index === 0 && !items.some(function(item) { return item.key === 'superadmin'; })) {
          items.unshift({ key: 'superadmin', label: 'Super Admin', icon: 'fa-user-shield', href: 'admin/superadmin.html' });
        }
        return { title: group.title, items: items };
      });
    }
    if (user && user.type === 'student') {
      return [{
        title: 'Student Portal',
        items: [
          { key: 'dashboard', label: 'Dashboard', icon: 'fa-gauge-high' },
          { key: 'mydocuments', label: 'My Documents', icon: 'fa-file-shield' },
          { key: 'transcript', label: 'Transcript', icon: 'fa-file-lines' },
          { key: 'clearance', label: 'Clearance', icon: 'fa-clipboard-list' }
        ]
      }];
    }
    if (!user) {
      return NAV.map(function (group) {
        return {
          title: group.title,
          items: group.items.filter(function (item) { return item.key !== 'schemeofwork'; })
        };
      });
    }
    if (isSchoolAdmin(user)) {
      return NAV.map(function (group) {
        return {
          title: group.title,
          items: group.items.reduce(function (items, item) {
            if (item.key === 'dashboard') {
              items.push({ key: 'dashboard', label: pageBase() === '../' ? 'Dashboard' : 'Back to Admin Portal', icon: 'fa-chart-pie', href: 'admin/admin.html' });
              items.push({ key: 'staffportal', label: 'Staff Portal', icon: 'fa-id-card', href: 'dashboard.html' });
              return items;
            }
            items.push(item);
            return items;
          })
        };
      });
    }
    var allowed = (user.privileges || []).slice();
    if (allowed.indexOf('dashboard') < 0) allowed.push('dashboard');
    if (user.category === 'Teaching Staff' && allowed.indexOf('cass') < 0) allowed.push('cass');
    if (user.category === 'Teaching Staff' && allowed.indexOf('schemeofwork') < 0) allowed.push('schemeofwork');
    if (user.category !== 'Teaching Staff') {
      allowed = allowed.filter(function (key) { return key !== 'cass' && key !== 'schemeofwork'; });
    }
    if (user.id && allowed.indexOf('mydocuments') < 0) allowed.push('mydocuments');
    if (user.id && allowed.indexOf('clearance') < 0) allowed.push('clearance');
    return NAV.map(function (group) {
      var items = group.items.filter(function (item) { return allowed.indexOf(item.key) > -1; });
      return { title: group.title, items: items };
    }).filter(function (group) { return group.items.length; });
  }

  function pageBase() {
    return location.pathname.replace(/\\/g, '/').indexOf('/admin/') > -1 ? '../' : '';
  }

  function cleanUrl(path) {
    if (location.protocol === 'file:') return path;
    return String(path || '').replace(/\.html($|[?#])/i, '$1');
  }

  function route(path) {
    return cleanUrl(pageBase() + path);
  }

  function pageHref(item) {
    var base = pageBase();
    if (item.href) {
      if (/^(https?:|#|\/)/i.test(item.href)) return cleanUrl(item.href);
      if (base && item.href.indexOf('admin/') === 0) return cleanUrl(item.href.replace(/^admin\//, ''));
      return cleanUrl(base + item.href);
    }
    return cleanUrl(base + item.key + '.html');
  }

  function buildSidebar(active) {
    var nav = allowedNav();
    var user = currentUser();
    var homeHref = (isSchoolAdmin(user) && !user.isSuperAdmin) ? route('admin/admin.html') : route('dashboard.html');
    var groups = nav.map(function (g, idx) {
      var open = isSchoolAdmin(user) || (user && user.isSuperAdmin) || g.items.some(function (i) { return i.key === active; }) || idx === 0;
      var links = g.items.map(function (i) {
        var cls = i.key === active ? ' class="active"' : '';
        return '<a href="' + pageHref(i) + '"' + cls + '><i class="fas ' + i.icon + '"></i> ' + i.label + '</a>';
      }).join('');
      return '<div class="nav__group' + (open ? ' open' : '') + '">' +
        '<button class="nav__title" type="button">' + g.title + ' <i class="fas fa-chevron-down chev"></i></button>' +
        '<div class="nav__items">' + links + '</div></div>';
    }).join('');

    return el(
      '<aside class="sidebar" id="sidebar">' +
        '<a class="sidebar__brand" href="' + homeHref + '">' +
          '<span class="logo"><i class="fas fa-graduation-cap"></i></span>' +
          '<span>AXIOMBYTE SMS<small>AXIOMBYTE SMS</small></span>' +
        '</a>' +
        '<nav class="nav">' + groups + '</nav>' +
      '</aside>'
    );
  }

  function sidebarIsUsable(sidebar) {
    return !!(sidebar && sidebar.querySelector('.sidebar__brand') && sidebar.querySelector('.nav__items a'));
  }

  function ensureSidebar(active) {
    var sidebar = document.getElementById('sidebar');
    if (!sidebarIsUsable(sidebar)) {
      if (sidebar) sidebar.remove();
      document.body.prepend(buildSidebar(active));
    }
    forceDesktopSidebar();
  }

  function activeSchoolLabel() {
    try {
      var code = localStorage.getItem('axiom_active_school_code') || SCHOOL.code;
      var name = localStorage.getItem('axiom_active_school_name') || SCHOOL.name;
      return code + ' - ' + name;
    } catch (e) { return SCHOOL.code + ' - ' + SCHOOL.name; }
  }

  function buildTopbar(title, subtitle) {
    var user = currentUser();
    var displayName = user && user.full_name ? user.full_name : SCHOOL.user;
    var myDocumentsLabel = user && user.type === 'student' ? 'Student Documents' : 'My Documents';
    var addUserLink = (!user || isSchoolAdmin(user)) ? '<a href="' + route('registeruser.html') + '"><i class="fas fa-user-plus" style="width:16px"></i> Add New User</a>' : '';
    return el(
      '<header class="topbar">' +
        '<button class="icon-btn hamburger" id="hamburger" aria-label="Menu"><i class="fas fa-bars"></i></button>' +
        '<h1>' + title + '<small>' + (subtitle || activeSchoolLabel()) + '</small></h1>' +
        '<button class="icon-btn" id="helpBtn" title="Quick help" style="margin-left:auto"><i class="far fa-circle-question"></i></button>' +
        '<div class="usermenu" id="usermenu">' +
          '<button class="usermenu__btn" type="button">' +
            '<span class="avatar">' + displayName.charAt(0) + '</span>' +
            '<span style="font-weight:600;font-size:14px">' + displayName + '</span>' +
            '<i class="fas fa-chevron-down" style="font-size:11px;color:var(--text-faint)"></i>' +
          '</button>' +
          '<div class="usermenu__list">' +
            '<a href="' + route('mydocuments.html') + '"><i class="fas fa-file-shield" style="width:16px"></i> ' + myDocumentsLabel + '</a>' +
            addUserLink +
            '<hr/>' +
            '<a href="#" class="danger" id="logoutLink"><i class="fas fa-arrow-right-from-bracket" style="width:16px"></i> Logout</a>' +
          '</div>' +
        '</div>' +
      '</header>'
    );
  }

  function wire(active, title, subtitle) {
    document.body.classList.add('portal-shell');
    var bootUser = currentUser();
    if (isSchoolAdmin(bootUser)) document.body.classList.add('school-admin-portal');
    // Keep the full sidebar on desktop/tablet, but start narrow screens in drawer mode.
    setSidebarCollapsed(window.innerWidth < 700 ? true : savedSidebarCollapsed());

    // mount sidebar + overlay
    ensureSidebar(active);
    if (!document.getElementById('overlay')) {
      document.body.appendChild(el('<div class="overlay" id="overlay"></div>'));
    }

    // mount topbar at top of .main
    var main = document.querySelector('.main');
    if (main && !document.querySelector('.topbar')) {
      main.prepend(buildTopbar(title, subtitle));
    }
    forceDesktopSidebar();

    // accordion
    document.querySelectorAll('.nav__title').forEach(function (b) {
      b.addEventListener('click', function () { b.closest('.nav__group').classList.toggle('open'); });
    });

    // mobile nav
    var hamburger = document.getElementById('hamburger');
    var overlay = document.getElementById('overlay');
    if (hamburger) hamburger.addEventListener('click', function () {
      setSidebarCollapsed(false);
      document.body.classList.toggle('nav-open');
    });
    if (overlay) overlay.addEventListener('click', function () { document.body.classList.remove('nav-open'); });
    document.querySelectorAll('.sidebar a[href]').forEach(function (link) {
      link.addEventListener('click', function () {
        if (window.innerWidth < 700) document.body.classList.remove('nav-open');
        setTimeout(function () { ensureSidebar(active); }, 60);
      });
    });

    ['pageshow', 'focus', 'visibilitychange'].forEach(function (eventName) {
      window.addEventListener(eventName, function () { ensureSidebar(active); });
    });
    setTimeout(function () { ensureSidebar(active); }, 250);
    setTimeout(function () { ensureSidebar(active); }, 1000);

    // user menu
    var um = document.getElementById('usermenu');
    if (um && um.querySelector('.usermenu__btn')) um.querySelector('.usermenu__btn').addEventListener('click', function (e) { e.stopPropagation(); um.classList.toggle('open'); });
    document.addEventListener('click', function () { if (um) um.classList.remove('open'); });

    // help + logout
    var helpBtn = document.getElementById('helpBtn');
    if (helpBtn) helpBtn.addEventListener('click', function () {
      Portal.toast('Use the field labels and tooltips on this page for guidance.');
    });
    var logoutLink = document.getElementById('logoutLink');
    if (logoutLink) logoutLink.addEventListener('click', function (e) {
      e.preventDefault();
      if (confirm('Log out of the portal?')) {
        if (window.AxiomDB && AxiomDB.signOut) { AxiomDB.signOut(); }
        else localStorage.removeItem('axiom_current_user');
        location.href = route('login.html');
      }
    });

    // toast host
    document.body.appendChild(el('<div class="toast-host" id="toastHost"></div>'));
  }

  function forceDesktopSidebar() {
    var sidebar = document.getElementById('sidebar');
    var main = document.querySelector('.main');
    if (!sidebar || !main) return;
    function apply() {
      if (window.innerWidth >= 700) {
        sidebar.style.transform = 'none';
        sidebar.style.display = 'flex';
        main.style.marginLeft = 'var(--sidebar-w)';
        main.style.width = 'calc(100% - var(--sidebar-w))';
        document.body.classList.remove('sidebar-collapsed', 'nav-open');
      } else {
        setSidebarCollapsed(true);
        sidebar.style.transform = '';
        sidebar.style.display = '';
        main.style.marginLeft = '';
        main.style.width = '';
      }
    }
    apply();
    if (!forceDesktopSidebar.bound) {
      window.addEventListener('resize', function () { forceDesktopSidebar(); });
      forceDesktopSidebar.bound = true;
    }
  }

  var Portal = {
    SCHOOL: SCHOOL,
    NAV: NAV,
    currentUser: currentUser,
    isSchoolAdmin: isSchoolAdmin,

    init: function (opts) {
      opts = opts || {};
      var active = opts.active || '';
      var title = opts.title || lookupTitle(active) || 'Dashboard';
      function go() {
        wire(active, title, opts.subtitle);
        var user = currentUser();
        var pageKey = active || (location.pathname.split('/').pop() || '').replace('.html', '');
        if (!user && ['login', 'superadmin-login', 'index'].indexOf(pageKey) === -1) {
          Portal.toast('Please login to continue.', true);
          setTimeout(function () { location.href = route('login.html'); }, 700);
          return;
        }
        if (user && user.isSuperAdmin) {
          if (opts.onReady) opts.onReady();
          return;
        }
        if (user && user.type === 'student' && (active === 'dashboard' || active === 'mydocuments' || active === 'transcript' || active === 'clearance')) {
          if (opts.onReady) opts.onReady();
          return;
        }
        if (user && active === 'dashboard') {
          if (opts.onReady) opts.onReady();
          return;
        }
        if (user && !isSchoolAdmin(user) && user.category !== 'Teaching Staff' && active === 'cass') {
          Portal.toast('Capture Assessment is for Teaching Staff only.', true);
          setTimeout(function () { location.href = route('mydocuments.html'); }, 900);
          return;
        }
        if (user && user.category === 'Teaching Staff' && active === 'cass') {
          if (opts.onReady) opts.onReady();
          return;
        }
        if (active === 'schemeofwork' && (!user || (!isSchoolAdmin(user) && user.category !== 'Teaching Staff'))) {
          Portal.toast('Scheme of Work is for Teaching Staff only.', true);
          setTimeout(function () { location.href = user ? route('dashboard.html') : route('login.html'); }, 900);
          return;
        }
        if (user && user.category === 'Teaching Staff' && active === 'schemeofwork') {
          if (opts.onReady) opts.onReady();
          return;
        }
        if (user && !isSchoolAdmin(user) && active && active !== 'mydocuments' && (user.privileges || []).indexOf(active) === -1) {
          Portal.toast('You do not have access to this module.', true);
          setTimeout(function () { location.href = route('mydocuments.html'); }, 900);
          return;
        }
        if (opts.onReady) opts.onReady();
      }
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', go); else go();
    },

    toast: function (msg, isErr) {
      var host = document.getElementById('toastHost'); if (!host) return;
      var t = el('<div class="toast' + (isErr ? ' err' : '') + '"><i class="fas ' + (isErr ? 'fa-circle-exclamation' : 'fa-circle-check') + '"></i><span>' + msg + '</span></div>');
      host.appendChild(t);
      setTimeout(function () { t.style.transition = 'opacity .3s'; t.style.opacity = '0'; setTimeout(function () { t.remove(); }, 300); }, 2800);
    },

    // Live filter for a table by a search input
    filterTable: function (inputSel, tableSel) {
      var input = document.querySelector(inputSel), table = document.querySelector(tableSel);
      if (!input || !table) return;
      input.addEventListener('input', function () {
        var q = input.value.toLowerCase();
        table.querySelectorAll('tbody tr').forEach(function (tr) {
          tr.style.display = tr.textContent.toLowerCase().indexOf(q) > -1 ? '' : 'none';
        });
      });
    },

    // Simple tab controller: containers with .tabs button[data-tab] + .tab-panel[data-tab]
    initTabs: function (rootSel) {
      var root = rootSel ? document.querySelector(rootSel) : document;
      root.querySelectorAll('.tabs button[data-tab]').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var id = btn.getAttribute('data-tab');
          root.querySelectorAll('.tabs button[data-tab]').forEach(function (b) { b.classList.toggle('active', b === btn); });
          root.querySelectorAll('.tab-panel[data-tab]').forEach(function (p) { p.classList.toggle('active', p.getAttribute('data-tab') === id); });
        });
      });
    },

    // WAEC-style grade from a 0-100 score
    grade: function (score) {
      score = Number(score);
      if (isNaN(score)) return { g: '-', cls: 'gray', remark: '' };
      if (score >= 80) return { g: 'A1', cls: 'green', remark: 'Excellent' };
      if (score >= 70) return { g: 'B2', cls: 'green', remark: 'Very Good' };
      if (score >= 60) return { g: 'B3', cls: 'green', remark: 'Good' };
      if (score >= 55) return { g: 'C4', cls: 'blue',  remark: 'Credit' };
      if (score >= 50) return { g: 'C5', cls: 'blue',  remark: 'Credit' };
      if (score >= 45) return { g: 'C6', cls: 'blue',  remark: 'Credit' };
      if (score >= 40) return { g: 'D7', cls: 'amber', remark: 'Pass' };
      if (score >= 35) return { g: 'E8', cls: 'amber', remark: 'Pass' };
      return { g: 'F9', cls: 'red', remark: 'Fail' };
    }
  };

  function lookupTitle(key) {
    var found = null;
    NAV.forEach(function (g) { g.items.forEach(function (i) { if (i.key === key) found = i.label; }); });
    return found;
  }

  w.Portal = Portal;
})(window);




