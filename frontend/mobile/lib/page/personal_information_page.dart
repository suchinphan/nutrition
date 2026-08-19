import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/app_config.dart';
import '../utils/bmi_calculator.dart' as bmi_calc;
import 'show_bmi_and_suggested_calories.dart';
import 'register_login_page.dart';

class PersonalInformationPage extends StatefulWidget {
  final bool isEditMode;
  const PersonalInformationPage({super.key, this.isEditMode = false});

  @override
  State<PersonalInformationPage> createState() =>
      _PersonalInformationPageState();
}

class _PersonalInformationPageState extends State<PersonalInformationPage> {
  final Color primaryGreen = AppColors.leaf;
  // guest personal data stored in-memory via AuthService

  final TextEditingController nameController = TextEditingController();
  final TextEditingController surnameController = TextEditingController();
  final TextEditingController genderController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  final TextEditingController heightController = TextEditingController();

  // Date components for dd/MM/yyyy (Thai BE year)
  String? _selectedDay;
  int? _selectedMonthIndex; // 1-12
  int? _selectedYearBE; // Buddhist Era (พ.ศ.)

  // Chronic diseases and allergies
  final List<String> _selectedDiseases = [];
  final List<String> _selectedAllergies = [];
  // `other_disease` and `other_allergy` removed — handled via
  // `diseasesController` and `allergiesController` only.
  // Free-text controllers (comma-separated values)
  final TextEditingController diseasesController = TextEditingController();
  final TextEditingController allergiesController = TextEditingController();
  // Medical lists fetched from backend
  List<String> _canonicalDiseases = [];
  List<String> _canonicalAllergies = [];
  List<String> _diseaseSuggestions = [];
  List<String> _allergySuggestions = [];
  final List<String> _thaiMonthNames = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
    'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
  ];

  String? _selectedGender;
  String? _selectedAge;
  String? _selectedWeight;
  String? _selectedHeight;
  final List<String> _activityOptions = [
    'ไม่ออกกำลังกายหรือออกกำลังกายน้อยมาก',
    'ออกกำลังกาย/เล่นกีฬา 1-3 วัน/สัปดาห์',
    'ออกกำลังกายปานกลาง/เล่นกีฬา 3-5 วัน/สัปดาห์',
    'ออกกำลังกายหนัก/เล่นกีฬา 6-7 วัน/สัปดาห์',
    'ออกกำลังกายหนักมากเป็นนักกีฬา',
  ];
  String? _selectedActivity = 'ไม่ออกกำลังกายหรือออกกำลังกายน้อยมาก';

  // Inline validation error messages
  String? _genderError;
  String? _ageError;
  String? _weightError;
  String? _heightError;
  String? _bmiError;

  bool _saving = false;
  bool _authLoaded = false;
  bool _authSyncing = false;

  // `_hasPersonalInfo` is computed from AuthService (single source of truth)
  bool get _hasPersonalInfo {
    final auth = AuthService();
    
    final Map<String, dynamic> p = auth.isGuest
        ? (auth.guestPersonal ?? <String, dynamic>{})
        : (auth.user ?? <String, dynamic>{});
    final g = (p['gender']?.toString() ?? '').trim();
    final a = (p['age']?.toString() ?? '').trim();
    final w = (p['weight']?.toString() ?? '').trim();
    final h = (p['height']?.toString() ?? '').trim();
    return g.isNotEmpty && a.isNotEmpty && w.isNotEmpty && h.isNotEmpty;
  }

  final List<String> _genderOptions = ['ชาย', 'หญิง'];
  // Age input will accept a birth date in dd/MM/yyyy format

  bool get guestUsedEffective => AuthService().guestUsed;

  @override
  void initState() {
    super.initState();
    // Refresh UI when AuthService notifies (e.g., after login/profile fetch)
    AuthService().addListener(_handleAuthChange);
    Future.microtask(() async {
      if (widget.isEditMode) {
        // In edit mode, load existing saved user and refresh from server
        await _loadSavedUser();
        try {
          await AuthService().refreshProfile();
          await _loadSavedUser();
        } catch (_) {}
      } else {
        // New registration: clear any stale values so user starts with empty form
        _clearFormForNewRegistration();
      }
      await _fetchMedicalLists();
      // Also attempt to pre-fill form from the latest AuthService().user
      try {
        _prefillFromAuthUser();
      } catch (_) {}
    });
  }

  void _handleAuthChange() {
    if (!mounted) return;
    if (!_authSyncing && widget.isEditMode) {
      // Only reload saved user data when in edit mode
      _authSyncing = true;
      _loadSavedUser().whenComplete(() {
        _authSyncing = false;
      });
    }
  }

  Future<void> _fetchMedicalLists() async {
    try {
      final uri = Uri.parse('${_backendBase()}/api/medical-lists');
      final resp = await http.get(uri).timeout(Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final Map<String, dynamic> j = json.decode(resp.body);
        setState(() {
          _canonicalDiseases = ((j['diseases'] as List?) ?? []).map((e) => e.toString()).toList();
          _canonicalAllergies = ((j['allergies'] as List?) ?? []).map((e) => e.toString()).toList();
        });
      }
    } catch (_) {}
  }

  void _updateDiseaseSuggestions(String text) {
    final last = text.split(',').last.trim().toLowerCase();
    if (last.isEmpty) {
      setState(() => _diseaseSuggestions = []);
      return;
    }
    // If user explicitly answered 'ไม่มี' (none), do not show suggestions
    if (last == 'ไม่มี') {
      setState(() => _diseaseSuggestions = []);
      return;
    }
    final s = _canonicalDiseases.where((d) => d.toLowerCase().contains(last) && !text.split(',').map((t) => t.trim()).contains(d)).toList();
    setState(() => _diseaseSuggestions = s.take(6).toList());
  }

  void _updateAllergySuggestions(String text) {
    final last = text.split(',').last.trim().toLowerCase();
    if (last.isEmpty) {
      setState(() => _allergySuggestions = []);
      return;
    }
    // If user explicitly answered 'ไม่มี' (none), do not show suggestions
    if (last == 'ไม่มี') {
      setState(() => _allergySuggestions = []);
      return;
    }
    final s = _canonicalAllergies.where((d) => d.toLowerCase().contains(last) && !text.split(',').map((t) => t.trim()).contains(d)).toList();
    setState(() => _allergySuggestions = s.take(6).toList());
  }

  String _replaceLastToken(String original, String replacement) {
    final parts = original.split(',');
    if (parts.isEmpty) return replacement;
    parts[parts.length - 1] = ' $replacement';
    return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(', ');
  }

  int _toGregorianYear(int y) {
    // Convert Buddhist Era year (พ.ศ.) to Gregorian year (AD) when needed.
    // Heuristic: years > 2400 are likely BE (e.g., 2569 -> 2026)
    if (y > 2400) return y - 543;
    return y;
  }

  // ponytail: สูตรอายุจากวันเกิดเดิมถูกก๊อปวางซ้ำ ~10 จุดในไฟล์นี้ รวมเป็นจุดเดียว
  // yearBE ผ่าน _toGregorianYear ก่อนเสมอ (แปลงเฉพาะปีที่ดูเป็น พ.ศ. จริง ๆ ปี ค.ศ. ที่ส่งมาตรง ๆ จะไม่ถูกแตะ)
  int? _ageFromDob(int day, int month, int yearBE) {
    try {
      final gy = _toGregorianYear(yearBE);
      final now = DateTime.now();
      int ageVal = now.year - gy - ((now.month < month || (now.month == month && now.day < day)) ? 1 : 0);
      if (ageVal < 0) ageVal = 0;
      return ageVal;
    } catch (_) {
      return null;
    }
  }

  String _backendBase() {
    // Adjust base URL if different (development uses localhost:5000)
    return 'http://localhost:5000';
  }

  int _daysInMonthFromSelection([int? monthIndex, int? yearBE]) {
    final int? m = monthIndex ?? _selectedMonthIndex;
    final int? yBE = yearBE ?? _selectedYearBE;
    if (m == null) return 31;
    final gy = yBE != null ? _toGregorianYear(yBE) : DateTime.now().year;
    // DateTime(year, month+1, 0).day yields last day of `month`.
    try {
      return DateTime(gy, m + 1, 0).day;
    } catch (_) {
      return 31;
    }
  }

  /// schema ใหม่เก็บ chronic_diseases/food_allergies เป็น JSON array เสมอ
  /// (ของเดิมเป็นสตริงคั่นด้วย comma) — สองเมธอดนี้แปลงไปมาให้ฟอร์ม/ตัวแปร
  /// เดิมในไฟล์นี้ (ที่ทำงานกับ String/List ปนกันอยู่) ใช้ต่อได้โดยไม่ต้อง
  /// เขียนฟอร์มใหม่ทั้งหมด
  List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty || t.toLowerCase() == 'ไม่มี') return [];
      return t.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  String _joinForDisplay(dynamic v) {
    final list = _asStringList(v);
    return list.isEmpty ? 'ไม่มี' : list.join(', ');
  }

  String? _normalizeNumberString(dynamic v) {
    if (v == null) return null;
    try {
      if (v is num) {
        if (v == v.toInt()) return v.toInt().toString();
        return v.toString();
      }
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      if (s.contains('.')) {
        final parts = s.split('.');
        if (parts.length == 2 && int.tryParse(parts[1]) == 0) return parts[0];
      }
      return s;
    } catch (_) {
      return v.toString();
    }
  }

  Future<List<Map<String, dynamic>>> _validateMedicalItems(List<String> items, String type) async {
    try {
      final uri = Uri.parse('${_backendBase()}/api/validate-medical');
      final body = json.encode({'type': type, 'items': items});
      final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: body).timeout(Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final Map<String, dynamic> j = json.decode(resp.body);
        final List<Map<String, dynamic>> results = [];
        for (final r in (j['results'] as List? ?? [])) {
          results.add(Map<String, dynamic>.from(r));
        }
        return results;
      }
    } catch (_) {}
    return [];
  }

  Future<void> _loadSavedUser() async {
    try {
      final auth = AuthService();
        await (auth as dynamic).loadToken();
      final u = auth.user;
      // If guest, try to load in-memory guest personal info
      if (auth.isGuest) {
        try {
          final parsed = auth.guestPersonal;
          if (parsed != null) {
            _selectedGender = parsed['gender']?.toString();
            // prefer SQL date_of_birth (yyyy-mm-dd) -> display dd/MM/yyyy
            final dob = parsed['date_of_birth']?.toString();
                    if (dob != null && dob.isNotEmpty) {
              try {
                  final parts = dob.split('-');
                  if (parts.length >= 3) {
                    // dob from backend is yyyy-mm-dd (AD)
                    final d = parts[2];
                    final m = parts[1];
                    final y = parts[0];
                    _selectedDay = d.startsWith('0') ? d.substring(1) : d;
                    _selectedMonthIndex = int.tryParse(m);
                    final int? yAD = int.tryParse(y);
                    if (yAD != null) _selectedYearBE = yAD + 543;
                    // compute numeric age (years) from dob
                    final ageVal = _ageFromDob(
                      int.tryParse(_selectedDay ?? '0') ?? 0,
                      _selectedMonthIndex ?? 1,
                      yAD ?? DateTime.now().year,
                    );
                    _selectedAge = ageVal?.toString() ?? parsed['age']?.toString();
                    ageController.text = _selectedAge ?? '';
                  }
              } catch (_) {
                _selectedAge = parsed['age']?.toString();
                ageController.text = _selectedAge ?? '';
              }
            } else {
              _selectedAge = parsed['age']?.toString();
            }
            // Normalize numeric weight/height so they match dropdown item strings
            _selectedWeight = _normalizeNumberString(parsed['weight']);
            _selectedHeight = _normalizeNumberString(parsed['height']);
            _selectedActivity = parsed['activity_level']?.toString() ?? _selectedActivity;
            // Load chronic/allergy for guests — schema ใหม่เก็บเป็น List เสมอ
            try {
                _selectedDiseases.clear();
                _selectedDiseases.addAll(_asStringList(parsed['chronic_diseases']));
                diseasesController.text = _joinForDisplay(parsed['chronic_diseases']);

                _selectedAllergies.clear();
                _selectedAllergies.addAll(_asStringList(parsed['food_allergies']));
                allergiesController.text = _joinForDisplay(parsed['food_allergies']);
            } catch (_) {}

            genderController.text = _selectedGender ?? '';
            ageController.text = _selectedAge ?? '';
            weightController.text = _selectedWeight ?? '';
            heightController.text = _selectedHeight ?? '';
          }
        } catch (_) {}
      }

      setState(() {
        if (u != null) {
          nameController.text = u['name']?.toString() ?? '';
          surnameController.text = u['surname']?.toString() ?? '';
          _selectedGender = u['gender']?.toString();
          final dob = u['date_of_birth']?.toString();
          if (dob != null && dob.isNotEmpty) {
            try {
              final parts = dob.split('-');
                if (parts.length >= 3) {
                final d = parts[2];
                final m = parts[1];
                final y = parts[0];
                _selectedDay = d.startsWith('0') ? d.substring(1) : d;
                _selectedMonthIndex = int.tryParse(m);
                final int? yAD = int.tryParse(y);
                if (yAD != null) _selectedYearBE = yAD + 543;
                // compute numeric age (years)
                final ageVal = _ageFromDob(
                  int.tryParse(_selectedDay ?? '0') ?? 0,
                  _selectedMonthIndex ?? 1,
                  yAD ?? DateTime.now().year,
                );
                _selectedAge = ageVal?.toString() ?? u['age']?.toString();
                ageController.text = _selectedAge ?? '';
              }
            } catch (_) {
              _selectedAge = u['age']?.toString();
              ageController.text = _selectedAge ?? '';
            }
          } else {
            _selectedAge = u['age']?.toString();
          }
          _selectedWeight = _normalizeNumberString(u['weight']);
          _selectedHeight = _normalizeNumberString(u['height']);
          _selectedActivity = u['activity_level']?.toString() ?? _selectedActivity;
          // load chronic/allergy — schema ใหม่เก็บเป็น List เสมอ
          try {
            _selectedDiseases.clear();
            _selectedDiseases.addAll(_asStringList(u['chronic_diseases']));
            diseasesController.text = _joinForDisplay(u['chronic_diseases']);

            _selectedAllergies.clear();
            _selectedAllergies.addAll(_asStringList(u['food_allergies']));
            allergiesController.text = _joinForDisplay(u['food_allergies']);
          } catch (_) {}
          genderController.text = _selectedGender ?? '';
          ageController.text = _selectedAge ?? '';
          weightController.text = _selectedWeight ?? '';
          heightController.text = _selectedHeight ?? '';
          // `_hasPersonalInfo` is computed from AuthService; no manual assignment here.
        }
        _authLoaded = true;
      });
    } catch (_) {
      setState(() {
        _authLoaded = true;
      });
    }
  }

  void _clearFormForNewRegistration() {
    try {
      // Clear selection fields and controllers so new users see empty form
      _selectedDay = null;
      _selectedMonthIndex = null;
      _selectedYearBE = null;
      _selectedGender = null;
      _selectedAge = null;
      _selectedWeight = null;
      _selectedHeight = null;
      _selectedDiseases.clear();
      _selectedAllergies.clear();
      diseasesController.text = '';
      allergiesController.text = '';
      // If we have a persisted guestPersonal activity, keep it instead
      try {
        final gp = AuthService().guestPersonal;
        if (gp != null && gp['activity_level'] != null && gp['activity_level'].toString().trim().isNotEmpty) {
          _selectedActivity = gp['activity_level'].toString().trim();
        } else {
          _selectedActivity = _activityOptions.first;
        }
      } catch (_) {
        _selectedActivity = _activityOptions.first;
      }
      nameController.text = '';
      surnameController.text = '';
      genderController.text = '';
      ageController.text = '';
      weightController.text = '';
      heightController.text = '';
      // mark authLoaded so UI renders immediately
      _authLoaded = true;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _prefillFromAuthUser() {
    try {
      final auth = AuthService();
      final u = auth.user;
      if (u == null) return;
      // Only pre-fill fields that are currently empty to avoid overwriting user input
      final g = u['gender']?.toString() ?? '';
      final ageVal = u['age']?.toString() ?? '';
      final weightVal = _normalizeNumberString(u['weight']) ?? '';
      final heightVal = _normalizeNumberString(u['height']) ?? '';
      final dob = u['date_of_birth']?.toString() ?? '';
      final cd = _joinForDisplay(u['chronic_diseases']);
      final fa = _joinForDisplay(u['food_allergies']);
      final activityVal = u['activity_level']?.toString() ?? '';
      final nameVal = u['name']?.toString() ?? '';
      final surnameVal = u['surname']?.toString() ?? '';

      // Set controllers only when the controller is empty
      if ((nameController.text).trim().isEmpty && nameVal.isNotEmpty) {
        nameController.text = nameVal;
      }
      if ((surnameController.text).trim().isEmpty && surnameVal.isNotEmpty) {
        surnameController.text = surnameVal;
      }
      if ((genderController.text).trim().isEmpty && g.isNotEmpty) {
        genderController.text = g;
        _selectedGender = g;
      }
      if ((ageController.text).trim().isEmpty && ageVal.isNotEmpty) {
        ageController.text = ageVal;
        _selectedAge = ageVal;
      }
      if ((weightController.text).trim().isEmpty && weightVal.isNotEmpty) {
        weightController.text = weightVal;
        _selectedWeight = weightVal;
      }
      if ((heightController.text).trim().isEmpty && heightVal.isNotEmpty) {
        heightController.text = heightVal;
        _selectedHeight = heightVal;
      }
      if ((
            _selectedActivity == null ||
            _selectedActivity!.isEmpty ||
            (_activityOptions.isNotEmpty && _selectedActivity == _activityOptions.first)
          ) && activityVal.isNotEmpty) {
        _selectedActivity = activityVal.trim();
      }

      // Chronic diseases and allergies: fill when not empty (preserve literal 'ไม่มี')
      if ((diseasesController.text).trim().isEmpty && cd.isNotEmpty) {
        diseasesController.text = cd;
        _selectedDiseases.clear();
        if (cd.trim().toLowerCase() != 'ไม่มี') {
          _selectedDiseases.addAll(cd.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
        }
      }
      if ((allergiesController.text).trim().isEmpty && fa.isNotEmpty) {
        allergiesController.text = fa;
        _selectedAllergies.clear();
        if (fa.trim().toLowerCase() != 'ไม่มี') {
          _selectedAllergies.addAll(fa.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
        }
      }

      // Parse date_of_birth (expected format yyyy-mm-dd) and set day/month/year (AD)
      if (dob.isNotEmpty) {
        try {
          final parts = dob.split('-');
          if (parts.length >= 3) {
            final y = int.tryParse(parts[0]);
            final m = int.tryParse(parts[1]);
            final d = parts[2];
            if (d.isNotEmpty) {
              final dayStr = d.startsWith('0') ? d.substring(1) : d;
              if (( _selectedDay == null || _selectedDay!.isEmpty) ) {
                _selectedDay = dayStr;
              }
              if ((_selectedMonthIndex == null) && m != null) _selectedMonthIndex = m;
              // Convert backend year (usually Gregorian AD) to Thai BE for UI
              // dropdown which expects BE years. If the year already looks like
              // a BE year (>2400), keep it as-is.
              if ((_selectedYearBE == null) && y != null) {
                _selectedYearBE = (y > 2400) ? y : (y + 543);
              }

              // Update age controller if empty: compute from dob — ใช้ helper
              // เดียวกับที่เหลือของไฟล์นี้ (_ageFromDob) แทนก็อปสูตรซ้ำเอง
              // (บั๊กที่เจอจริง — comment บรรทัด 192 อ้างว่า consolidate ไปแล้ว
              // แต่จุดนี้หลุดไป)
              if ((ageController.text).trim().isEmpty && y != null) {
                final calcAge = _ageFromDob(int.tryParse(dayStr) ?? 1, m ?? 1, y);
                if (calcAge != null) {
                  ageController.text = calcAge.toString();
                  _selectedAge = calcAge.toString();
                }
              }
            }
          }
        } catch (_) {}
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  Widget _dropdownField(
    String hint,
    String? value,
    List<String> items,
    ValueChanged<String?>? onChanged, {
    bool enabled = true,
    String? error,
  }) {
    final uniq = items.toSet().toList();
    String? safeInitial;
    if (value != null && uniq.where((e) => e == value).length == 1) {
      safeInitial = value;
    }
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: safeInitial,
            hint: Text(hint, overflow: TextOverflow.ellipsis, maxLines: 1),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderSide: BorderSide.none),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              filled: true,
              fillColor: AppColors.line,
              errorText: error,
            ),
            items: uniq
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e,
                      style: TextStyle(color: Colors.black),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _smallDropdown<T>(
    String hint,
    T? value,
    List<T> items,
    ValueChanged<T?>? onChanged, {
    bool enabled = true,
    String? error,
    double? width = 100,
  }) {
    final uniq = items.toSet().toList();
    T? safeInitial;
    if (value != null && uniq.where((e) => e == value).length == 1) safeInitial = value;
    final child = IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: DropdownButtonFormField<T>(
            isExpanded: true,
            initialValue: safeInitial,
            hint: Text(hint, overflow: TextOverflow.ellipsis, maxLines: 1),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderSide: BorderSide.none),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              filled: true,
              fillColor: AppColors.line,
              errorText: error,
            ),
            items: uniq
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e.toString(),
                      style: TextStyle(color: Colors.black),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
    if (width != null) return SizedBox(width: width, child: child);
    return child;
  }

  bool _validateAll() {
    _genderError = null;
    _ageError = null;
    _weightError = null;
    _heightError = null;
    _bmiError = null;

    final sg = genderController.text.trim();
    // build age string from date parts if present, otherwise fallback
    String sa;
    if ((_selectedDay != null && _selectedMonthIndex != null && _selectedYearBE != null) && _selectedDay!.isNotEmpty) {
      sa = '${_selectedDay!.padLeft(2, '0')}/${_selectedMonthIndex!.toString().padLeft(2, '0')}/${_selectedYearBE!.toString()}';
    } else {
      sa = ageController.text.trim();
    }
    final sw = weightController.text.trim();
    final sh = heightController.text.trim();

    if (sg.isEmpty) _genderError = 'กรุณาเลือกเพศ';
    if (sa.isEmpty) _ageError = 'กรุณาเลือกอายุ';
    if (sw.isEmpty) _weightError = 'กรุณาเลือกน้ำหนัก';
    if (sh.isEmpty) _heightError = 'กรุณาเลือกส่วนสูง';

    int? age;
    // support dd/MM/yyyy (birth date) or numeric age
    if (sa.contains('/')) {
      try {
        final parts = sa.split('/');
        if (parts.length >= 3) {
          final d = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final y = int.tryParse(parts[2]);
          if (d != null && m != null && y != null) {
            age = _ageFromDob(d, m, y);
          }
        }
      } catch (_) {
        age = null;
      }
    } else {
      age = int.tryParse(sa);
    }
    final weight = double.tryParse(sw);
    final height = int.tryParse(sh);

    if (sa.isNotEmpty && age == null) _ageError = 'ข้อมูลอายุไม่ถูกต้อง';
    if (sw.isNotEmpty && weight == null) {
      _weightError = 'ข้อมูลน้ำหนักไม่ถูกต้อง';
    }
    if (sh.isNotEmpty && height == null) {
      _heightError = 'ข้อมูลส่วนสูงไม่ถูกต้อง';
    }

    if (age != null) {
      if (age < 5 || age > 100) _ageError = 'อายุต้องอยู่ระหว่าง 5 - 100 ปี';
    }
    if (weight != null) {
      if (weight < 1.0 || weight > 200.0) {
        _weightError = 'น้ำหนักต้องอยู่ระหว่าง 1 - 200 กก.';
      }
    }
    // Gender-specific abnormal weight check: male weight < 50kg flagged
    try {
      final gval = sg;
      if (gval == 'ชาย' && weight != null && weight < 50.0) {
        _weightError = 'น้ำหนักต่ำกว่าปกติสำหรับเพศชาย';
      }
    } catch (_) {}
    if (height != null) {
      if (height < 1 || height > 250) {
        _heightError = 'ส่วนสูงต้องอยู่ระหว่าง 1 - 250 ซม.';
      }
    }

    if (age != null && height != null && age < 10 && height < 80) {
      _heightError = 'ส่วนสูงน้อยเกินไปสำหรับอายุ';
    }
    if (age != null && weight != null && age < 10 && weight > 50.0) {
      _weightError = 'น้ำหนักมากเกินไปสำหรับอายุ';
    }

    if (weight != null && height != null) {
      final double bmi = weight / ((height / 100) * (height / 100));
      if (bmi.isNaN || bmi < 6 || bmi > 60) {
        _bmiError =
            'ดัชนีมวลกาย (BMI) ผิดปกติ: ${bmi.isFinite ? bmi.toStringAsFixed(1) : 'ไม่ทราบ'}';
      }
    }

    setState(() {});

    return _genderError != null ||
        _ageError != null ||
        _weightError != null ||
        _heightError != null ||
        _bmiError != null;
  }

  bool _allRequiredFilled() {
    final sg = genderController.text.trim();
    String sa;
    if ((_selectedDay != null && _selectedMonthIndex != null && _selectedYearBE != null) && _selectedDay!.isNotEmpty) {
      sa = '${_selectedDay!.padLeft(2, '0')}/${_selectedMonthIndex?.toString().padLeft(2, '0') ?? ''}/${_selectedYearBE?.toString() ?? ''}';
    } else {
      sa = ageController.text.trim();
    }
    final sw = weightController.text.trim();
    final sh = heightController.text.trim();

    // Require chronic diseases and allergies text (or selected lists) as well
    final sd = diseasesController.text.trim();
    final sa2 = allergiesController.text.trim();

    final hasDiseases = sd.isNotEmpty || _selectedDiseases.isNotEmpty;
    final hasAllergies = sa2.isNotEmpty || _selectedAllergies.isNotEmpty;

    return sg.isNotEmpty && sa.isNotEmpty && sw.isNotEmpty && sh.isNotEmpty && hasDiseases && hasAllergies;
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6.0),
    child: Text(
      text,
      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
    ),
  );

  Future<void> _onNext() async {
    final auth = AuthService();
    // Block only if guest has already used their one-time submission
    if (auth.isGuestLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถแก้ไขข้อมูลได้อีก')),
      );
      return;
    }

    // Validate based on controllers (single source of truth for this page)
    final sg = genderController.text.trim();
    final sa = ageController.text.trim();
    final sw = weightController.text.trim();
    final sh = heightController.text.trim();

    // Run full validation and block if any inline errors exist
    if (_validateAll()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'พบค่าที่ผิดปกติ/ไม่ครบถ้วน โปรดตรวจสอบก่อนดำเนินการต่อ',
          ),
        ),
      );
      return;
    }
    debugPrint(
      'Before _onNext save: gender=$sg age=$sa weight=$sw height=$sh _hasPersonalInfo=$_hasPersonalInfo',
    );
    if (sg.isEmpty || sa.isEmpty || sw.isEmpty || sh.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกข้อมูลให้ครบถ้วน')),
      );
      return;
    }
    if (_saving) return;

    int? age;
    String? dobSql;
    // Prefer explicit DOB selection (day/month/year) for constructing dobSql and age
    if ((_selectedDay != null && _selectedMonthIndex != null && _selectedYearBE != null) && _selectedDay!.isNotEmpty) {
      final d = int.tryParse(_selectedDay!);
      final m = _selectedMonthIndex;
      final yBE = _selectedYearBE;
      if (d != null && m != null && yBE != null) {
        final gy = _toGregorianYear(yBE);
        age = DateTime.now().year - gy - ((DateTime.now().month < m || (DateTime.now().month == m && DateTime.now().day < d)) ? 1 : 0);
        dobSql = '${gy.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      }
    } else if (sa.contains('/')) {
      final parts = sa.split('/');
      if (parts.length >= 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          final gy = _toGregorianYear(y);
          age = DateTime.now().year - gy - ((DateTime.now().month < m || (DateTime.now().month == m && DateTime.now().day < d)) ? 1 : 0);
          dobSql = '${gy.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
        }
      }
    } else {
      age = int.tryParse(sa.split(' ').first);
    }
    final weight = double.tryParse(sw.split(' ').first);
    final height = int.tryParse(sh.split(' ').first);
    if (age == null || weight == null || height == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ข้อมูลไม่ถูกต้อง')));
      return;
    }

    // Validate diseases and allergies with backend fuzzy matcher
    List<String> finalDiseases = _selectedDiseases.isNotEmpty ? List.from(_selectedDiseases) : (diseasesController.text.trim().isNotEmpty ? diseasesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList() : []);
    List<String> finalAllergies = _selectedAllergies.isNotEmpty ? List.from(_selectedAllergies) : (allergiesController.text.trim().isNotEmpty ? allergiesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList() : []);

    Future<bool> maybeResolveAndConfirm(List<String> items, String typ) async {
      if (items.isEmpty) return true;
      // Treat explicit 'ไม่มี' entries as intentional "none" and skip validation/dialogs.
      final filtered = items.where((it) => it.trim().toLowerCase() != 'ไม่มี').toList();
      if (filtered.isEmpty) return true;
      final res = await _validateMedicalItems(filtered, typ);
      if (!mounted) return false;
      // Build messages for low-confidence matches
      final List<Widget> rows = [];
      bool anyLow = false;
      for (int i = 0; i < res.length; i++) {
        final r = res[i];
        final input = (r['input'] ?? '').toString();
        final matched = r['matched'];
        final score = (r['score'] ?? 0.0) is double ? r['score'] : (r['score'] ?? 0.0).toDouble();
        if (r['blocked'] == true) {
          // blocked due to profanity — show explicit error and prevent saving
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('ข้อความไม่เหมาะสม'),
              content: Text('ข้อความ "${r['input']}" มีคำหยาบคายหรือไม่เหมาะสม กรุณาแก้ไข'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ตกลง')),
              ],
            ),
          );
          return false;
        }

        if (matched != null && score >= 0.72) {
          rows.add(Text('"$input" → ตรงกับ "$matched" (ความมั่นใจ ${(score * 100).toStringAsFixed(0)}%)'));
        } else {
          anyLow = true;
          final suggestions = (r['suggestions'] as List?) ?? [];
          rows.add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('"$input" → ไม่พบการจับคู่แน่ชัด (คะแนน ${(score * 100).toStringAsFixed(0)}%)'),
            if (suggestions.isNotEmpty) Text('ข้อเสนอแนะ: ${suggestions.join(', ')}'),
          ]));
        }
      }

      if (!anyLow) {
        // all good
        // replace items with matched canonical when available
        for (final r in res) {
          if (r['matched'] != null) {
            final idx = items.indexWhere((it) => it.trim() == (r['input'] ?? '').toString());
            if (idx != -1) items[idx] = r['matched'];
          }
        }
        return true;
      }

      // show dialog to user listing low confidence items and suggestions
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('ยืนยันข้อมูล $typ'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('กลับไปแก้ไข')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ยืนยันและบันทึก')),
          ],
        ),
      );
      if (confirm == true) {
        // accept canonical matches where present
        for (final r in res) {
          if (r['matched'] != null) {
            final idx = items.indexWhere((it) => it.trim() == (r['input'] ?? '').toString());
            if (idx != -1) items[idx] = r['matched'];
          }
        }
        return true;
      }
      return false;
    }

    final okDiseases = await maybeResolveAndConfirm(finalDiseases, 'disease');
    if (!okDiseases) return;
    final okAllergies = await maybeResolveAndConfirm(finalAllergies, 'allergy');
    if (!okAllergies) return;
    if (!mounted) return;

    if (age < 5 ||
        age > 100 ||
        weight < 1.0 ||
        weight > 200.0 ||
        height < 1 ||
        height > 250) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาใส่ค่าภายในช่วงที่กำหนด')),
      );
      return;
    }

    final double bmi = weight / ((height / 100) * (height / 100));
    final List<String> reasons = [];
    if (age < 10 && height < 80) reasons.add('ส่วนสูงน้อยเกินไปสำหรับอายุ');
    if (age < 10 && weight > 50.0) reasons.add('น้ำหนักมากเกินไปสำหรับอายุ');
    if (bmi.isNaN || bmi < 6 || bmi > 60) {
      reasons.add(
        'ดัชนีมวลกาย (BMI) ผิดปกติ: ${bmi.isFinite ? bmi.toStringAsFixed(1) : 'ไม่ทราบ'}',
      );
    }

    if (reasons.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ข้อมูลอาจผิดปกติ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('พบค่าที่น่าจะผิดปกติ/เป็นไปได้ยาก โปรดตรวจสอบ:'),
              const SizedBox(height: 8),
              ...reasons.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text('- $r'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ระบบจะไม่อนุญาตให้ไปหน้าถัดไปจนกว่าจะแก้ไขข้อมูลให้ถูกต้อง',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('กลับไปแก้ไข'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    // schema ใหม่ส่งเป็น JSON array เสมอ (ไม่ใช่สตริง 'ไม่มี' แบบเดิม) —
    // Priority: controller text (latest UI) -> resolved list (canonicalized)
    List<String> payloadMedicalList(List<String> resolvedList, TextEditingController controller) {
      final fromController = _asStringList(controller.text);
      if (fromController.isNotEmpty) return fromController;
      return resolvedList;
    }

    final List<String> chronicDiseasesPayload = payloadMedicalList(finalDiseases, diseasesController);
    final List<String> foodAllergiesPayload = payloadMedicalList(finalAllergies, allergiesController);

    // Prepare merged data for background save
    Map<String, dynamic>? mergedUser;
    Map<String, dynamic>? mergedGuest;

    if (!auth.isLoggedIn) {
      if (!auth.isGuest) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushReplacement(
          MaterialPageRoute(builder: (_) => const RegisterLoginPage()),
        );
        return;
      }
      mergedGuest = <String, dynamic>{
        'gender': sg,
        'weight': sw,
        'height': sh,
        'activity_level': _selectedActivity?.trim(),
        'chronic_diseases': chronicDiseasesPayload,
        'food_allergies': foodAllergiesPayload,
        'name': nameController.text.trim(),
        'surname': surnameController.text.trim(),
      };
    } else {
      final existing = auth.user ?? {};
      mergedUser = Map<String, dynamic>.from(existing);
      mergedUser['name'] = nameController.text.trim();
      mergedUser['surname'] = surnameController.text.trim();
      mergedUser['gender'] = sg;
      mergedUser['weight'] = sw;
      mergedUser['height'] = sh;
      mergedUser['activity_level'] = _selectedActivity?.trim();
      mergedUser['chronic_diseases'] = chronicDiseasesPayload;
      mergedUser['food_allergies'] = foodAllergiesPayload;
    }

    if (!mounted) return;

    // Perform saves (blocking) so profile changes take effect immediately
    try {
      if (mergedUser != null) {
        // ponytail: เพศ/วันเกิดแก้ไขได้เสมอแล้ว จึงส่งค่าที่ผู้ใช้กรอกล่าสุดไปจริง ๆ (ไม่ทับกลับเป็นค่าเดิม)
        if (dobSql != null) mergedUser['date_of_birth'] = dobSql;
        // Ensure we send the latest UI values and never null — send 'ไม่มี' when empty.
        mergedUser['chronic_diseases'] = chronicDiseasesPayload;
        mergedUser['food_allergies'] = foodAllergiesPayload;
        // Perform API update directly so we can capture server-calculated fields
        try {
          final token = auth.token;
          final idVal = mergedUser['id'] ?? mergedUser['user_id'] ?? mergedUser['userid'] ?? auth.user?['id'];
          final intId = idVal == null ? null : int.tryParse(idVal.toString());
          if (token != null && intId != null) {
            final uri = Uri.parse('${getApiBase()}/user/$intId');
            final resp = await http.post(uri,
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token'
                },
                body: jsonEncode(mergedUser));
            if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
              final Map<String, dynamic> remote = jsonDecode(resp.body);
              // Persist server-returned full profile into AuthService
              await AuthService().saveUser(remote);
            } else {
              // คำนวณอายุจาก dobSql โดยตรงและเซฟลง mergedUser
              if (dobSql != null) {
                mergedUser['date_of_birth'] = dobSql;
                final birthDate = DateTime.tryParse(dobSql);
                final ageVal = birthDate != null ? _ageFromDob(birthDate.day, birthDate.month, birthDate.year) : null;
                mergedUser['age'] = ageVal?.toString() ??
                    (ageController.text.trim().isNotEmpty ? ageController.text.trim() : null);
              }

              // Fallback: merge locally then attempt remote sync via AuthService
              await (auth as dynamic).saveUser(mergedUser);
            }
          } else {
            // คำนวณอายุจาก dobSql โดยตรงและเซฟลง mergedUser เช่นกัน
            if (dobSql != null) {
              mergedUser['date_of_birth'] = dobSql;
              final birthDate = DateTime.tryParse(dobSql);
              final ageVal = birthDate != null ? _ageFromDob(birthDate.day, birthDate.month, birthDate.year) : null;
              mergedUser['age'] = ageVal?.toString() ??
                  (ageController.text.trim().isNotEmpty ? ageController.text.trim() : null);
            }

            await (auth as dynamic).saveUser(mergedUser);
          }
          try {
            await (auth as dynamic).markUserLocked();
          } catch (_) {}
        } catch (e) {
          // On any error, fallback to the existing merge/save behavior
          try {
            // คำนวณอายุจาก dobSql โดยตรงในบล็อก Catch
            if (dobSql != null) {
              mergedUser['date_of_birth'] = dobSql;
              final birthDate = DateTime.tryParse(dobSql);
              final ageVal = birthDate != null ? _ageFromDob(birthDate.day, birthDate.month, birthDate.year) : null;
              mergedUser['age'] = ageVal?.toString() ??
                  (ageController.text.trim().isNotEmpty ? ageController.text.trim() : null);
            }

            await (auth as dynamic).saveUser(mergedUser);
            await (auth as dynamic).markUserLocked();
          } catch (_) {}
        }
        if (dobSql != null && mounted) setState(() {});
      } else if (mergedGuest != null) {
        // For guests, only set DOB if it wasn't previously saved in guest personal
        final existingGuestDob = (auth.guestPersonal ?? <String, dynamic>{})['date_of_birth']?.toString() ?? '';
        if (dobSql != null && existingGuestDob.isEmpty) mergedGuest['date_of_birth'] = dobSql;
        // Ensure we send the latest UI values and never null — send 'ไม่มี' when empty.
        mergedGuest['chronic_diseases'] = chronicDiseasesPayload;
        mergedGuest['food_allergies'] = foodAllergiesPayload;
        await (auth as dynamic).saveGuestPersonal(mergedGuest);
        try {
          await (auth as dynamic).markGuestUsed();
          await (auth as dynamic).markGuestSelectionLocked();
        } catch (_) {}
        if (dobSql != null && mounted) setState(() {});
      }
    } catch (e) {
      if (kDebugMode) print('Save error before navigation: $e');
    }

    // After saving, prefer server-returned bmi/recommended_calories when available
    String bmiStr = '';
    String caloriesStr = '';
    try {
      final finalPersonal = auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {};
      if (finalPersonal.containsKey('bmi')) {
        final b = finalPersonal['bmi'];
        if (b != null) bmiStr = (b is num) ? b.toStringAsFixed(1) : b.toString();
      } else {
        bmiStr = (weight / ((height / 100) * (height / 100))).toStringAsFixed(1);
      }

      if (finalPersonal.containsKey('calories_goal')) {
        final rc = finalPersonal['calories_goal'];
        if (rc != null) {
          if (rc is num) {
            caloriesStr = '${rc.round()} kcal';
          } else {
            caloriesStr = rc.toString();
          }
        }
      } else {
        // fallback: canonical BMR/TDEE estimate (see utils/bmi_calculator.dart)
        try {
          final tdee = bmi_calc.calcTdee(
            weight: weight.toDouble(),
            height: height.toDouble(),
            age: age,
            gender: genderController.text.trim(),
            activity: _selectedActivity,
          );
          if (tdee != null) caloriesStr = '${tdee.round()} kcal';
        } catch (_) {
          caloriesStr = '';
        }
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ShowBMIAndSuggestedCalories(
        userId: auth.user != null ? (auth.user!['id']?.toString() ?? '') : '',
        bmi: bmiStr,
        calories: caloriesStr,
        activity: _selectedActivity ?? '',
        chronicDiseases: diseasesController.text.trim().isNotEmpty
            ? diseasesController.text.trim()
            : _joinForDisplay((auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {})['chronic_diseases']),
        foodAllergies: allergiesController.text.trim().isNotEmpty
            ? allergiesController.text.trim()
            : _joinForDisplay((auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {})['food_allergies']),
        consumedCalories: (() {
          try {
            final finalPersonal = auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {};
            final c = finalPersonal['consumed_calories'] ?? finalPersonal['consumed'] ?? finalPersonal['calories'];
            if (c != null) {
              if (c is num) return '${c.round()} kcal';
              return c.toString();
            }
          } catch (_) {}
          return '0';
        })(),
      )),
    );
  }

  void _goNextViewOnly() {
    // Guest already used their one-time submission — route through the same
    // BMI/goal steps using their previously-saved data instead of skipping
    // straight to menu selection.
    final auth = AuthService();
    final finalPersonal = auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {};
    String bmiStr = '';
    final b = finalPersonal['bmi'];
    if (b != null) bmiStr = (b is num) ? b.toStringAsFixed(1) : b.toString();
    String caloriesStr = '';
    final rc = finalPersonal['calories_goal'];
    if (rc != null) {
      caloriesStr = (rc is num) ? '${rc.round()} kcal' : rc.toString();
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ShowBMIAndSuggestedCalories(
          userId: auth.user != null ? (auth.user!['id']?.toString() ?? '') : '',
          bmi: bmiStr,
          calories: caloriesStr,
          activity: finalPersonal['activity_level']?.toString() ?? '',
          chronicDiseases: _joinForDisplay(finalPersonal['chronic_diseases']),
          foodAllergies: _joinForDisplay(finalPersonal['food_allergies']),
          consumedCalories: (() {
            final c = finalPersonal['consumed_calories'] ?? finalPersonal['consumed'] ?? finalPersonal['calories'];
            if (c == null) return '0';
            return (c is num) ? '${c.round()} kcal' : c.toString();
          })(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    // Only perform logout redirect when the session is neither a logged-in
    // user nor a Guest. This prevents spurious logout when storage marks a
    // Guest but in-memory state is still initializing.
    if (!auth.isGuest && !auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => RegisterLoginPage()),
          (route) => false,
        );
      });
      return const SizedBox.shrink();
    }
    if (!_authLoaded) {
      if (widget.isEditMode) {
        Future.microtask(() async {
          await _loadSavedUser();
          if (mounted) setState(() {});
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      } else {
        // New registration: ensure form is cleared and proceed immediately
        _clearFormForNewRegistration();
      }
    }

    // Recompute age dynamically from stored/selected DOB so age updates over time
    try {
      if ((_selectedDay != null && _selectedMonthIndex != null && _selectedYearBE != null) && _selectedDay!.isNotEmpty) {
        final d = int.tryParse(_selectedDay!);
        final m = _selectedMonthIndex;
        final yBE = _selectedYearBE;
        if (d != null && m != null && yBE != null) {
          final ageVal = _ageFromDob(d, m, yBE);
          _selectedAge = ageVal?.toString() ?? _selectedAge;
          ageController.text = _selectedAge ?? '';
        }
      }
    } catch (_) {}

    // ponytail: เพศและวันเกิดแก้ไขได้เสมอเหมือนน้ำหนัก/ส่วนสูง (ผู้ใช้จริงไม่ควรถูกล็อกหลังกรอกครั้งแรก)
    // guest ยังคงล็อกหลังใช้สิทธิ์ครั้งเดียวตามปกติของบัญชี guest
    final bool canEditDOB = auth.isGuest ? !auth.isGuestLocked : true;
    final bool canEditOtherFields = auth.isLoggedIn ? true : !auth.isGuestLocked;
    final bool canEditGender = auth.isGuest ? !auth.isGuestLocked : true;
    // Suppressed frequent debug prints to avoid flooding console during rebuilds

    final bool hasValidationErrors =
        _genderError != null ||
        _ageError != null ||
        _weightError != null ||
        _heightError != null ||
        _bmiError != null;

    String idText = '';
    if (auth.isLoggedIn && auth.user != null) {
      final uname =
          auth.user!['username'] ??
          auth.user!['name'] ??
          (auth.user!['id']?.toString() ?? '—');
      idText = uname;
    } else if (auth.isGuest) {
      idText = 'Guest';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8F6),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back, color: primaryGreen),
        ),
        title: Text('กรอกข้อมูลส่วนตัว', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
        actions: [
          if (idText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Center(
                child: Text(idText, style: TextStyle(color: Colors.black)),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('ชื่อ'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: nameController,
                      enabled: canEditOtherFields,
                      decoration: InputDecoration(
                        hintText: 'ระบุชื่อ',
                        filled: true,
                        fillColor: AppColors.line,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _label('นามสกุล'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: surnameController,
                      enabled: canEditOtherFields,
                      decoration: InputDecoration(
                        hintText: 'ระบุนามสกุล',
                        filled: true,
                        fillColor: AppColors.line,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _label('เพศ'),
                    const SizedBox(height: 6),
                    _dropdownField(
              'ระบุเพศ (ชาย - หญิง)',
              _selectedGender,
              _genderOptions,
              canEditGender
                  ? (v) => setState(() {
                      _selectedGender = v;
                      genderController.text = v ?? '';
                      _genderError = null;
                      _validateAll();
                    })
                  : null,
              enabled: canEditGender,
              error: _genderError,
            ),
            const SizedBox(height: 12),
            _label('วัน/เดือน/ปี (วันเกิด)'),
            Row(
              children: [
                Flexible(
                  flex: 1,
                  child: Builder(builder: (ctx) {
                    final days = _daysInMonthFromSelection();
                    final dayItems = List<String>.generate(days, (i) => '${i + 1}');
                    return _smallDropdown<String>(
                      'วัน',
                      _selectedDay,
                      dayItems,
                      canEditDOB
                          ? (v) => setState(() {
                              _selectedDay = v;
                              if (_selectedDay != null && _selectedMonthIndex != null && _selectedYearBE != null) {
                                final ageVal = _ageFromDob(
                                  int.tryParse(_selectedDay!) ?? 0,
                                  _selectedMonthIndex!,
                                  _selectedYearBE!,
                                );
                                if (ageVal != null) {
                                  _selectedAge = ageVal.toString();
                                  ageController.text = _selectedAge ?? '';
                                }
                              } else {
                                _selectedAge = null;
                                ageController.text = '';
                              }
                              _ageError = null;
                              _validateAll();
                            })
                          : null,
                      enabled: canEditDOB,
                      width: null,
                    );
                  }),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 2,
                  child: IgnorePointer(
                    ignoring: !canEditDOB,
                    child: Opacity(
                      opacity: canEditDOB ? 1.0 : 0.6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _selectedMonthIndex != null ? '$_selectedMonthIndex' : null,
                          hint: Text('เดือน', overflow: TextOverflow.ellipsis, maxLines: 1),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderSide: BorderSide.none),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            filled: true,
                            fillColor: AppColors.line,
                          ),
                          items: List.generate(12, (i) => '${i + 1}').map((val) {
                            final idx = int.tryParse(val)! - 1;
                            final label = _thaiMonthNames[idx];
                            return DropdownMenuItem<String>(
                              value: val,
                              child: Text(label, style: TextStyle(color: Colors.black)),
                            );
                          }).toList(),
                          onChanged: canEditDOB
                              ? (v) => setState(() {
                                  _selectedMonthIndex = v != null ? int.tryParse(v) : null;
                                  // if selected day is now out of range for this month, clear it
                                  final maxDays = _daysInMonthFromSelection(_selectedMonthIndex, _selectedYearBE);
                                  if (_selectedDay != null) {
                                    final sel = int.tryParse(_selectedDay!);
                                    if (sel != null && sel > maxDays) _selectedDay = null;
                                  }
                                  if (_selectedDay != null && _selectedMonthIndex != null && _selectedYearBE != null) {
                                    final ageVal = _ageFromDob(
                                      int.tryParse(_selectedDay ?? '0') ?? 0,
                                      _selectedMonthIndex!,
                                      _selectedYearBE!,
                                    );
                                    if (ageVal != null) {
                                      _selectedAge = ageVal.toString();
                                      ageController.text = _selectedAge ?? '';
                                    }
                                  } else {
                                    _selectedAge = null;
                                    ageController.text = '';
                                  }
                                  _ageError = null;
                                  _validateAll();
                                })
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Years: Thai BE, from now-5 down to now-100
                Flexible(
                  flex: 2,
                  child: Builder(builder: (ctx) {
                    final now = DateTime.now();
                    final int currentBE = now.year + 543;
                    // Include current BE year and go back 95 years (total 96 entries)
                    final years = List<String>.generate(96, (i) => '${currentBE - i}');
                    return _smallDropdown<String>(
                      'พ.ศ.',
                      _selectedYearBE != null ? '$_selectedYearBE' : null,
                      years,
                      canEditDOB
                          ? (v) => setState(() {
                              _selectedYearBE = v != null ? int.tryParse(v) : null;
                              // if selected day is now out of range for this month/year (leap-year effect), clear it
                              final maxDays = _daysInMonthFromSelection(_selectedMonthIndex, _selectedYearBE);
                              if (_selectedDay != null) {
                                final sel = int.tryParse(_selectedDay!);
                                if (sel != null && sel > maxDays) _selectedDay = null;
                              }
                              if (_selectedDay != null && _selectedMonthIndex != null && _selectedYearBE != null) {
                                final ageVal = _ageFromDob(
                                  int.tryParse(_selectedDay ?? '0') ?? 0,
                                  _selectedMonthIndex!,
                                  _selectedYearBE!,
                                );
                                if (ageVal != null) {
                                  _selectedAge = ageVal.toString();
                                  ageController.text = _selectedAge ?? '';
                                }
                              } else {
                                _selectedAge = null;
                                ageController.text = '';
                              }
                              _ageError = null;
                              _validateAll();
                            })
                          : null,
                      enabled: canEditDOB,
                      width: null,
                    );
                  }),
                ),
              ],
            ),
            if (_ageError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(_ageError!, style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 12),
            _label('อายุ'),
            const SizedBox(height: 6),
            Builder(builder: (ctx) {
              final bool dobSet = (_selectedDay != null && _selectedMonthIndex != null && _selectedYearBE != null) && _selectedDay!.isNotEmpty;
              // Age must be computed from DOB; user cannot enter age manually.
              return TextFormField(
                controller: ageController,
                enabled: false,
                decoration: InputDecoration(
                  hintText: dobSet ? (_selectedAge ?? '') : 'โปรดเลือก วัน/เดือน/ปีเกิด ก่อน',
                  filled: true,
                  fillColor: AppColors.line,
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  errorText: _ageError,
                ),
              );
            }),
            const SizedBox(height: 12),
            _label('น้ำหนัก'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: weightController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    enabled: canEditOtherFields,
                    decoration: InputDecoration(
                      hintText: 'ระบุน้ำหนัก เช่น 55.5 (1 - 200)',
                      filled: true,
                      fillColor: AppColors.line,
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      errorText: _weightError,
                    ),
                    onChanged: (v) {
                      _selectedWeight = v;
                      _weightError = null;
                      _validateAll();
                    },
                  ),
                ),
                SizedBox(width: 8),
                Column(
                  children: [
                    SizedBox(
                      width: 36,
                      height: 32,
                      child: IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        onPressed: canEditOtherFields ? () {
                          double current = double.tryParse(weightController.text) ?? 0.0;
                          if (current < 200) {
                            final newVal = (current + 0.1);
                            weightController.text = newVal.toStringAsFixed(1);
                            _selectedWeight = weightController.text;
                            _validateAll();
                          }
                        } : null,
                        icon: Icon(Icons.add),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 32,
                      child: IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        onPressed: canEditOtherFields ? () {
                          double current = double.tryParse(weightController.text) ?? 0.0;
                          if (current > 1.0) {
                            final newVal = (current - 0.1);
                            weightController.text = newVal.toStringAsFixed(1);
                            _selectedWeight = weightController.text;
                            _validateAll();
                          }
                        } : null,
                        icon: Icon(Icons.remove),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _label('ส่วนสูง'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: heightController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    enabled: canEditOtherFields,
                    decoration: InputDecoration(
                      hintText: 'ระบุส่วนสูง เช่น 170 (1 - 250)',
                      filled: true,
                      fillColor: AppColors.line,
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      errorText: _heightError,
                    ),
                    onChanged: (v) {
                      _selectedHeight = v;
                      _heightError = null;
                      _validateAll();
                    },
                  ),
                ),
                SizedBox(width: 8),
                Column(
                  children: [
                    SizedBox(
                      width: 36,
                      height: 32,
                      child: IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        onPressed: canEditOtherFields ? () {
                          double current = double.tryParse(heightController.text) ?? 0.0;
                          if (current < 250) {
                            final newVal = (current + 1);
                            heightController.text = newVal.toStringAsFixed(0);
                            _selectedHeight = heightController.text;
                            _validateAll();
                          }
                        } : null,
                        icon: Icon(Icons.add),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 32,
                      child: IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        onPressed: canEditOtherFields ? () {
                          double current = double.tryParse(heightController.text) ?? 0.0;
                          if (current > 1.0) {
                            final newVal = (current - 1);
                            heightController.text = newVal.toStringAsFixed(0);
                            _selectedHeight = heightController.text;
                            _validateAll();
                          }
                        } : null,
                        icon: Icon(Icons.remove),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _label('โรคประจำตัว'),
            TextFormField(
              controller: diseasesController,
              enabled: canEditOtherFields,
              decoration: InputDecoration(
                hintText: 'พิมพ์ชื่อโรค คั่นด้วยคอมม่า เช่น เบาหวาน, ความดัน',
                filled: true,
                fillColor: AppColors.line,
                border: OutlineInputBorder(borderSide: BorderSide.none),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
              onChanged: (v) {
                _selectedDiseases.clear();
                if (v.trim().isNotEmpty) {
                  _selectedDiseases.addAll(v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
                }
                _updateDiseaseSuggestions(v);
                _validateAll();
                setState(() {});
              },
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Text(
                'หมายเหตุ: หากไม่มีโรคประจำตัว กรุณาระบุว่า "ไม่มี" และหากมีโรคแต่ไม่พบในรายการ ให้ระบุว่า "อื่นๆ"',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
            if (_diseaseSuggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _diseaseSuggestions.map((s) => InkWell(
                        onTap: () {
                          final newText = _replaceLastToken(diseasesController.text, s);
                          diseasesController.text = newText;
                          _selectedDiseases.clear();
                          _selectedDiseases.addAll(newText.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty));
                          _updateDiseaseSuggestions(newText);
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Text(s, style: TextStyle(color: Colors.black)),
                        ),
                      )).toList(),
                ),
              ),
            const SizedBox(height: 12),
            _label('แพ้อาหาร'),
            TextFormField(
              controller: allergiesController,
              enabled: canEditOtherFields,
              decoration: InputDecoration(
                hintText: 'พิมพ์ชื่ออาหารที่แพ้ คั่นด้วยคอมม่า เช่น ถั่วลิสง, นมวัว',
                filled: true,
                fillColor: AppColors.line,
                border: OutlineInputBorder(borderSide: BorderSide.none),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
              onChanged: (v) {
                _selectedAllergies.clear();
                if (v.trim().isNotEmpty) {
                  _selectedAllergies.addAll(v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
                }
                _updateAllergySuggestions(v);
                _validateAll();
                setState(() {});
              },
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Text(
                'หมายเหตุ: หากไม่มีการแพ้อาหาร กรุณาระบุว่า "ไม่มี" และหากมีแต่ไม่พบในรายการ ให้ระบุว่า "อื่นๆ"',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
            if (_allergySuggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _allergySuggestions.map((s) => InkWell(
                        onTap: () {
                          final newText = _replaceLastToken(allergiesController.text, s);
                          allergiesController.text = newText;
                          _selectedAllergies.clear();
                          _selectedAllergies.addAll(newText.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty));
                          _updateAllergySuggestions(newText);
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Text(s, style: TextStyle(color: Colors.black)),
                        ),
                      )).toList(),
                ),
              ),
            const SizedBox(height: 12),
            _label('เลือกกิจกรรม'),
            const SizedBox(height: 6),
            _dropdownField(
              'เลือกกิจกรรม',
              _selectedActivity,
              _activityOptions,
              canEditOtherFields
                  ? (v) => setState(() {
                      _selectedActivity = v;
                      _validateAll();
                    })
                  : null,
              enabled: canEditOtherFields,
            ),
                    if (_bmiError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(_bmiError!, style: TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 12),
                  ],
                  ),
                ),
              ),
            ),
            if (auth.isGuestLocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  'ไม่สามารถกรอกข้อมูลได้อีก',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : auth.isGuestLocked
                        ? _goNextViewOnly
                        : (hasValidationErrors || !_allRequiredFilled() ? null : _onNext),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.disabled)) return AppColors.inkSoft;
                    return primaryGreen;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.disabled)) return Colors.white70;
                    return Colors.white;
                  }),
                  shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                  elevation: WidgetStateProperty.all(0),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'หน้าถัดไป',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    try {
      AuthService().removeListener(_handleAuthChange);
    } catch (_) {}
    nameController.dispose();
    surnameController.dispose();
    genderController.dispose();
    ageController.dispose();
    weightController.dispose();
    heightController.dispose();
    diseasesController.dispose();
    allergiesController.dispose();
    super.dispose();
  }
}