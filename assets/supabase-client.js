/* AXIOMBYTE SMS Supabase bridge
   Fill SUPABASE_URL and SUPABASE_ANON_KEY below after creating the Supabase project. */
(function (w) {
  'use strict';

  var CONFIG = {
      SUPABASE_URL: 'https://cdiptnnbneivckcejxpi.supabase.co',
      SUPABASE_ANON_KEY: 'sb_publishable_TVhQl4wZRVrZpCpq8Wq5Cg_M6npOAjp',
    SCHOOL_CODE: '0021101'
  };

  function configured() {
    return CONFIG.SUPABASE_URL.indexOf('PASTE_') !== 0 &&
      CONFIG.SUPABASE_ANON_KEY.indexOf('PASTE_') !== 0 &&
      w.supabase && w.supabase.createClient;
  }

  var client = null;
  function db() {
    if (!configured()) return null;
    if (!client) client = w.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);
    return client;
  }

  function activeSchoolCode() {
    try {
      var user = JSON.parse(w.localStorage.getItem('axiom_current_user') || 'null');
      return w.localStorage.getItem('axiom_active_school_code') || (user && user.school_code) || CONFIG.SCHOOL_CODE;
    } catch (e) {
      return CONFIG.SCHOOL_CODE;
    }
  }

  function setActiveSchool(code, id, name) {
    if (code) w.localStorage.setItem('axiom_active_school_code', String(code));
    if (id) w.localStorage.setItem('axiom_active_school_id', String(id));
    if (name) w.localStorage.setItem('axiom_active_school_name', String(name));
  }

  function activeStaffSessionToken() {
    try {
      var user = JSON.parse(w.localStorage.getItem('axiom_current_user') || 'null');
      return user && user.session_token ? String(user.session_token) : '';
    } catch (e) {
      return '';
    }
  }

  function activeStudentSessionToken() {
    try {
      var user = JSON.parse(w.localStorage.getItem('axiom_current_user') || 'null');
      return user && user.type === 'student' && user.session_token ? String(user.session_token) : '';
    } catch (e) {
      return '';
    }
  }

  function currentStoredUser() {
    try {
      return JSON.parse(w.localStorage.getItem('axiom_current_user') || 'null');
    } catch (e) {
      return null;
    }
  }

  async function authSession() {
    var c = db();
    if (!c) return null;
    var result = await c.auth.getSession();
    if (result.error) throw result.error;
    return result.data && result.data.session ? result.data.session : null;
  }

  async function signOut() {
    var c = db();
    if (c && c.auth) await c.auth.signOut();
    w.localStorage.removeItem('axiom_current_user');
  }

  async function restoreSessionUser() {
    var session = await authSession();
    if (!session || !session.user) return null;
    var profile = await loadAuthProfile(session.user);
    if (profile) w.localStorage.setItem('axiom_current_user', JSON.stringify(profile));
    return profile;
  }
  async function currentSchool() {
    var c = db();
    if (!c) return null;
    var cachedId = w.localStorage.getItem('axiom_active_school_id');
    var cachedName = w.localStorage.getItem('axiom_active_school_name');
    if (cachedId) {
      return {
        id: cachedId,
        code: activeSchoolCode(),
        name: cachedName || 'ASUOM SENIOR HIGH SCHOOL'
      };
    }
    var result = await c.from('schools').select('*').eq('code', activeSchoolCode()).limit(1).maybeSingle();
    if (result.error) throw result.error;
    if (!result.data) {
      var created = await c
        .from('schools')
        .insert({ code: activeSchoolCode(), name: 'ASUOM SENIOR HIGH SCHOOL' })
        .select('*')
        .single();
      if (created.error) throw created.error;
      return created.data;
    }
    return result.data;
  }

  function schoolAccessBlocked(school) {
    if (!school) return false;
    var status = school.subscription_status || 'Permanent';
    if (status === 'Suspended') return true;
    if (status === 'Trial' && school.trial_expires_at) return new Date(school.trial_expires_at).getTime() < Date.now();
    return false;
  }

  async function resolveAuthEmail(identifier, accountType) {
    var c = db();
    if (!c) return null;
    identifier = String(identifier || '').trim();
    if (!identifier) return null;
    var result = await c.rpc('resolve_auth_login', {
      p_identifier: identifier,
      p_account_type: accountType || null
    });
    if (result.error) throw result.error;
    return result.data || (identifier.indexOf('@') > -1 ? identifier : null);
  }

  async function loadAuthProfile(authUser, expectedType) {
    var c = db();
    if (!c || !authUser) return null;
    var profile;
    if (!expectedType || expectedType === 'superadmin') {
      var superResult = await c.from('super_admins').select('*').eq('auth_user_id', authUser.id).limit(1).maybeSingle();
      if (superResult.error) throw superResult.error;
      if (superResult.data && superResult.data.status !== 'Suspended') {
        profile = superResult.data;
        await c.from('super_admins').update({ last_login_at: new Date().toISOString() }).eq('id', profile.id);
        return {
          id: profile.id,
          auth_user_id: authUser.id,
          type: 'superadmin',
          full_name: profile.full_name,
          username: profile.username,
          email: profile.email || authUser.email,
          category: 'Super Administrator',
          role: 'Super Administrator',
          isSuperAdmin: true,
          isAdmin: true,
          privileges: ['superadmin', 'admin']
        };
      }
    }
    if (!expectedType || expectedType === 'staff') {
      var staffResult = await c.from('staff_users').select('*, schools(code, name, subscription_status, trial_expires_at)').eq('auth_user_id', authUser.id).limit(1).maybeSingle();
      if (staffResult.error) throw staffResult.error;
      if (staffResult.data && staffResult.data.status !== 'Suspended') {
        profile = staffResult.data;
        if (schoolAccessBlocked(profile.schools)) { await c.auth.signOut(); return null; }
        var previousCode = activeSchoolCode();
        if (profile.schools && profile.schools.code) setActiveSchool(profile.schools.code, profile.school_id, profile.schools.name);
        var privileges = await listUserPrivileges(profile.id);
        await c.from('staff_users').update({ last_login_at: new Date().toISOString() }).eq('id', profile.id);
        return {
          id: profile.id,
          auth_user_id: authUser.id,
          full_name: profile.full_name,
          staff_id: profile.staff_id,
          username: profile.username,
          email: profile.email || authUser.email,
          role: profile.role,
          category: profile.category,
          position_responsibility: profile.position_responsibility,
          position: profile.position_responsibility,
          form_master_class: profile.form_master_class || '',
          department: profile.department,
          rank: profile.rank,
          school_id: profile.school_id,
          school_code: profile.schools && profile.schools.code ? profile.schools.code : previousCode,
          school_name: profile.schools && profile.schools.name ? profile.schools.name : '',
          isAdmin: profile.category === 'School Administrator',
          privileges: privileges || []
        };
      }
    }
    if (!expectedType || expectedType === 'student') {
      var studentResult = await c.from('students').select('*, schools(code, name, subscription_status, trial_expires_at), classes(name, programmes(name))').eq('auth_user_id', authUser.id).limit(1).maybeSingle();
      if (studentResult.error) throw studentResult.error;
      if (studentResult.data) {
        var student = studentResult.data;
        if (schoolAccessBlocked(student.schools)) { await c.auth.signOut(); return null; }
        if (student.schools && student.schools.code) setActiveSchool(student.schools.code, student.school_id, student.schools.name);
        return {
          id: student.id,
          auth_user_id: authUser.id,
          type: 'student',
          ass_ref_id: student.ass_ref_id,
          full_name: [student.first_name, student.surname, student.other_names].filter(Boolean).join(' ').toUpperCase(),
          class_name: student.classes && student.classes.name ? student.classes.name : '',
          programme: student.classes && student.classes.programmes ? student.classes.programmes.name : '',
          status: student.status || '',
          student_level: student.student_level || '',
          school_id: student.school_id,
          school_code: student.schools && student.schools.code ? student.schools.code : activeSchoolCode(),
          school_name: student.schools && student.schools.name ? student.schools.name : '',
          category: 'Student',
          role: 'Student',
          privileges: (String(student.status || '').toLowerCase() === 'completed' || String(student.student_level || '').toLowerCase() === 'completed') ? ['dashboard', 'mydocuments', 'transcript', 'clearance'] : ['dashboard', 'mydocuments', 'transcript']
        };
      }
    }
    return null;
  }

  async function loginWithAuth(accountType, identifier, password) {
    var c = db();
    if (!c) return null;
    var email = null;
    try {
      email = await resolveAuthEmail(identifier, accountType);
    } catch (err) {
      if (accountType === 'staff') return loginStaffWithAccountPassword(identifier, password);
      throw err;
    }
    if (!email) {
      if (accountType === 'staff') return loginStaffWithAccountPassword(identifier, password);
      return { error: 'auth_not_linked' };
    }
    var signedIn = await c.auth.signInWithPassword({ email: email, password: String(password || '').trim() });
    if (signedIn.error) {
      if (accountType === 'staff') return loginStaffWithAccountPassword(identifier, password);
      return { error: 'auth_failed', message: signedIn.error.message };
    }
    var user = signedIn.data && signedIn.data.user;
    var profile = await loadAuthProfile(user, accountType);
    if (!profile) {
      await c.auth.signOut();
      return { error: 'profile_not_found' };
    }
    return profile;
  }

  async function loginStaffWithAccountPassword(identifier, password) {
    var c = db();
    if (!c) return null;
    var result = await c.rpc('resolve_staff_password_login', {
      p_identifier: String(identifier || '').trim(),
      p_password: String(password || '').trim()
    });
    if (result.error) return { error: 'account_password_login_failed', message: result.error.message };
    if (!result.data) return { error: 'auth_failed' };
    var profile = result.data;
    if (profile.email) {
      try {
        var authLogin = await c.auth.signInWithPassword({
          email: profile.email,
          password: String(password || '').trim()
        });
        if (!authLogin.error && authLogin.data && authLogin.data.user) {
          var authProfile = await loadAuthProfile(authLogin.data.user, 'staff');
          if (authProfile) {
            authProfile.session_token = profile.session_token;
            authProfile.privileges = profile.privileges || authProfile.privileges || [];
            authProfile.form_master_class = authProfile.form_master_class || profile.form_master_class || '';
            if (profile.school_code) setActiveSchool(profile.school_code, profile.school_id, profile.school_name);
            return authProfile;
          }
        }
      } catch (e) {
        console.warn('Account password fallback could not establish Auth session.', e);
      }
    }
    if (profile.school_code) setActiveSchool(profile.school_code, profile.school_id, profile.school_name);
    profile.type = profile.type || 'staff';
    profile.isAdmin = profile.isAdmin || profile.category === 'School Administrator' || profile.role === 'School Administrator';
    profile.form_master_class = profile.form_master_class || '';
    profile.privileges = profile.privileges || [];
    return profile;
  }

  async function qualitativeAssessmentSetup() {
    var c = db();
    if (!c) return null;
    var token = activeStaffSessionToken();
    var user = currentStoredUser();
    var staffUser = user && user.type !== 'student' && user.category && user.category !== 'Student';
    if (!token && !staffUser) throw new Error('Staff session expired. Please logout and login again.');
    var result = await c.rpc('secure_qualitative_assessment_setup', {
      p_session_token: token || null
    });
    if (result.error) {
      if (/secure_qualitative_assessment_setup|schema cache|function/i.test(result.error.message || '')) {
        throw new Error('Run the form master qualitative assessment SQL in Supabase, then logout and login again.');
      }
      throw result.error;
    }
    return result.data || null;
  }

  async function captureAssessmentSetup() {
    var c = db();
    if (!c) return null;
    var token = activeStaffSessionToken();
    if (!token) return { needsLogin: true, assignments: [], classes: [], students: [], assessment_modes: [] };
    var result = await c.rpc('secure_capture_assessment_setup', {
      p_session_token: token
    });
    if (result.error) {
      if (/secure_capture_assessment_setup|schema cache|function/i.test(result.error.message || '')) return null;
      throw result.error;
    }
    return result.data || null;
  }
  async function loginSuperAdmin(username, password) {
    return loginWithAuth('superadmin', username, password);
  }

  async function listSchools() {
    var c = db();
    if (!c) return null;
    var result = await c.from('schools').select('*').order('name');
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function createSchool(payload) {
    var c = db();
    if (!c) return null;
    var result = await c
      .from('schools')
      .insert({
        code: String(payload.code || '').trim(),
        name: String(payload.name || '').trim()
      })
      .select('*')
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function updateSchool(schoolId, payload) {
    var c = db();
    if (!c || !schoolId) return null;
    var result = await c
      .from('schools')
      .update({
        code: String(payload.code || '').trim(),
        name: String(payload.name || '').trim()
      })
      .eq('id', schoolId)
      .select('*')
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function listSchoolAdmins(schoolId) {
    var c = db();
    if (!c) return null;
    var query = c.from('staff_users').select('*, schools(code, name, subscription_status, trial_expires_at)').eq('category', 'School Administrator').order('full_name');
    if (schoolId) query = query.eq('school_id', schoolId);
    var result = await query;
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function createSchoolAdmin(schoolId, payload) {
    var c = db();
    if (!c || !schoolId) return null;
    var row = Object.assign({}, payload, {
      staff_name: payload.full_name,
      category: 'School Administrator',
      role: 'School Administrator',
      position_responsibility: payload.position_responsibility || 'Administrator',
      status: payload.status || 'Active'
    });
    var result = await c.rpc('secure_create_staff_user', {
      p_school_id: schoolId,
      p_payload: row
    });
    if (result.error) throw result.error;
    if (payload.account_password && result.data && result.data.id) {
      var passwordResult = await c
        .from('staff_users')
        .update({ account_password: payload.account_password, must_change_password: true })
        .eq('id', result.data.id)
        .eq('category', 'School Administrator')
        .select('*')
        .single();
      if (passwordResult.error) throw passwordResult.error;
      result.data = Object.assign({}, result.data, passwordResult.data || {});
      try {
        await resetSchoolAdminPassword(result.data.id, payload.account_password);
      } catch (err) {
        console.warn('School admin Auth link/reset failed; account_password login fallback can still be used after SQL setup.', err);
      }
    }
    return result.data;
  }

  async function updateSchoolAdmin(staffUserId, payload) {
    var c = db();
    if (!c || !staffUserId) return null;
    payload = Object.assign({}, payload || {});
    delete payload.id;
    delete payload.school_id;
    delete payload.created_at;
    delete payload.updated_at;
    delete payload.auth_user_id;
    payload.category = 'School Administrator';
    payload.role = 'School Administrator';
    if (payload.full_name && !payload.staff_name) payload.staff_name = payload.full_name;
    var result = await c
      .from('staff_users')
      .update(payload)
      .eq('id', staffUserId)
      .eq('category', 'School Administrator')
      .select('*, schools(code, name, subscription_status, trial_expires_at)')
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function resetSchoolAdminPassword(staffUserId, temporaryPassword) {
    var c = db();
    if (!c || !staffUserId) return null;
    var result = await c.rpc('super_admin_reset_school_admin_password', {
      p_staff_user_id: staffUserId,
      p_new_password: String(temporaryPassword || '').trim()
    });
    if (result.error) throw result.error;
    return result.data;
  }

  async function deleteSchoolAdmin(staffUserId) {
    var c = db();
    if (!c || !staffUserId) return null;
    var result = await c
      .from('staff_users')
      .delete()
      .eq('id', staffUserId)
      .eq('category', 'School Administrator');
    if (result.error) throw result.error;
    return true;
  }


  async function submitSchoolSignup(payload) {
    var c = db();
    if (!c) return null;
    var result = await c.rpc('submit_school_signup', { p_payload: payload || {} });
    if (result.error) throw result.error;
    return result.data;
  }

  async function listSchoolSignupRequests() {
    var c = db();
    if (!c) return [];
    var result = await c
      .from('school_signup_requests')
      .select('*, schools(code, name, subscription_status)')
      .order('status', { ascending: false })
      .order('trial_expires_at', { ascending: true })
      .order('created_at', { ascending: false });
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function approveSchoolSignup(requestId, permanent, reason) {
    var c = db();
    if (!c || !requestId) return null;
    var result = await c.rpc('approve_school_signup', {
      p_request_id: requestId,
      p_permanent: permanent !== false,
      p_decline_reason: reason || null
    });
    if (result.error) throw result.error;
    return result.data;
  }
  async function listProgrammes() {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c.from('programmes').select('*, departments(id, name, code)').eq('school_id', school.id).order('name');
    if (result.error) throw result.error;
    return result.data;
  }

  async function listDepartments() {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c.from('departments').select('*').eq('school_id', school.id).order('name');
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function createDepartment(payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c.from('departments').insert({
      school_id: school.id,
      name: payload.name,
      code: payload.code || null,
      description: payload.description || null
    }).select('*').single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function updateDepartment(departmentId, payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !departmentId) return null;
    var result = await c.from('departments').update({
      name: payload.name,
      code: payload.code || null,
      description: payload.description || null
    }).eq('school_id', school.id).eq('id', departmentId).select('*').single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function deleteDepartment(departmentId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !departmentId) return null;
    var result = await c.from('departments').delete().eq('school_id', school.id).eq('id', departmentId);
    if (result.error) throw result.error;
    return true;
  }

  async function listSubjects() {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c
      .from('subjects')
      .select('*, programmes(name)')
      .eq('school_id', school.id)
      .order('name');
    if (result.error) throw result.error;
    return result.data;
  }

  async function listClasses() {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c
      .from('classes')
      .select('*, programmes(name, department_id), departments(id, name, code), class_subjects(option_no, subjects(id, name, code))')
      .eq('school_id', school.id)
      .order('name');
    if (result.error) throw result.error;
    return result.data.map(function (row) {
      return {
        id: row.id,
        name: row.name,
        programme_id: row.programme_id,
        programme: row.programmes && row.programmes.name,
        department_id: row.department_id,
        department: row.departments && row.departments.name,
        year_level: row.year_level,
        class_teacher: row.class_teacher,
        subjects: (row.class_subjects || [])
          .sort(function (a, b) { return a.option_no - b.option_no; })
          .map(function (cs) { return cs.subjects && cs.subjects.name; })
          .filter(Boolean),
        subjectLinks: (row.class_subjects || [])
          .sort(function (a, b) { return a.option_no - b.option_no; })
          .map(function (cs) {
            return cs.subjects ? { id: cs.subjects.id, name: cs.subjects.name, code: cs.subjects.code } : null;
          })
          .filter(Boolean)
      };
    });
  }

  function programmeName(row) {
    return row && (row.name || row.programme || row);
  }

  async function findProgrammeByName(name) {
    var programmes = await listProgrammes();
    return (programmes || []).find(function (programme) {
      return (programme.name || '').toLowerCase() === (name || '').toLowerCase();
    });
  }

  async function findDepartmentByName(name) {
    var departments = await listDepartments();
    return (departments || []).find(function (department) {
      return (department.name || '').toLowerCase() === (name || '').toLowerCase();
    });
  }

  async function createProgramme(payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var department = await findDepartmentByName(payload.department);
    if (!department) throw new Error('Select a valid department for this programme.');
    var row = {
      school_id: school.id,
      name: payload.name,
      code: payload.code || null,
      department_id: department.id,
      department: department.name
    };
    var result = await c.from('programmes').insert(row).select('*, departments(id, name, code)').single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function deleteProgramme(programmeId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !programmeId) return null;
    var result = await c.from('programmes').delete().eq('school_id', school.id).eq('id', programmeId);
    if (result.error) throw result.error;
    return true;
  }

  async function createSubject(payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var programme = payload.programme === 'All Programmes' ? null : await findProgrammeByName(payload.programme);
    if (payload.programme !== 'All Programmes' && !programme) throw new Error('Programme was not found for this subject.');
    var row = {
      school_id: school.id,
      programme_id: programme ? programme.id : null,
      name: payload.name,
      code: payload.code || null,
      subject_type: payload.type || payload.subject_type || 'Elective',
      applies_to_all_programmes: payload.programme === 'All Programmes'
    };
    var result = await c.from('subjects').insert(row).select('*, programmes(name)').single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function deleteSubject(subjectId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !subjectId) return null;
    var result = await c.from('subjects').delete().eq('school_id', school.id).eq('id', subjectId);
    if (result.error) throw result.error;
    return true;
  }

  async function subjectRowsForProgramme(programmeNameValue) {
    var subjects = await listSubjects();
    return (subjects || []).filter(function (subject) {
      var linkedProgramme = subject.programmes && subject.programmes.name;
      return subject.applies_to_all_programmes || linkedProgramme === programmeNameValue;
    });
  }

  async function saveClassSubjects(classId, programmeNameValue, subjectNames) {
    var c = db();
    if (!c || !classId) return [];
    var available = await subjectRowsForProgramme(programmeNameValue);
    var rows = [];
    var used = {};
    (subjectNames || []).forEach(function (subjectName) {
      var match = available.find(function (subject) { return programmeName(subject) === subjectName; });
      if (match && !used[match.id]) {
        used[match.id] = true;
        rows.push({ class_id: classId, subject_id: match.id, option_no: rows.length + 1 });
      }
    });
    if (!rows.length) return [];
    var inserted = await c.from('class_subjects').insert(rows).select('*');
    if (inserted.error) throw inserted.error;
    return inserted.data;
  }

  async function createClass(payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var programme = await findProgrammeByName(payload.programme);
    if (!programme) throw new Error('Programme was not found for this class.');
    var programmeDepartment = programme.departments && programme.departments.name ? programme.departments.name : programme.department;
    if (payload.department && programmeDepartment && payload.department !== programmeDepartment) throw new Error('The selected programme does not belong to this department.');
    var result = await c
      .from('classes')
      .insert({
        school_id: school.id,
        programme_id: programme.id,
        department_id: programme.department_id,
        name: payload.name,
        year_level: payload.year_level || null,
        class_teacher: payload.class_teacher || null
      })
      .select('*')
      .single();
    if (result.error) throw result.error;
    await saveClassSubjects(result.data.id, payload.programme, payload.subjects || []);
    var classes = await listClasses();
    return (classes || []).find(function (cls) { return cls.id === result.data.id; }) || result.data;
  }

  async function updateClass(classId, payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !classId) return null;
    var programme = await findProgrammeByName(payload.programme);
    if (!programme) throw new Error('Programme was not found for this class.');
    var programmeDepartment = programme.departments && programme.departments.name ? programme.departments.name : programme.department;
    if (payload.department && programmeDepartment && payload.department !== programmeDepartment) throw new Error('The selected programme does not belong to this department.');
    var updated = await c
      .from('classes')
      .update({
        programme_id: programme.id,
        department_id: programme.department_id,
        name: payload.name,
        year_level: payload.year_level || null,
        class_teacher: payload.class_teacher || null
      })
      .eq('school_id', school.id)
      .eq('id', classId)
      .select('*')
      .single();
    if (updated.error) throw updated.error;
    var deleted = await c.from('class_subjects').delete().eq('class_id', classId);
    if (deleted.error) throw deleted.error;
    await saveClassSubjects(classId, payload.programme, payload.subjects || []);
    var classes = await listClasses();
    return (classes || []).find(function (cls) { return cls.id === classId; }) || updated.data;
  }

  async function deleteClass(classId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !classId) return null;
    var result = await c.from('classes').delete().eq('school_id', school.id).eq('id', classId);
    if (result.error) throw result.error;
    return true;
  }

  async function listHouses() {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c.from('houses').select('*').eq('school_id', school.id).order('name');
    if (result.error) throw result.error;
    return result.data;
  }

  async function createHouse(payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c
      .from('houses')
      .insert({
        school_id: school.id,
        name: payload.name,
        residential_status: payload.residentialStatus || payload.residential_status,
        patron: payload.patron || null,
        capacity: payload.capacity ? Number(payload.capacity) : null
      })
      .select('*')
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function deleteHouse(houseId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !houseId) return null;
    var result = await c.from('houses').delete().eq('school_id', school.id).eq('id', houseId);
    if (result.error) throw result.error;
    return true;
  }

  async function listStudents() {
    var c = db();
    if (!c) return null;
    var session = await authSession();
    if (!session || !session.user) {
      throw new Error('Please login as school administrator before loading students.');
    }
    var school = await currentSchool();
    if (!school) return null;
    var rpcResult = await c.rpc('secure_list_students', { p_school_id: school.id });
    if (!rpcResult.error) return rpcResult.data || [];
    if (!/secure_list_students|schema cache|function/i.test(rpcResult.error.message || '')) {
      throw rpcResult.error;
    }
    var result = await c
      .from('students')
      .select('*, classes(name, year_level, programmes(name)), houses(name)')
      .eq('school_id', school.id)
      .order('created_at', { ascending: false });
    if (result.error) throw result.error;
    return result.data;
  }

  async function createStudent(payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var row = Object.assign({}, payload, { school_id: school.id });
    var rpcResult = await c.rpc('secure_create_student', {
      p_school_id: school.id,
      p_payload: row
    });
    if (!rpcResult.error) return rpcResult.data;
    if (String(rpcResult.error.message || '').toLowerCase().includes('secure_create_student')) {
      throw new Error('Run the secure student registration SQL in Supabase, then refresh this page.');
    }
    throw rpcResult.error;
  }

  async function updateStudentByAssRef(assRefId, payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !assRefId) return null;
    payload = Object.assign({}, payload || {});
    delete payload.id;
    delete payload.school_id;
    delete payload.created_at;
    delete payload.updated_at;
    var rpcResult = await c.rpc('secure_update_student_by_ass_ref', {
      p_school_id: school.id,
      p_ass_ref_id: assRefId,
      p_payload: payload
    });
    if (!rpcResult.error) return rpcResult.data;
    if (String(rpcResult.error.message || '').toLowerCase().includes('secure_update_student_by_ass_ref')) {
      throw new Error('Run the secure student update SQL in Supabase, then refresh this page.');
    }
    throw rpcResult.error;
  }

  async function progressStudents(assRefIds) {
    var c = db(), school = await currentSchool();
    assRefIds = (assRefIds || []).filter(Boolean);
    if (!c || !school || !assRefIds.length) return [];
    var result = await c.rpc('progress_students', {
      p_school_id: school.id,
      p_ass_ref_ids: assRefIds
    });
    if (result.error) {
      var missingFunction = result.error.code === 'PGRST202' || /could not find the function/i.test(result.error.message || '');
      if (!missingFunction) throw result.error;

      var allStudents = await listStudents();
      var wanted = {};
      assRefIds.forEach(function(ref) { wanted[ref] = true; });
      var currentYear = new Date().getFullYear();
      var targets = (allStudents || []).filter(function(student) {
        var status = String(student.status || 'Active').toLowerCase();
        return wanted[student.ass_ref_id] && status !== 'transferred' && status !== 'dropped' && status !== 'completed';
      });
      try {
        return await Promise.all(targets.map(function(student) {
          var level = student.student_level || (student.classes && student.classes.year_level) || '';
          if (!level && student.year_admitted) {
            var difference = currentYear - Number(student.year_admitted);
            level = difference <= 0 ? 'Year 1' : difference === 1 ? 'Year 2' : difference === 2 ? 'Year 3' : 'Completed';
          }
          var nextLevel = level === 'Year 1' ? 'Year 2' : level === 'Year 2' ? 'Year 3' : 'Completed';
          return updateStudentByAssRef(student.ass_ref_id, {
            student_level: nextLevel,
            status: nextLevel === 'Completed' ? 'Completed' : 'Active'
          });
        }));
      } catch (fallbackError) {
        if (/student_level|schema cache|status.*check/i.test(fallbackError.message || '')) {
          throw new Error('Run the student progression SQL migration in Supabase, then refresh this page.');
        }
        throw fallbackError;
      }
    }
    return result.data || [];
  }

  async function deleteStudentByAssRef(assRefId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !assRefId) return null;
    var result = await c
      .from('students')
      .delete()
      .eq('school_id', school.id)
      .eq('ass_ref_id', assRefId);
    if (result.error) throw result.error;
    return true;
  }

  async function listStaff() {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c.from('staff_users').select('*').eq('school_id', school.id).order('full_name');
    if (result.error) throw result.error;
    return result.data;
  }

  async function getStaffUser(staffUserId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !staffUserId) return null;
    var result = await c
      .from('staff_users')
      .select('*')
      .eq('school_id', school.id)
      .eq('id', staffUserId)
      .limit(1)
      .maybeSingle();
    if (result.error) throw result.error;
    return result.data;
  }

  async function createStaffUser(payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c.rpc('secure_create_staff_user', {
      p_school_id: school.id,
      p_payload: payload
    });
    if (result.error) throw result.error;
    return result.data;
  }

  async function updateStaffUser(staffUserId, payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !staffUserId) return null;
    delete payload.id;
    delete payload.school_id;
    delete payload.created_at;
    delete payload.updated_at;
    var result = await c
      .from('staff_users')
      .update(payload)
      .eq('school_id', school.id)
      .eq('id', staffUserId)
      .select('*')
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function deleteStaffUser(staffUserId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !staffUserId) return null;
    var result = await c
      .from('staff_users')
      .delete()
      .eq('school_id', school.id)
      .eq('id', staffUserId);
    if (result.error) throw result.error;
    return true;
  }

  async function loginStaff(login, password) {
    var fallbackProfile = await loginStaffWithAccountPassword(login, password);
    if (fallbackProfile && !fallbackProfile.error) return fallbackProfile;
    return loginWithAuth('staff', login, password);
  }

  async function loginStudentWithPasswordSession(assRefId, password) {
    var c = db();
    if (!c) return null;
    var result = await c.rpc('resolve_student_password_login', {
      p_ass_ref_id: String(assRefId || '').trim(),
      p_password: String(password || '').trim()
    });
    if (result.error) {
      if (/resolve_student_password_login|schema cache|function/i.test(result.error.message || '')) return null;
      return { error: 'auth_failed', message: result.error.message };
    }
    if (!result.data) return { error: 'auth_failed' };
    var profile = result.data;
    if (profile.school_code) setActiveSchool(profile.school_code, profile.school_id, profile.school_name);
    profile.type = 'student';
    profile.category = 'Student';
    profile.role = 'Student';
    var completedStudent = String(profile.status || '').toLowerCase() === 'completed' || String(profile.student_level || '').toLowerCase() === 'completed';
    profile.privileges = completedStudent ? ['dashboard', 'mydocuments', 'transcript', 'clearance'] : ['dashboard', 'mydocuments', 'transcript'];
    return profile;
  }

  function dobPassword(dateValue) {
    if (!dateValue) return '';
    var parts = String(dateValue).slice(0, 10).split('-');
    if (parts.length !== 3) return '';
    return parts[1] + parts[2] + parts[0];
  }

  function dobPasswords(dateValue) {
    if (!dateValue) return [];
    var raw = String(dateValue).trim();
    var iso = raw.slice(0, 10).split('-');
    if (iso.length === 3 && iso[0].length === 4) {
      return [
        iso[1] + iso[2] + iso[0],
        iso[2] + iso[1] + iso[0]
      ];
    }
    var digits = raw.replace(/\D/g, '');
    if (digits.length === 8) return [digits];
    return [];
  }

  async function ensureStudentAccount(assRefId, password) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !assRefId) return null;
    var result = await c.rpc('ensure_student_auth_account', {
      p_school_id: school.id,
      p_ass_ref_id: String(assRefId || '').trim(),
      p_password: String(password || '').trim()
    });
    if (!result.error) return result.data;
    if (/ensure_student_auth_account|schema cache|function/i.test(result.error.message || '')) {
      throw new Error('Run the student account SQL in Supabase, then upload/register students again.');
    }
    throw result.error;
  }

  async function loginStudent(assRefId, password) {
    var sessionProfile = await loginStudentWithPasswordSession(assRefId, password);
    if (sessionProfile && !sessionProfile.error) return sessionProfile;

    var profile = await loginWithAuth('student', assRefId, password);
    if (profile && !profile.error) return profile;
    if (profile && profile.error !== 'auth_not_linked' && profile.error !== 'auth_failed') return profile;

    var c = db();
    if (!c) return profile;
    var repair = await c.rpc('resolve_student_auth_login', {
      p_ass_ref_id: String(assRefId || '').trim(),
      p_password: String(password || '').trim()
    });
    if (repair.error) {
      if (/resolve_student_auth_login|schema cache|function/i.test(repair.error.message || '')) return profile;
      return { error: 'auth_failed', message: repair.error.message };
    }
    if (!repair.data) return profile || { error: 'auth_failed' };

    var signedIn = await c.auth.signInWithPassword({
      email: repair.data,
      password: String(password || '').trim()
    });
    if (signedIn.error) return { error: 'auth_failed', message: signedIn.error.message };
    var repairedProfile = await loadAuthProfile(signedIn.data && signedIn.data.user, 'student');
    if (!repairedProfile) {
      await c.auth.signOut();
      return { error: 'profile_not_found' };
    }
    if (sessionProfile && sessionProfile.session_token) repairedProfile.session_token = sessionProfile.session_token;
    return repairedProfile;
  }

  async function listUserPrivileges(staffUserId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !staffUserId) return null;
    var result = await c
      .from('user_privileges')
      .select('page_key')
      .eq('school_id', school.id)
      .eq('staff_user_id', staffUserId);
    if (result.error) throw result.error;
    return result.data.map(function (row) { return row.page_key; });
  }

  async function saveUserPrivileges(staffUserId, pageKeys) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !staffUserId) return null;
    var result = await c.rpc('secure_save_user_privileges', {
      p_school_id: school.id,
      p_staff_user_id: staffUserId,
      p_page_keys: pageKeys || []
    });
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function listStaffSubjectClasses(staffUserId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !staffUserId) return null;
    var result = await c
      .from('staff_subject_classes')
      .select('*, classes(name), subjects(name, code)')
      .eq('school_id', school.id)
      .eq('staff_user_id', staffUserId);
    if (result.error) throw result.error;
    return (result.data || []).map(function(row) {
      return {
        classId: row.class_id,
        className: row.classes && row.classes.name,
        subjectId: row.subject_id,
        subjectName: row.subjects && row.subjects.name
      };
    });
  }

  async function saveStaffSubjectClasses(staffUserId, assignments) {
    var c = db();
    if (!c || !staffUserId) return null;
    var token = activeStaffSessionToken();
    if (token) {
      var sessionResult = await c.rpc('secure_save_staff_subject_classes_with_session', {
        p_session_token: token,
        p_staff_user_id: staffUserId,
        p_assignments: assignments || []
      });
      if (!sessionResult.error) return sessionResult.data || [];
      if (!/secure_save_staff_subject_classes_with_session|schema cache|function/i.test(sessionResult.error.message || '')) {
        throw sessionResult.error;
      }
    }
    var school = await currentSchool();
    if (!c || !school || !staffUserId) return null;
    var deleted = await c
      .from('staff_subject_classes')
      .delete()
      .eq('school_id', school.id)
      .eq('staff_user_id', staffUserId);
    if (deleted.error) throw deleted.error;
    if (!assignments || !assignments.length) return [];
    var rows = assignments.map(function(item) {
      return {
        school_id: school.id,
        staff_user_id: staffUserId,
        class_id: item.classId,
        subject_id: item.subjectId
      };
    }).filter(function(row) { return row.class_id && row.subject_id; });
    if (!rows.length) return [];
    var inserted = await c.from('staff_subject_classes').insert(rows).select('*');
    if (inserted.error) throw inserted.error;
    return inserted.data;
  }

  async function listAssessmentModes() {
    var c = db();
    if (!c) return null;
    var result = await c.from('assessment_modes').select('*').order('display_order');
    if (result.error) throw result.error;
    return result.data;
  }

  async function saveAssessmentScores(payload) {
    var c = db();
    if (!c) return null;
    var token = activeStaffSessionToken();
    if (token) {
      var sessionResult = await c.rpc('secure_save_assessment_scores_with_session', {
        p_session_token: token,
        p_payload: payload || {}
      });
      if (!sessionResult.error) return sessionResult.data;
      if (/secure_save_assessment_scores_with_session|schema cache|function/i.test(sessionResult.error.message || '')) {
        throw new Error('Run the staff capture assessment SQL in Supabase, then refresh this page.');
      }
      throw sessionResult.error;
    }
    var school = await currentSchool();
    if (!c || !school) return null;
    payload = Object.assign({}, payload || {}, { school_id: school.id });
    var result = await c.rpc('secure_save_assessment_scores', { p_payload: payload });
    if (result.error) throw result.error;
    return result.data;
  }

  async function listAssessmentRecords(filters) {
    var c = db();
    if (!c) return null;
    filters = filters || {};
    var token = activeStaffSessionToken();
    if (token) {
      var sessionResult = await c.rpc('secure_list_assessment_records_with_session', {
        p_session_token: token,
        p_filters: filters || {}
      });
      if (!sessionResult.error) return sessionResult.data || [];
      if (/secure_list_assessment_records_with_session|schema cache|function/i.test(sessionResult.error.message || '')) {
        throw new Error('Run the staff assessment records SQL in Supabase, then refresh this page.');
      }
      throw sessionResult.error;
    }
    var school = await currentSchool();
    if (!school) return null;
    var result = await c
      .from('assessment_scores')
      .select('score, grade, remark, updated_at, students(ass_ref_id, first_name, surname, other_names, ghana_card_number, gender, disability_status, date_of_birth, status, passport_url, student_level, year_admitted, classes(year_level)), assessments(class_id, academic_year, year_level, semester, status, submitted_at, overall_score, inserted_by, subjects(name, code), classes(name, programme_id, programmes(name)), assessment_modes(name, display_order))')
      .order('updated_at', { ascending: false });
    if (result.error) throw result.error;
    return (result.data || []).filter(function(row) {
      var assessment = row.assessments || {};
      if (!assessment || assessment.status !== 'Submitted') return false;
      if (filters.academicYear && assessment.academic_year !== filters.academicYear) return false;
      if (filters.yearLevel && assessment.year_level !== filters.yearLevel) return false;
      if (filters.semester && assessment.semester !== filters.semester) return false;
      if (filters.modeName) {
        var modeName = assessment.assessment_modes && assessment.assessment_modes.name;
        var displayOrder = assessment.assessment_modes && assessment.assessment_modes.display_order;
        var label = displayOrder ? displayOrder + '. ' + modeName : modeName;
        if (modeName !== filters.modeName && label !== filters.modeName) return false;
      }
      if (filters.className && assessment.classes && assessment.classes.name !== filters.className) return false;
      if (filters.subjectName && assessment.subjects && assessment.subjects.name !== filters.subjectName) return false;
      return true;
    });
  }

  async function listSchoolAssessmentMonitor(filters) {
    var c = db();
    if (!c) return null;
    filters = filters || {};
    var school = await currentSchool();
    if (!school) return null;
    var token = activeStaffSessionToken();
    var rpcResult = await c.rpc('secure_school_assessment_monitor', {
      p_session_token: token || null,
      p_school_id: school.id,
      p_academic_year: filters.academicYear || null,
      p_year_level: filters.yearLevel || null,
      p_semester: filters.semester || null,
      p_mode_name: filters.modeName || null
    });
    if (!rpcResult.error) return rpcResult.data || {};

    var missingRpc = rpcResult.error.code === 'PGRST202' ||
      /secure_school_assessment_monitor|schema cache|function/i.test(rpcResult.error.message || '');
    if (!missingRpc) throw rpcResult.error;

    try {
      var fallbackResults = await Promise.all([
        listStudents(),
        listStaff(),
        listAssessmentRecords({
          academicYear: filters.academicYear || '',
          yearLevel: filters.yearLevel || '',
          semester: filters.semester || ''
        }),
        listClasses()
      ]);
      var students = fallbackResults[0] || [];
      var staffRows = fallbackResults[1] || [];
      var records = fallbackResults[2] || [];
      var classRows = fallbackResults[3] || [];
      var assignmentLists = await Promise.all(staffRows.map(function(staff) {
        return listStaffSubjectClasses(staff.id).catch(function() { return []; });
      }));
      var activeStudents = students.filter(function(student) {
        return ['deleted', 'transferred', 'dropped', 'completed'].indexOf(String(student.status || 'Active').toLowerCase()) < 0;
      });
      var wantedMode = String(filters.modeName || '').trim().toLowerCase();
      records = records.filter(function(record) {
        var assessment = record.assessments || {};
        var mode = assessment.assessment_modes || {};
        return !wantedMode || String(mode.name || '').trim().toLowerCase() === wantedMode;
      });

      var teacherRows = [];
      staffRows.forEach(function(staff, staffIndex) {
        if (String(staff.status || 'Active').toLowerCase() !== 'active') return;
        (assignmentLists[staffIndex] || []).forEach(function(assignment) {
          var classStudents = activeStudents.filter(function(student) {
            var classInfo = student.classes || {};
            var classId = student.class_id || classInfo.id || '';
            var className = classInfo.name || student.class_name || '';
            var yearLevel = student.student_level || classInfo.year_level || '';
            return (String(classId) === String(assignment.classId) || className === assignment.className) &&
              (!filters.yearLevel || !yearLevel || String(yearLevel).toLowerCase() === String(filters.yearLevel).toLowerCase());
          });
          var capturedRefs = {};
          records.forEach(function(record) {
            var assessment = record.assessments || {};
            var subject = assessment.subjects || {};
            var student = record.students || {};
            if (String(assessment.class_id || '') === String(assignment.classId || '') &&
                String(subject.name || '').toLowerCase() === String(assignment.subjectName || '').toLowerCase() &&
                record.score !== null && record.score !== undefined) {
              capturedRefs[student.ass_ref_id || student.id] = true;
            }
          });
          var captured = Object.keys(capturedRefs).filter(Boolean).length;
          teacherRows.push({
            staff_user_id: staff.id,
            teacher_name: staff.full_name || staff.staff_name || staff.staff_id || 'Unnamed Staff',
            phone_number: staff.phone || '',
            email: staff.email || '',
            class_id: assignment.classId,
            class_name: assignment.className || '',
            subject_id: assignment.subjectId,
            subject_name: assignment.subjectName || '',
            total_assigned: classStudents.length,
            captured: captured,
            not_captured: Math.max(classStudents.length - captured, 0)
          });
        });
      });
      teacherRows = teacherRows.filter(function(row) {
        return Number(row.total_assigned || 0) > 0;
      });
      var assignedKeys = {};
      teacherRows.forEach(function(row) {
        assignedKeys[String(row.class_id) + '|' + String(row.subject_id)] = true;
      });
      var unassignedRows = [];
      classRows.forEach(function(classRow) {
        var classStudents = activeStudents.filter(function(student) {
          var classInfo = student.classes || {};
          var sameClass = String(student.class_id || classInfo.id || '') === String(classRow.id || '') || classInfo.name === classRow.name;
          var yearLevel = student.student_level || classInfo.year_level || classRow.year_level || '';
          return sameClass && (!filters.yearLevel || String(yearLevel).toLowerCase() === String(filters.yearLevel).toLowerCase());
        });
        if (!classStudents.length) return;
        (classRow.subjectLinks || []).forEach(function(subject) {
          var key = String(classRow.id) + '|' + String(subject.id);
          if (assignedKeys[key]) return;
          classStudents.forEach(function(student) {
            unassignedRows.push({
              student_id: student.id,
              ass_ref_id: student.ass_ref_id || '',
              student_name: [student.first_name, student.surname, student.other_names].filter(Boolean).join(' ').toUpperCase(),
              gender: student.gender || '',
              year_level: student.student_level || (student.classes && student.classes.year_level) || classRow.year_level || '',
              class_id: classRow.id,
              class_name: classRow.name || '',
              subject_id: subject.id,
              subject_name: subject.name || '',
              subject_code: subject.code || '',
              status: 'UNASSIGNED'
            });
          });
        });
      });
      var selectedYearStudents = activeStudents.filter(function(student) {
        var classInfo = student.classes || {};
        var yearLevel = student.student_level || classInfo.year_level || '';
        return !filters.yearLevel || String(yearLevel).toLowerCase() === String(filters.yearLevel).toLowerCase();
      });
      var expectedTotal = teacherRows.reduce(function(total, row) { return total + Number(row.total_assigned || 0); }, 0);
      var capturedTotal = teacherRows.reduce(function(total, row) { return total + Number(row.captured || 0); }, 0);
      var normalizedScores = records.map(function(record) {
        var overall = Number(record.assessments && record.assessments.overall_score);
        return overall > 0 ? (Number(record.score || 0) / overall) * 100 : null;
      }).filter(function(value) { return value !== null && isFinite(value); });
      var teacherIds = {};
      teacherRows.forEach(function(row) { teacherIds[row.staff_user_id] = true; });
      return {
        school_id: school.id,
        school_code: school.code || activeSchoolCode(),
        school_name: school.name || '',
        total_students: activeStudents.length,
        selected_year_students: selectedYearStudents.length,
        expected_total: expectedTotal,
        captured_total: capturedTotal,
        percentage_completed: expectedTotal ? Number(((capturedTotal / expectedTotal) * 100).toFixed(2)) : 0,
        mean_mark: normalizedScores.length ? Number((normalizedScores.reduce(function(a, b) { return a + b; }, 0) / normalizedScores.length).toFixed(2)) : 0,
        teacher_total: Object.keys(teacherIds).length,
        teachers: teacherRows,
        unassigned_students: unassignedRows
      };
    } catch (fallbackError) {
      throw new Error('Run the school assessment monitor SQL in Supabase, then refresh this page. ' + (fallbackError.message || ''));
    }
  }

  async function recalculateClassPositions(filters) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    filters = filters || {};
    var result = await c.rpc('recalculate_class_positions', {
      p_school_id: school.id,
      p_academic_year: filters.academicYear,
      p_term: filters.term,
      p_programme_id: filters.programmeId,
      p_class_id: filters.classId
    });
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function listResultSummaries(filters) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    filters = filters || {};
    var query = c
      .from('result_summaries')
      .select('*, students(ass_ref_id, first_name, surname, other_names), classes(name), programmes(name)')
      .eq('school_id', school.id);
    if (filters.academicYear) query = query.eq('academic_year', filters.academicYear);
    if (filters.term) query = query.eq('term', filters.term);
    if (filters.programmeId) query = query.eq('programme_id', filters.programmeId);
    if (filters.classId) query = query.eq('class_id', filters.classId);
    if (filters.studentId) query = query.eq('student_id', filters.studentId);
    query = filters.studentId
      ? query.order('calculated_at', { ascending: false })
      : query.order('class_position');
    var result = await query;
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function updateSchoolInfo(payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c
      .from('schools')
      .update({ name: payload.name || school.name })
      .eq('id', school.id)
      .select('*')
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function saveQualitativeAssessment(payload) {
    var c = db();
    if (!c) return null;
    payload = Object.assign({}, payload || {});
    var token = activeStaffSessionToken();
    var user = currentStoredUser();
    var staffUser = user && user.type !== 'student' && user.category && user.category !== 'Student';
    if (token || staffUser) {
      var sessionResult = await c.rpc('secure_save_qualitative_assessment_with_session', {
        p_session_token: token || null,
        p_payload: payload || {}
      });
      if (!sessionResult.error) return sessionResult.data;
      if (/secure_save_qualitative_assessment_with_session|schema cache|function/i.test(sessionResult.error.message || '')) {
        throw new Error('Run the form master qualitative assessment SQL in Supabase, then refresh this page.');
      }
      throw sessionResult.error;
    }
    var school = await currentSchool();
    if (!school) return null;
    payload.captured_by_name = payload.captured_by_name || payload.captured_by || '';
    delete payload.captured_by;
    payload.school_id = school.id;
    var result = await c
      .from('qualitative_assessments')
      .upsert(payload, { onConflict: 'school_id,student_ref,term' })
      .select('*')
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function listQualitativeAssessments(studentRefs) {
    var c = db();
    if (!c) return null;
    var studentToken = activeStudentSessionToken();
    var staffToken = activeStaffSessionToken();
    var storedUser = currentStoredUser();
    var staffUser = storedUser && storedUser.type !== 'student' && storedUser.category && storedUser.category !== 'Student';
    if (studentToken || staffToken || staffUser) {
      var sessionResult = await c.rpc('secure_list_qualitative_assessments', {
        p_school_id: null,
        p_student_refs: studentRefs || [],
        p_student_session_token: studentToken || null,
        p_staff_session_token: staffToken || null
      });
      if (!sessionResult.error) return sessionResult.data || [];
      if (/secure_list_qualitative_assessments|schema cache|function/i.test(sessionResult.error.message || '')) {
        throw new Error('Run the transcript qualitative assessment SQL in Supabase, then refresh this page.');
      }
      throw sessionResult.error;
    }
    var school = await currentSchool();
    if (!school) return null;
    var query = c
      .from('qualitative_assessments')
      .select('*')
      .eq('school_id', school.id)
      .order('updated_at', { ascending: false });
    if (studentRefs && studentRefs.length) query = query.in('student_ref', studentRefs);
    var result = await query;
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function uploadOwnerDocument(ownerType, ownerId, title, file) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var bucket = ownerType === 'student' ? 'student-documents' : 'staff-documents';
    var path = school.code + '/' + ownerType + '/' + ownerId + '/' + Date.now() + '-' + file.name;
    var uploaded = await c.storage.from(bucket).upload(path, file, { upsert: false });
    if (uploaded.error) throw uploaded.error;
    var publicInfo = await c.storage.from(bucket).createSignedUrl(path, 315360000);
    var record = {
      school_id: school.id,
      owner_type: ownerType,
      title: title,
      file_name: file.name,
      file_type: file.name.split('.').pop().toUpperCase(),
      file_size: file.size,
      file_url: publicInfo && publicInfo.data ? publicInfo.data.signedUrl : path
    };
    if (ownerType === 'student') record.student_id = ownerId;
    else record.staff_user_id = ownerId;
    var result = await c.from('documents').insert(record).select('*').single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function uploadStudentPassport(assRefId, file) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !assRefId || !file) return null;
    var session = c.auth && c.auth.getSession ? await c.auth.getSession() : null;
    if (!session || !session.data || !session.data.session) {
      throw new Error('Please reset this School Admin password from Super Admin, log out, then log in again before uploading student pictures.');
    }
    function readPassportDataUrl() {
      return new Promise(function(resolve, reject) {
        var reader = new FileReader();
        reader.onload = function() { resolve(reader.result); };
        reader.onerror = reject;
        reader.readAsDataURL(file);
      });
    }
    var safeName = String(file.name || 'passport.jpg').replace(/[^a-zA-Z0-9._-]+/g, '-');
    var path = school.code + '/' + assRefId + '/' + Date.now() + '-' + safeName;
    var uploaded = await c.storage.from('student-passports').upload(path, file, {
      upsert: false,
      contentType: file.type || undefined
    });
    if (uploaded.error) {
      console.warn('Student passport storage upload failed; saving passport data on student record instead.', uploaded.error);
      var fallbackUrl = await readPassportDataUrl();
      await updateStudentByAssRef(assRefId, { passport_url: fallbackUrl });
      return fallbackUrl;
    }
    var publicInfo = c.storage.from('student-passports').getPublicUrl(path);
    var publicUrl = publicInfo && publicInfo.data ? publicInfo.data.publicUrl : path;
    var signedInfo = await c.storage.from('student-passports').createSignedUrl(path, 315360000);
    if (!signedInfo.error && signedInfo.data && signedInfo.data.signedUrl) {
      publicUrl = signedInfo.data.signedUrl;
    }
    await updateStudentByAssRef(assRefId, { passport_url: publicUrl });
    return publicUrl;
  }

  async function uploadStaffProfilePhoto(staffUserId, file) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !staffUserId || !file) return null;
    function readStaffPhotoDataUrl() {
      return new Promise(function(resolve, reject) {
        var reader = new FileReader();
        reader.onload = function() { resolve(reader.result); };
        reader.onerror = reject;
        reader.readAsDataURL(file);
      });
    }
    var safeName = String(file.name || 'profile.jpg').replace(/[^a-zA-Z0-9._-]+/g, '-');
    var path = school.code + '/profile-photos/' + staffUserId + '/' + Date.now() + '-' + safeName;
    var uploaded = await c.storage.from('staff-documents').upload(path, file, {
      upsert: false,
      contentType: file.type || undefined
    });
    if (uploaded.error) {
      console.warn('Staff profile photo storage upload failed; saving profile photo data on staff record instead.', uploaded.error);
      var fallbackUrl = await readStaffPhotoDataUrl();
      await updateStaffUser(staffUserId, { profile_photo: fallbackUrl });
      return fallbackUrl;
    }
    var publicInfo = c.storage.from('staff-documents').getPublicUrl(path);
    var photoUrl = publicInfo && publicInfo.data ? publicInfo.data.publicUrl : path;
    var signedInfo = await c.storage.from('staff-documents').createSignedUrl(path, 315360000);
    if (!signedInfo.error && signedInfo.data && signedInfo.data.signedUrl) {
      photoUrl = signedInfo.data.signedUrl;
    }
    await updateStaffUser(staffUserId, { profile_photo: photoUrl });
    return photoUrl;
  }

  function readFileDataUrl(file) {
    return new Promise(function(resolve, reject) {
      var reader = new FileReader();
      reader.onload = function() { resolve(reader.result); };
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  }

  async function submitSchemeOfWorkWithSession(token, payload, file, fileInfo) {
    var c = db(), school = await currentSchool();
    if (!c || !token || !payload || !file) return null;
    fileInfo = fileInfo || {};
    var safeName = String(file.name || 'scheme-of-work').replace(/[^a-zA-Z0-9._-]+/g, '-');
    var path = fileInfo.filePath || ((school && school.code ? school.code : activeSchoolCode()) + '/' + (payload.teacher_id || 'staff') + '/' + Date.now() + '-' + safeName);
    var rpcPayload = Object.assign({}, payload, {
      fileName: file.name,
      filePath: path,
      fileUrl: fileInfo.fileUrl || await readFileDataUrl(file)
    });
    var result = await c.rpc('secure_submit_scheme_of_work_with_session', {
      p_session_token: token,
      p_payload: rpcPayload
    });
    if (result.error) throw result.error;
    return result.data;
  }

  async function submitSchemeOfWork(payload, file) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !payload || !payload.teacher_id || !file) return null;
    var token = activeStaffSessionToken();
    if (token) {
      return submitSchemeOfWorkWithSession(token, payload, file);
    }
    var teacherResult = await c
      .from('staff_users')
      .select('id, category, department, position_responsibility')
      .eq('school_id', school.id)
      .eq('id', payload.teacher_id)
      .limit(1)
      .maybeSingle();
    if (teacherResult.error) throw teacherResult.error;
    if (!teacherResult.data || String(teacherResult.data.category || '').toLowerCase() !== 'teaching staff') {
      throw new Error('Only Teaching Staff can submit a scheme of work.');
    }
    var teacherRole = String(teacherResult.data.position_responsibility || '').toLowerCase().replace(/_/g, ' ');
    var teacherIsHod = /(^|[;,])\s*(head of department(?:\s*\(hod\))?|hod)\s*($|[;,])/.test(teacherRole);
    var initialStatus = teacherIsHod ? 'Pending Head Academic' : 'Pending HOD';
    var safeName = String(file.name || 'scheme-of-work').replace(/[^a-zA-Z0-9._-]+/g, '-');
    var path = school.code + '/' + payload.teacher_id + '/' + Date.now() + '-' + safeName;
    var uploaded = await c.storage.from('scheme-of-work').upload(path, file, {
      upsert: false,
      contentType: file.type || undefined
    });
    if (uploaded.error) throw uploaded.error;
    var publicInfo = await c.storage.from('scheme-of-work').createSignedUrl(path, 315360000);
    var row = Object.assign({}, payload, {
      school_id: school.id,
      file_name: file.name,
      file_path: path,
      file_url: publicInfo && publicInfo.data ? publicInfo.data.signedUrl : path,
      department: teacherResult.data.department,
      status: initialStatus
    });
    var result = await c.from('scheme_of_work').insert(row).select('*').single();
    if (result.error) {
      if (token) {
        try {
          return await submitSchemeOfWorkWithSession(token, payload, file, {
            filePath: path,
            fileUrl: publicInfo && publicInfo.data ? publicInfo.data.signedUrl : path
          });
        } catch (rpcErr) {
          await c.storage.from('scheme-of-work').remove([path]);
          throw rpcErr;
        }
      }
      await c.storage.from('scheme-of-work').remove([path]);
      throw result.error;
    }
    var history = await c.from('scheme_of_work_history').insert({
      school_id: school.id,
      scheme_id: result.data.id,
      actor_id: payload.teacher_id,
      action: teacherIsHod ? 'HOD submitted directly to Head Academic' : 'Teaching Staff submitted to HOD'
    });
    if (history.error) console.error(history.error);
    return result.data;
  }

  async function listSchemeOfWork(filters) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    filters = filters || {};
    var query = c
      .from('scheme_of_work')
      .select('*, teacher:staff_users!scheme_of_work_teacher_id_fkey(id, full_name, staff_id, department, position_responsibility)')
      .eq('school_id', school.id)
      .order('submitted_at', { ascending: false });
    if (filters.teacherId) query = query.eq('teacher_id', filters.teacherId);
    if (filters.department) query = query.eq('department', filters.department);
    if (filters.status) query = query.eq('status', filters.status);
    var result = await query;
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function replaceSchemeOfWorkDocument(schemeId, file) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !schemeId || !file) return null;
    var token = activeStaffSessionToken();
    var safeName = String(file.name || 'scheme-document').replace(/[^a-zA-Z0-9._-]+/g, '-');
    var path = school.code + '/scheme-replacements/' + schemeId + '/' + Date.now() + '-' + safeName;
    if (token) {
      var sessionPayload = {
        fileName: file.name,
        filePath: path,
        fileUrl: await readFileDataUrl(file)
      };
      var sessionResult = await c.rpc('secure_replace_scheme_document_with_session', {
        p_session_token: token,
        p_scheme_id: schemeId,
        p_payload: sessionPayload
      });
      if (sessionResult.error) throw sessionResult.error;
      return sessionResult.data;
    }
    var uploaded = await c.storage.from('scheme-of-work').upload(path, file, {
      upsert: true,
      contentType: file.type || undefined
    });
    if (uploaded.error) throw uploaded.error;
    var signedInfo = await c.storage.from('scheme-of-work').createSignedUrl(path, 315360000);
    var fileUrl = signedInfo && signedInfo.data ? signedInfo.data.signedUrl : path;
    var result = await c
      .from('scheme_of_work')
      .update({
        file_name: file.name,
        file_path: path,
        file_url: fileUrl,
        updated_at: new Date().toISOString()
      })
      .eq('school_id', school.id)
      .eq('id', schemeId)
      .select('*')
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function reviewSchemeOfWork(schemeId, stage, approved, reason, reviewerId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !schemeId || !reviewerId) return null;
    var isHod = stage === 'hod';
    var expectedStatus = isHod ? 'Pending HOD' : 'Pending Head Academic';
    var nextStatus = isHod
      ? (approved ? 'Pending Head Academic' : 'Declined by HOD')
      : (approved ? 'Final Approved' : 'Declined by Head Academic');
    if (!approved && !String(reason || '').trim()) throw new Error('A decline reason is required.');
    var reviewerResult = await c.from('staff_users').select('id, category, department, position_responsibility').eq('school_id', school.id).eq('id', reviewerId).limit(1).maybeSingle();
    if (reviewerResult.error) throw reviewerResult.error;
    var schemeResult = await c.from('scheme_of_work').select('id, teacher_id, department, status, hod_reviewer_id, teacher:staff_users!scheme_of_work_teacher_id_fkey(position_responsibility)').eq('school_id', school.id).eq('id', schemeId).limit(1).maybeSingle();
    if (schemeResult.error) throw schemeResult.error;
    if (!reviewerResult.data || !schemeResult.data) throw new Error('Reviewer or scheme of work was not found.');
    var roleText = String(reviewerResult.data.position_responsibility || '').toLowerCase().replace(/_/g, ' ');
    var reviewerIsHod = /(^|[;,])\s*(head of department(?:\s*\(hod\))?|hod)\s*($|[;,])/.test(roleText);
    var reviewerIsHeadAcademic = /assistant headmaster\s*\(academics\)|head\s+(?:of\s+)?academics?|academic head/.test(roleText);
    if (String(reviewerResult.data.category || '').toLowerCase() !== 'teaching staff') throw new Error('Only Teaching Staff reviewers can process schemes of work.');
    if (isHod && !reviewerIsHod) throw new Error('Only a staff member with the HOD position can complete HOD review.');
    if (isHod && !String(reviewerResult.data.department || '').trim()) throw new Error('The HOD must have a department assigned.');
    if (isHod && String(reviewerResult.data.department || '').trim().toLowerCase() !== String(schemeResult.data.department || '').trim().toLowerCase()) throw new Error('This scheme belongs to a different department.');
    if (isHod && schemeResult.data.teacher_id === reviewerId) throw new Error('An HOD cannot review their own scheme of work.');
    if (!isHod && !reviewerIsHeadAcademic) throw new Error('Only the Head Academic can complete final review.');
    if (!isHod && !schemeResult.data.hod_reviewer_id) {
      var submitterRole = String(schemeResult.data.teacher && schemeResult.data.teacher.position_responsibility || '').toLowerCase().replace(/_/g, ' ');
      var submitterIsHod = /(^|[;,])\s*(head of department(?:\s*\(hod\))?|hod)\s*($|[;,])/.test(submitterRole);
      if (!submitterIsHod) throw new Error('This scheme has not been approved by an HOD.');
    }
    if (schemeResult.data.status !== expectedStatus) throw new Error('This scheme has already been reviewed or is no longer pending.');
    var changes = { status: nextStatus };
    if (isHod) {
      changes.hod_reviewer_id = reviewerId;
      changes.hod_decision_at = new Date().toISOString();
      changes.hod_reason = approved ? null : String(reason).trim();
    } else {
      changes.head_academic_reviewer_id = reviewerId;
      changes.head_academic_decision_at = new Date().toISOString();
      changes.head_academic_reason = approved ? null : String(reason).trim();
    }
    var result = await c
      .from('scheme_of_work')
      .update(changes)
      .eq('school_id', school.id)
      .eq('id', schemeId)
      .eq('status', expectedStatus)
      .select('*')
      .maybeSingle();
    if (result.error) throw result.error;
    if (!result.data) throw new Error('This scheme has already been reviewed or is no longer pending.');
    var action = approved
      ? (isHod ? 'Approved by HOD and forwarded to Head Academic' : 'Final approval by Head Academic')
      : (isHod ? 'Declined by HOD' : 'Declined by Head Academic');
    var history = await c.from('scheme_of_work_history').insert({
      school_id: school.id,
      scheme_id: schemeId,
      actor_id: reviewerId,
      action: action,
      reason: approved ? null : String(reason).trim()
    });
    if (history.error) console.error(history.error);
    return result.data;
  }

  async function listSchemeOfWorkHistory(schemeId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !schemeId) return null;
    var result = await c
      .from('scheme_of_work_history')
      .select('*, actor:staff_users!scheme_of_work_history_actor_id_fkey(full_name, staff_id)')
      .eq('school_id', school.id)
      .eq('scheme_id', schemeId)
      .order('created_at');
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function listClearanceRequirements() {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var result = await c
      .from('clearance_requirements')
      .select('*, staff_users(id, full_name, staff_id, position_responsibility)')
      .eq('school_id', school.id)
      .order('sort_order')
      .order('title');
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function saveClearanceRequirement(payload) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var row = {
      school_id: school.id,
      title: payload.title,
      position_title: payload.position_title,
      staff_user_id: payload.staff_user_id || null,
      is_required: payload.is_required !== false,
      sort_order: Number(payload.sort_order || 1),
      active: payload.active !== false,
      updated_at: new Date().toISOString()
    };
    var query = payload.id
      ? c.from('clearance_requirements').update(row).eq('school_id', school.id).eq('id', payload.id)
      : c.from('clearance_requirements').insert(row);
    var result = await query.select('*').single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function deleteClearanceRequirement(requirementId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !requirementId) return null;
    var result = await c.from('clearance_requirements').delete().eq('school_id', school.id).eq('id', requirementId);
    if (result.error) throw result.error;
    return true;
  }

  async function initializeStudentClearance(studentId) {
    var c = db();
    if (!c || !studentId) return null;
    var result = await c.rpc('initialize_student_clearance', { p_student_id: studentId });
    if (result.error) throw result.error;
    return result.data;
  }

  function clearanceStudentIsCompleted(row) {
    var student = row && row.students ? row.students : null;
    if (!student) return false;
    var status = String(student.status || '').trim().toLowerCase();
    var level = String(student.student_level || '').trim().toLowerCase();
    return status === 'completed' || level === 'completed';
  }

  function completedClearanceRows(rows) {
    return (rows || []).filter(clearanceStudentIsCompleted);
  }

  async function listStudentClearances(filters) {
    var c = db();
    if (!c) return null;
    filters = filters || {};
    var adminMode = filters.admin === true;
    if (!adminMode && (filters.studentAssRef || filters.studentId)) {
      var studentToken = activeStudentSessionToken();
      if (!studentToken) {
        throw new Error('Student session expired. Please logout and login again to view clearance status.');
      }
      var studentFeed = await c.rpc('secure_list_my_student_clearances', {
        p_ass_ref_id: filters.studentAssRef || null,
        p_session_token: studentToken
      });
      if (!studentFeed.error) return completedClearanceRows(studentFeed.data || []);
      if (/p_session_token|Could not find the function|schema cache|function/i.test(studentFeed.error.message || '')) {
        throw new Error('Run the student clearance session SQL in Supabase, then logout and login again.');
      }
      if (!/secure_list_my_student_clearances|schema cache|function/i.test(studentFeed.error.message || '')) {
        throw studentFeed.error;
      }
    }
    if (!adminMode && !filters.studentAssRef && !filters.studentId) {
      var staffFeed = await c.rpc('secure_list_staff_clearances', {
        p_session_token: activeStaffSessionToken() || null
      });
      if (!staffFeed.error) return completedClearanceRows(staffFeed.data || []);
      if (/secure_list_staff_clearances|schema cache|function/i.test(staffFeed.error.message || '')) {
        throw new Error('Run the clearance assignment scope SQL in Supabase, then refresh this page.');
      }
      throw staffFeed.error;
    }
    var school = await currentSchool();
    if (!school) return null;
    var resolvedStudentId = filters.studentId || null;
    if (filters.studentAssRef) {
      var studentLookup = await c
        .from('students')
        .select('id')
        .eq('school_id', school.id)
        .eq('ass_ref_id', String(filters.studentAssRef || '').trim())
        .limit(1)
        .maybeSingle();
      if (studentLookup.error) throw studentLookup.error;
      if (studentLookup.data && studentLookup.data.id) resolvedStudentId = studentLookup.data.id;
    }
    var query = c
      .from('student_clearances')
      .select('*, students(id, ass_ref_id, first_name, surname, other_names, status, student_level, passport_url, classes(name, programmes(name))), clearance_requirements(title, is_required), assigned_staff:staff_users!student_clearances_assigned_staff_user_id_fkey(id, full_name, staff_id), reviewer:staff_users!student_clearances_reviewed_by_fkey(id, full_name, staff_id)')
      .eq('school_id', school.id)
      .order('created_at', { ascending: false });
    if (resolvedStudentId) query = query.eq('student_id', resolvedStudentId);
    if (filters.status) query = query.eq('status', filters.status);
    var result = await query;
    if (result.error) throw result.error;
    return completedClearanceRows(result.data || []);
  }

  async function reviewStudentClearance(clearanceId, status, reason) {
    var c = db();
    if (!c || !clearanceId) return null;
    var result = await c.rpc('review_student_clearance', {
      p_clearance_id: clearanceId,
      p_status: status,
      p_reason: reason || null,
      p_session_token: activeStaffSessionToken() || null
    });
    if (result.error && /review_student_clearance|schema cache|function|p_session_token/i.test(result.error.message || '')) {
      result = await c.rpc('review_student_clearance', {
        p_clearance_id: clearanceId,
        p_status: status,
        p_reason: reason || null
      });
    }
    if (result.error) throw result.error;
    return result.data;
  }
  async function listDocuments(ownerType, ownerId) {
    var c = db(), school = await currentSchool();
    if (!c || !school) return null;
    var query = c.from('documents').select('*').eq('school_id', school.id).order('uploaded_at', { ascending: false });
    if (ownerType === 'staff') query = query.eq('owner_type', 'staff').eq('staff_user_id', ownerId);
    if (ownerType === 'student') query = query.eq('owner_type', 'student').eq('student_id', ownerId);
    var result = await query;
    if (result.error) throw result.error;
    return result.data;
  }

  async function listStudentTranscript(studentId) {
    var c = db(), school = await currentSchool();
    if (!c || !school || !studentId) return null;
    var studentResult = await c
      .from('students')
      .select('*, classes(name, programmes(name))')
      .eq('school_id', school.id)
      .eq('id', studentId)
      .limit(1)
      .maybeSingle();
    if (studentResult.error) throw studentResult.error;
    if (!studentResult.data) throw new Error('Student record was not found.');

    var scoreResult = await c
      .from('assessment_scores')
      .select('score, grade, remark, assessments(academic_year, year_level, semester, overall_score, status, subjects(name, subject_type), classes(name), assessment_modes(name, display_order))')
      .eq('student_id', studentId)
      .order('updated_at', { ascending: false });
    if (scoreResult.error) throw scoreResult.error;
    var summaries = [];
    var summaryResult = await c
      .from('result_summaries')
      .select('*')
      .eq('school_id', school.id)
      .eq('student_id', studentId)
      .order('calculated_at', { ascending: false });
    if (!summaryResult.error) summaries = summaryResult.data || [];
    return {
      student: studentResult.data,
      scores: (scoreResult.data || []).filter(function (row) {
        return row.assessments && row.assessments.status === 'Submitted';
      }),
      summaries: summaries
    };
  }

  async function deleteDocument(documentId) {
    var c = db();
    if (!c || !documentId) return null;
    var result = await c.rpc('secure_delete_document', { p_document_id: documentId });
    if (result.error) throw result.error;
    return result.data === true;
  }

  w.AxiomDB = {
    config: CONFIG,
    isConfigured: configured,
    client: db,
    activeSchoolCode: activeSchoolCode,
    setActiveSchool: setActiveSchool,
    authSession: authSession,
    restoreSessionUser: restoreSessionUser,
    signOut: signOut,
    loadAuthProfile: loadAuthProfile,
    currentSchool: currentSchool,
    loginSuperAdmin: loginSuperAdmin,
    listSchools: listSchools,
    createSchool: createSchool,
    updateSchool: updateSchool,
    listSchoolAdmins: listSchoolAdmins,
    createSchoolAdmin: createSchoolAdmin,
    updateSchoolAdmin: updateSchoolAdmin,
    resetSchoolAdminPassword: resetSchoolAdminPassword,
    deleteSchoolAdmin: deleteSchoolAdmin,
    submitSchoolSignup: submitSchoolSignup,
    listSchoolSignupRequests: listSchoolSignupRequests,
    approveSchoolSignup: approveSchoolSignup,
    listDepartments: listDepartments,
    createDepartment: createDepartment,
    updateDepartment: updateDepartment,
    deleteDepartment: deleteDepartment,
    listProgrammes: listProgrammes,
    listSubjects: listSubjects,
    listClasses: listClasses,
    createProgramme: createProgramme,
    deleteProgramme: deleteProgramme,
    createSubject: createSubject,
    deleteSubject: deleteSubject,
    createClass: createClass,
    updateClass: updateClass,
    deleteClass: deleteClass,
    listHouses: listHouses,
    createHouse: createHouse,
    deleteHouse: deleteHouse,
    listStudents: listStudents,
    createStudent: createStudent,
    ensureStudentAccount: ensureStudentAccount,
    updateStudentByAssRef: updateStudentByAssRef,
    progressStudents: progressStudents,
    deleteStudentByAssRef: deleteStudentByAssRef,
    listStaff: listStaff,
    getStaffUser: getStaffUser,
    createStaffUser: createStaffUser,
    updateStaffUser: updateStaffUser,
    deleteStaffUser: deleteStaffUser,
    loginStaff: loginStaff,
    loginStudent: loginStudent,
    listUserPrivileges: listUserPrivileges,
    saveUserPrivileges: saveUserPrivileges,
    listStaffSubjectClasses: listStaffSubjectClasses,
    saveStaffSubjectClasses: saveStaffSubjectClasses,
    listAssessmentModes: listAssessmentModes,
    captureAssessmentSetup: captureAssessmentSetup,
    saveAssessmentScores: saveAssessmentScores,
    listAssessmentRecords: listAssessmentRecords,
    listSchoolAssessmentMonitor: listSchoolAssessmentMonitor,
    recalculateClassPositions: recalculateClassPositions,
    listResultSummaries: listResultSummaries,
    updateSchoolInfo: updateSchoolInfo,
    qualitativeAssessmentSetup: qualitativeAssessmentSetup,
    saveQualitativeAssessment: saveQualitativeAssessment,
    listQualitativeAssessments: listQualitativeAssessments,
    uploadStudentPassport: uploadStudentPassport,
    uploadStaffProfilePhoto: uploadStaffProfilePhoto,
      submitSchemeOfWork: submitSchemeOfWork,
      listSchemeOfWork: listSchemeOfWork,
      replaceSchemeOfWorkDocument: replaceSchemeOfWorkDocument,
      reviewSchemeOfWork: reviewSchemeOfWork,
    listSchemeOfWorkHistory: listSchemeOfWorkHistory,
    listClearanceRequirements: listClearanceRequirements,
    saveClearanceRequirement: saveClearanceRequirement,
    deleteClearanceRequirement: deleteClearanceRequirement,
    initializeStudentClearance: initializeStudentClearance,
    listStudentClearances: listStudentClearances,
    reviewStudentClearance: reviewStudentClearance,
    uploadOwnerDocument: uploadOwnerDocument,
    listDocuments: listDocuments,
    listStudentTranscript: listStudentTranscript,
    deleteDocument: deleteDocument
  };
})(window);







