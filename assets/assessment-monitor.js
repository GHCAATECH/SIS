(function () {
  'use strict';

  Portal.init({ active: 'assessmentmonitor' });

  var activeRows = [];
  var activeTeacherRows = [];
  var activeTeacherTotal = 0;
  var lastMonitorPayload = null;
  var teacherListMode = 'assigned';

  function escapeHtml(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function currentAcademicYear() {
    var today = new Date();
    var year = today.getFullYear();
    return today.getMonth() >= 8 ? year + '/' + (year + 1) : (year - 1) + '/' + year;
  }

  function selectedFilters(useTeacherFilters) {
    return {
      academicYear: currentAcademicYear(),
      yearLevel: document.getElementById('monitorYear').value,
      semester: document.getElementById(useTeacherFilters ? 'teacherSemester' : 'monitorSemester').value,
      modeName: document.getElementById(useTeacherFilters ? 'teacherMode' : 'monitorMode').value
    };
  }

  function rowMatchesSearch(row, query) {
    if (!query) return true;
    return [
      row.rowNo, row.completed, row.meanMark, row.acadYear, row.yearLevel,
      row.mode, row.semester, row.registered, row.expected, row.captured, row.notCaptured
    ].join(' ').toLowerCase().indexOf(query) > -1;
  }

  function renderMonitorRows(rows) {
    var query = document.getElementById('monitorSearch').value.trim().toLowerCase();
    var filtered = rows.filter(function (row) { return rowMatchesSearch(row, query); });
    var tbody = document.getElementById('monitorRows');

    if (!filtered.length) {
      tbody.innerHTML = '<tr><td class="monitor-empty" colspan="12">Select the filters and click Filter to load assessment monitoring data.</td></tr>';
      document.getElementById('monitorInfo').textContent = 'Showing 0 to 0 of 0 entries';
      return;
    }

    tbody.innerHTML = filtered.map(function (row, index) {
      var completed = Math.max(0, Math.min(100, Number(row.completed || 0)));
      return '<tr>' +
        '<td><button class="monitor-btn monitor-teacher-btn" type="button" data-teachers="' + index + '">Teacher List</button></td>' +
        '<td>' + escapeHtml(row.rowNo) + '</td>' +
        '<td><strong>' + escapeHtml(completed.toFixed(2)) + '%</strong><div class="monitor-progress"><span style="width:' + completed + '%"></span></div></td>' +
        '<td>' + escapeHtml(Number(row.meanMark || 0).toFixed(2)) + '</td>' +
        '<td>' + escapeHtml(row.acadYear) + '</td>' +
        '<td>' + escapeHtml(row.yearLevel) + '</td>' +
        '<td title="' + escapeHtml(row.mode) + '">' + escapeHtml(row.mode) + '</td>' +
        '<td>' + escapeHtml(row.semester) + '</td>' +
        '<td>' + escapeHtml(row.registered) + '</td>' +
        '<td>' + escapeHtml(row.expected) + '</td>' +
        '<td>' + escapeHtml(row.captured) + '</td>' +
        '<td>' + escapeHtml(row.notCaptured) + '</td>' +
      '</tr>';
    }).join('');

    document.getElementById('monitorInfo').textContent = 'Showing 1 to ' + filtered.length + ' of ' + filtered.length + ' ' + (filtered.length === 1 ? 'entry' : 'entries');
    tbody.querySelectorAll('[data-teachers]').forEach(function (button) {
      button.addEventListener('click', function () {
        openTeacherModal(filtered[Number(button.getAttribute('data-teachers'))]);
      });
    });
  }

  function payloadToRow(payload, filters) {
    var expected = Number(payload.expected_total || 0);
    var captured = Number(payload.captured_total || 0);
    return {
      rowNo: 1,
      completed: Number(payload.percentage_completed || 0),
      meanMark: Number(payload.mean_mark || 0),
      acadYear: filters.academicYear,
      yearLevel: filters.yearLevel,
      mode: filters.modeName,
      semester: filters.semester,
      registered: Number(payload.total_students || 0),
      expected: expected,
      captured: captured,
      notCaptured: Math.max(expected - captured, 0),
      teacherTotal: Number(payload.teacher_total || 0),
      teachers: Array.isArray(payload.teachers) ? payload.teachers : [],
      unassignedAssignments: Array.isArray(payload.unassigned_assignments) ? payload.unassigned_assignments : []
    };
  }

  async function loadMonitor(filters, options) {
    options = options || {};
    var button = document.getElementById('filterBtn');
    button.disabled = true;
    button.textContent = 'Loading...';
    try {
      if (!window.AxiomDB || !AxiomDB.isConfigured() || !AxiomDB.listSchoolAssessmentMonitor) {
        throw new Error('Supabase assessment monitoring is not configured.');
      }
      var payload = await AxiomDB.listSchoolAssessmentMonitor(filters);
      lastMonitorPayload = payload || {};
      document.getElementById('schoolTotal').textContent = Number(lastMonitorPayload.total_students || 0);
      activeRows = [payloadToRow(lastMonitorPayload, filters)];
      renderMonitorRows(activeRows);
      if (options.openTeacherList) {
        var teacherRows = options.onlyUnassigned ?
          (activeRows[0].unassignedAssignments || []) :
          (activeRows[0].teachers || []);
        openTeacherModal(Object.assign({}, activeRows[0], {
          teachers: teacherRows,
          teacherTotal: countUniqueTeachers(teacherRows)
        }), options.keepSearch, options.onlyUnassigned ? 'unassigned' : 'assigned');
      }
      if (!options.silent) Portal.toast('School assessment monitor loaded.');
      return activeRows[0];
    } catch (error) {
      console.error(error);
      activeRows = [];
      lastMonitorPayload = null;
      document.getElementById('schoolTotal').textContent = '0';
      renderMonitorRows([]);
      Portal.toast('Could not load school assessment monitor: ' + (error.message || 'Unknown error'), true);
      return null;
    } finally {
      button.disabled = false;
      button.textContent = '<< Filter >>';
    }
  }

  function countUniqueTeachers(rows) {
    var ids = {};
    (rows || []).forEach(function (row) {
      if (row.staff_user_id) ids[row.staff_user_id] = true;
    });
    return Object.keys(ids).length;
  }

  function runFilter() {
    return loadMonitor(selectedFilters(false));
  }

  function showUnassigned() {
    return loadMonitor(selectedFilters(false), { openTeacherList: true, onlyUnassigned: true });
  }

  function openTeacherModal(row, keepSearch, listMode) {
    var teachers = row && Array.isArray(row.teachers) ? row.teachers : [];
    teacherListMode = listMode || 'assigned';
    activeTeacherRows = teachers.slice();
    activeTeacherTotal = countUniqueTeachers(teachers);
    document.getElementById('teacherMode').value = document.getElementById('monitorMode').value;
    document.getElementById('teacherSemester').value = document.getElementById('monitorSemester').value;
    if (!keepSearch) document.getElementById('teacherSearch').value = '';
    renderTeacherRows();
    document.getElementById('teacherModal').classList.add('open');
  }

  function teacherSearchText(row) {
    return [
      row.teacher_name, row.phone_number, row.email, row.class_name, row.subject_name,
      row.total_assigned, row.captured, row.not_captured
    ].join(' ').toLowerCase();
  }

  function renderTeacherRows() {
    var body = document.getElementById('teacherRows');
    var query = document.getElementById('teacherSearch').value.trim().toLowerCase();
    var limit = Number(document.getElementById('teacherPageLength').value) || 100;
    var filtered = activeTeacherRows.filter(function (row) {
      return !query || teacherSearchText(row).indexOf(query) > -1;
    });
    var visible = filtered.slice(0, limit);
    document.getElementById('teacherTotal').textContent = query ? countUniqueTeachers(filtered) : activeTeacherTotal;

    if (!visible.length) {
      body.innerHTML = '<tr><td class="monitor-empty" colspan="9">' +
        (teacherListMode === 'unassigned' ?
          'No class/subject with students is currently unassigned.' :
          'No assigned staff records with students were found for the selected assessment mode and semester.') +
        '</td></tr>';
      return;
    }

    body.innerHTML = visible.map(function (row, index) {
      return '<tr>' +
        '<td>' + (index + 1) + '</td>' +
        '<td title="' + escapeHtml(row.teacher_name) + '">' + escapeHtml(row.teacher_name) + '</td>' +
        '<td>' + escapeHtml(row.phone_number || '') + '</td>' +
        '<td title="' + escapeHtml(row.email || '') + '">' + escapeHtml(row.email || '') + '</td>' +
        '<td>' + escapeHtml(row.class_name || '') + '</td>' +
        '<td title="' + escapeHtml(row.subject_name || '') + '">' + escapeHtml(row.subject_name || '') + '</td>' +
        '<td>' + escapeHtml(row.total_assigned || 0) + '</td>' +
        '<td>' + escapeHtml(row.captured || 0) + '</td>' +
        '<td>' + escapeHtml(row.not_captured || 0) + '</td>' +
      '</tr>';
    }).join('');
  }

  function closeTeacherModal() {
    document.getElementById('teacherModal').classList.remove('open');
  }

  async function refreshTeacherFilters() {
    document.getElementById('monitorMode').value = document.getElementById('teacherMode').value;
    document.getElementById('monitorSemester').value = document.getElementById('teacherSemester').value;
    await loadMonitor(selectedFilters(true), {
      openTeacherList: true,
      onlyUnassigned: teacherListMode === 'unassigned',
      keepSearch: true,
      silent: true
    });
  }

  function downloadWorkbook(fileName, headers, rows) {
    if (!rows.length) {
      Portal.toast('No filtered records are available to download.', true);
      return;
    }
    var html = '<html><head><meta charset="utf-8"></head><body><table border="1"><thead><tr>' +
      headers.map(function (header) { return '<th>' + escapeHtml(header) + '</th>'; }).join('') +
      '</tr></thead><tbody>' + rows.map(function (row) {
        return '<tr>' + row.map(function (value) { return '<td>' + escapeHtml(value) + '</td>'; }).join('') + '</tr>';
      }).join('') + '</tbody></table></body></html>';
    var blob = new Blob([html], { type: 'application/vnd.ms-excel;charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 250);
  }

  function downloadTeacherWorkbook() {
    downloadWorkbook('teacher-assessment-monitor.xls',
      ['ROW_NUM', 'TEACHER_NAME', 'PHONE_NO', 'EMAIL', 'CLASS', 'SUBJECT', 'TOTAL_ASSIGNED', 'CAPTURED', 'NOT_CAPTURED'],
      activeTeacherRows.map(function (row, index) {
        return [index + 1, row.teacher_name, row.phone_number, row.email, row.class_name, row.subject_name, row.total_assigned, row.captured, row.not_captured];
      })
    );
  }

  function downloadMonitorWorkbook() {
    downloadWorkbook('school-assessment-monitor.xls',
      ['ROW_NO', 'PERCENTAGE_COMPLETED', 'MEAN_MARK(%)', 'ACAD_YEAR', 'YEAR', 'MODE_OF_ASSESSMENT', 'SEMESTER', 'NUM_STD_REGISTERED', 'TOTAL_EXPECTED', 'CAPTURED', 'NOT_CAPTURED'],
      activeRows.map(function (row) {
        return [row.rowNo, row.completed + '%', row.meanMark, row.acadYear, row.yearLevel, row.mode, row.semester, row.registered, row.expected, row.captured, row.notCaptured];
      })
    );
  }

  document.getElementById('filterBtn').addEventListener('click', runFilter);
  document.getElementById('unassignedBtn').addEventListener('click', showUnassigned);
  document.getElementById('downloadBtn').addEventListener('click', downloadMonitorWorkbook);
  document.getElementById('monitorSearch').addEventListener('input', function () { renderMonitorRows(activeRows); });
  document.getElementById('closeTeacherModal').addEventListener('click', closeTeacherModal);
  document.getElementById('downloadTeacherList').addEventListener('click', downloadTeacherWorkbook);
  document.getElementById('teacherSearch').addEventListener('input', renderTeacherRows);
  document.getElementById('teacherPageLength').addEventListener('change', renderTeacherRows);
  document.getElementById('teacherMode').addEventListener('change', refreshTeacherFilters);
  document.getElementById('teacherSemester').addEventListener('change', refreshTeacherFilters);
  document.getElementById('teacherModal').addEventListener('click', function (event) {
    if (event.target.id === 'teacherModal') closeTeacherModal();
  });
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') closeTeacherModal();
  });

  renderMonitorRows([]);
}());
