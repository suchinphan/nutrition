import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../services/api_client.dart';
import '../services/app_config.dart';
import '../services/auth_service.dart';
import '../utils/bmi_calculator.dart' as bmi_calc;
import '../services/meal_selection_service_factory.dart';
import 'meal_selection_page.dart';

class ChooseAHealthGoal extends StatefulWidget {
	final String userId;

	const ChooseAHealthGoal({super.key, this.userId = ''});

	@override
	State<ChooseAHealthGoal> createState() => _ChooseAHealthGoalState();
}

class _ChooseAHealthGoalState extends State<ChooseAHealthGoal> {
	static const Color _accentGreen = AppColors.leaf;
	// เป้าหมายน้ำหนัก — แยกจาก preference หมวดอาหารด้านล่าง คุมแคลอรีเป้าหมายต่อวันโดยตรง
	String? _selectedWeightGoal; // 'ลดน้ำหนัก' / 'รักษาน้ำหนัก' / 'เพิ่มน้ำหนัก' -> maps to weight_goal
	static const List<String> _weightGoalOptions = ['ลดน้ำหนัก', 'รักษาน้ำหนัก', 'เพิ่มน้ำหนัก'];

	// New state variables per DB columns
	String? _selectedFoodGroup; // mirrors the "primary" food pick, kept for backward compatibility
	String? _selectedFoodGoal; // mirrors the "primary" food pick, kept for backward compatibility
	String? _selectedDrinkGoal; // maps to health_goal_drink (fixed label when drink chosen)
	String? _selectedDrinkType; // maps to health_goal_drink_types

	// Independent selection per food topic (1-3) so picking one doesn't
	// clear the others — each topic behaves like the drink topic already does.
	String? _selectedProteinGoal; // maps to health_goal_protein
	String? _selectedVegGoal; // maps to health_goal_veg
	String? _selectedCarbGoal; // maps to health_goal_carb

	String? _categoryKeyForGroup(String group) {
		if (group.contains('โปรตีน')) return 'protein';
		if (group.contains('ผัก')) return 'veg';
		if (group.contains('คาร์โบไฮเดรต')) return 'carb';
		return null;
	}

	String? _foodGoalFor(String? categoryKey) {
		switch (categoryKey) {
			case 'protein': return _selectedProteinGoal;
			case 'veg': return _selectedVegGoal;
			case 'carb': return _selectedCarbGoal;
		}
		return null;
	}

	void _setFoodGoalFor(String categoryKey, String value) {
		switch (categoryKey) {
			case 'protein': _selectedProteinGoal = value; break;
			case 'veg': _selectedVegGoal = value; break;
			case 'carb': _selectedCarbGoal = value; break;
		}
	}

	// Mirror one representative (group, goal) pair into the legacy single
	// fields so pages that still read health_goal/health_goal_group keep working.
	void _syncPrimaryFoodGoal() {
		if (_selectedProteinGoal != null) {
			_selectedFoodGroup = 'เมนูโปรตีน';
			_selectedFoodGoal = _selectedProteinGoal;
		} else if (_selectedVegGoal != null) {
			_selectedFoodGroup = 'เมนูผักและผลไม้';
			_selectedFoodGoal = _selectedVegGoal;
		} else if (_selectedCarbGoal != null) {
			_selectedFoodGroup = 'เมนูคาร์โบไฮเดรต';
			_selectedFoodGoal = _selectedCarbGoal;
		} else {
			_selectedFoodGroup = null;
			_selectedFoodGoal = null;
		}
	}

	bool get _allFoodGoalsSelected =>
		_selectedProteinGoal != null && _selectedVegGoal != null && _selectedCarbGoal != null;
	bool _saving = false;

	// Explicit locked flag used by the UI (set from server when refreshing)
	bool locked = false;

	// If backend available we'll load categories grouped by food-type.
	List<Map<String, dynamic>> _groupedGoals = [];
	final List<Map<String, String>> _fallbackGoalOptions = [
		{'id': 'อาหารครบ5หมู่', 'label': 'อาหารครบ5หมู่'},
		{'id': 'อาหารลดน้ำหนัก', 'label': 'อาหารลดน้ำหนัก'},
		{'id': 'การสร้างกล้ามเนื้อ', 'label': 'การสร้างกล้ามเนื้อ'},
	];

	bool _loadingGoals = true;

	Map<String, String> _computeBmiAndCalories(Map<String, dynamic> personal) {
		try {
			final wStr = personal['weight']?.toString() ?? '';
			final hStr = personal['height']?.toString() ?? '';
			final ageStr = personal['age']?.toString() ?? '';
			final gender = personal['gender']?.toString() ?? '';
			final weight = double.tryParse(wStr) ?? double.nan;
			final height = double.tryParse(hStr) ?? double.nan;
			final age = int.tryParse(ageStr) ?? 0;
			String bmiS = '';
			String calS = '';
			String status = '';
			String warning = '';
			if (weight.isFinite && height.isFinite && height > 0) {
				final bmi = bmi_calc.calcBmi(weight, height);
				if (bmi != null) bmiS = bmi.toStringAsFixed(1);
				final activityLabel = personal['activity']?.toString();
				final effectiveAge = age > 0 ? age : 30;
				final bmr = bmi_calc.calcBmr(weight: weight, height: height, age: effectiveAge, gender: gender);
				final tdee = bmi_calc.calcTdee(
					weight: weight,
					height: height,
					age: effectiveAge,
					gender: gender,
					activity: activityLabel,
				) ?? double.nan;
				// Parse chronic diseases to apply small, evidence-based adjustments
				final cdRaw = (personal['chronic_diseases'] ?? '').toString().toLowerCase();
				final List<String> cds = cdRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
				double adjustments = 0.0; // fractional (e.g., -0.05 == -5%)
				for (final d in cds) {
					if (d.contains('เบาหวาน') || d.contains('diabetes')) adjustments -= 0.05; // modest reduction
					if (d.contains('ความดัน') || d.contains('hypertension')) adjustments -= 0.03;
					if (d.contains('โรคไต') || d.contains('ไต')) adjustments -= 0.05;
					if (d.contains('มะเร็ง')) adjustments += 0.10; // some cancer states increase needs
					if (d.contains('หืด')) adjustments -= 0.02;
				}
				// Food allergies are noted but generally don't change caloric need; include for rationale only
				final allergiesRaw = (personal['food_allergies'] ?? '').toString();
				// Compute recommended calories
				double rec = double.nan;
				if (tdee.isFinite) {
					rec = tdee * (1.0 + adjustments);
					final goalAdjusted = bmi_calc.applyWeightGoal(rec, gender, _selectedWeightGoal);
					if (goalAdjusted != null) rec = goalAdjusted;
					calS = '${rec.round()} kcal';
				}
				status = bmi_calc.bmiStatus(bmi) ?? '';
				// Gender-specific abnormal checks
				if (gender == 'ชาย' && weight.isFinite && weight < 50.0) {
					warning = 'น้ำหนักต่ำกว่าปกติสำหรับเพศชาย';
				}
				// Provide breakdown rationale in a compact string
				final rationale = 'BMR=${bmr?.round() ?? '-'} kcal, activity=${activityLabel?.isNotEmpty == true ? activityLabel : 'ไม่ระบุ'}, adj_pct=${(adjustments*100).round()}%';
				return {
					'bmi': bmiS,
					'cal': calS,
					'status': status,
					'warning': warning,
					'recommended_cal': calS,
					'recommended_cal_value': rec.isFinite ? rec.round().toString() : '',
					'cal_rationale': rationale,
					'allergies': allergiesRaw
				};
			}
			return {'bmi': '', 'cal': '', 'status': '', 'warning': '', 'recommended_cal': '', 'recommended_cal_value': '', 'cal_rationale': '', 'allergies': ''};
		} catch (_) {
			return {'bmi': '', 'cal': '', 'status': '', 'warning': ''};
		}
	}

	Future<void> _showSummaryAndConfirm() async {
		final auth = AuthService();
		final personal = auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {};
		final names = auth.user != null ? (auth.user!['username'] ?? auth.user!['name']) : (auth.isGuest ? 'Guest' : '');
		final map = _computeBmiAndCalories(personal);
 		final bmi = map['bmi'] ?? '';
 		final cal = map['cal'] ?? '';
 		final status = map['status'] ?? '';
 		final warning = map['warning'] ?? '';
 		final recommended = map['recommended_cal'] ?? '';
 		final allergies = map['allergies'] ?? '';

		final confirmed = await showDialog<bool>(
			context: context,
			builder: (ctx) => AlertDialog(
				title: const Text('ยืนยันข้อมูล'),
				content: Column(
					mainAxisSize: MainAxisSize.min,
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						if (names != null && names.toString().isNotEmpty) Text('ผู้ใช้งาน: ${names.toString()}'),
						if (bmi.isNotEmpty) Text('BMI: $bmi'),
						if (status.isNotEmpty) Text('สถานะ BMI: $status'),
						if (recommended.isNotEmpty || cal.isNotEmpty)
							Text('แคลอรีที่แนะนำ: ${recommended.isNotEmpty ? recommended : cal}'),
						if (allergies.isNotEmpty) Padding(padding: const EdgeInsets.only(top:6.0), child: Text('แพ้อาหาร: $allergies', style: const TextStyle(fontSize: 13, color: Colors.black54))),
						if (warning.isNotEmpty) Padding(padding: const EdgeInsets.only(top:6.0), child: Text(warning, style: const TextStyle(color: Colors.red))),
						const SizedBox(height: 8),
						Text('เป้าหมายที่เลือก: ${_selectedGoalLabel()}'),
					],
				),
				actions: [
					TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('แก้ไข')),
					TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ยืนยันและบันทึก')),
				],
			),
		);
		if (confirmed == true) {
			// Build explicit target strings: empty string means "clear value"
			final String targetFoodGoal = _selectedFoodGoal ?? '';
			final String targetFoodGroup = _selectedFoodGroup ?? '';
			final String targetDrinkGoal = _selectedDrinkGoal ?? '';
			final String targetDrinkType = _selectedDrinkType ?? '';
			final String targetProteinGoal = _selectedProteinGoal ?? '';
			final String targetVegGoal = _selectedVegGoal ?? '';
			final String targetCarbGoal = _selectedCarbGoal ?? '';

			// Show a compact confirmation (already confirmed earlier) and then send
			setState(() => _saving = true);
			try {
				final api = ApiClient(getApiBase());
				final auth = AuthService();
				int? uid;
				try {
					uid = auth.user != null ? int.tryParse((auth.user!['id'] ?? '').toString()) : null;
				} catch (_) {
					uid = null;
				}
				if (uid == null) {
					final uidFromWidget = widget.userId;
					if (uidFromWidget.isNotEmpty) uid = int.tryParse(uidFromWidget);
				}

				final payload = {
					'health_goal': targetFoodGoal,
					'health_goal_group': targetFoodGroup,
					'health_goal_drink': targetDrinkGoal,
					'health_goal_drink_types': targetDrinkType,
					'health_goal_protein': targetProteinGoal,
					'health_goal_veg': targetVegGoal,
					'health_goal_carb': targetCarbGoal,
					'weight_goal': _selectedWeightGoal ?? '',
				};

				if (kDebugMode) print('ChooseAHealthGoal: sending payload=$payload');

				if (uid == null) {
					// Offline/guest path: persist locally and mark locked as before
					try {
						final existing = auth.tempSelections ?? auth.guestSelections ?? {};
						final merged = Map<String, dynamic>.from(existing);
						merged['health_goal'] = targetFoodGoal;
						merged['health_goal_group'] = targetFoodGroup;
						merged['health_goal_drink'] = targetDrinkGoal;
						merged['health_goal_drink_types'] = targetDrinkType;
						merged['health_goal_protein'] = targetProteinGoal;
						merged['health_goal_veg'] = targetVegGoal;
						merged['health_goal_carb'] = targetCarbGoal;
						merged['weight_goal'] = _selectedWeightGoal ?? '';
						try {
							auth.setTempSelections(merged);
						} catch (_) {}
						try { await auth.saveGuestSelections(merged); } catch (_) {}
						try { await auth.markGuestUsed(); } catch (_) {}
						if (mounted) {
						  setState(() {
							_selectedFoodGoal = targetFoodGoal.isNotEmpty ? targetFoodGoal : null;
							_selectedFoodGroup = targetFoodGroup.isNotEmpty ? targetFoodGroup : null;
							_selectedDrinkGoal = targetDrinkGoal.isNotEmpty ? targetDrinkGoal : null;
							_selectedDrinkType = targetDrinkType.isNotEmpty ? targetDrinkType : null;
							_selectedProteinGoal = targetProteinGoal.isNotEmpty ? targetProteinGoal : null;
							_selectedVegGoal = targetVegGoal.isNotEmpty ? targetVegGoal : null;
							_selectedCarbGoal = targetCarbGoal.isNotEmpty ? targetCarbGoal : null;
						});
						ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกข้อมูลสำเร็จ (ออฟไลน์) — เป้าหมาย: ${targetFoodGoal.isNotEmpty ? targetFoodGoal : 'ล้างค่า'}'), backgroundColor: _accentGreen));
						}
						setState(() => _saving = false);
						// Continue to meal/duration selection after successful offline save
						try {
							if (mounted) {
								Navigator.of(context).pushReplacement(MaterialPageRoute(
									builder: (_) => MealSelectionPage(
										service: createMealSelectionService(),
									),
								));
							}
						} catch (_) {}
						return;
					} catch (_) {}
				}

				// Ensure token loaded by AuthService
				try { await (auth as dynamic).loadToken(); } catch (_) {}

				final resp = await api.post('/user/$uid', body: payload);
				if (!mounted) return;
				if (resp.statusCode >= 200 && resp.statusCode < 300) {
					ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกเป้าหมายสุขภาพสำเร็จ')));
					try { await (AuthService() as dynamic).loadToken(force: true); } catch (_) {}
					if (mounted) {
						await _loadExistingGoalFromServer();
						setState(() {});
					}
					// After successful save, continue to meal/duration selection
					try {
						if (mounted) {
							Navigator.of(context).pushReplacement(MaterialPageRoute(
								builder: (_) => MealSelectionPage(
									service: createMealSelectionService(),
								),
							));
						}
					} catch (_) {}
				} else {
					final msg = resp.body.isNotEmpty == true ? resp.body : 'status ${resp.statusCode}';
					ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $msg')));
				}
			} catch (e) {
				if (kDebugMode) print('Error saving health goal (direct): $e');
				if (mounted) {
					ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
				}
			} finally {
				if (mounted) setState(() => _saving = false);
			}
		}
	}

	@override
  	void initState() {
    	super.initState();

		// โหลดสถานะ goal/lock ล่าสุดจาก server
		_loadExistingGoalFromServer();

		_loadGoalGroups(); // corrected: call existing method
    	_restoreSelectionFromAuth();

    	try {
      		AuthService().addListener(_authListener);
    	} catch (_) {}
  }

	@override
	void didChangeDependencies() {
		super.didChangeDependencies();
		// Called when the widget is inserted into the widget tree or when
		// dependencies change (including when returning to this route).
		// Ensure we always restore the latest persisted/remote health-goal
		// so the selected radio is visible even when the page is locked.
		_restoreSelectionFromAuth();
		// Always check server state when dependencies change (e.g., returning to this route)
		_loadExistingGoalFromServer();
	}

// Explicit loader that queries the backend for the user's profile including
// `health_goal_locked` and updates local UI state accordingly.
Future<void> _loadExistingGoalFromServer() async {
	// Determine the current user ID from either the widget or AuthService.
	final auth = AuthService();
	String? userId = widget.userId;
	if (userId.toString().trim().isEmpty || userId == 'User ID') {
		userId = auth.user != null ? auth.user!['id']?.toString() : null;
	}
	if (userId == null || userId.toString().trim().isEmpty) {
		if (kDebugMode) print('loadExistingGoalFromServer: no valid userId available, skipping server call');
		return;
	}
	try {
		final api = ApiClient(getApiBase());
		final resp = await api.get('/user/$userId');
		if (resp.statusCode == 200) {
			final data = jsonDecode(resp.body) as Map<String, dynamic>;
			final dynamic hv = data['health_goal'];
			final dynamic hg = data['health_goal_group'];
			final dynamic hd = data['health_goal_drink'];
			final dynamic hdt = data['health_goal_drink_types'];
			final dynamic hgp = data['health_goal_protein'];
			final dynamic hgv = data['health_goal_veg'];
			final dynamic hgc = data['health_goal_carb'];
			final dynamic wg = data['weight_goal'];
			final bool serverLocked = (data['health_goal_locked'] ?? false) == true;

			if (mounted) {
				setState(() {
					// Map server values to new state variables
					_selectedWeightGoal = wg != null && wg.toString().isNotEmpty ? wg.toString() : null;
					_selectedFoodGoal = hv != null && hv.toString().isNotEmpty ? hv.toString() : null;
					_selectedFoodGroup = hg != null && hg.toString().isNotEmpty ? hg.toString() : null;
					_selectedDrinkGoal = hd != null && hd.toString().isNotEmpty ? hd.toString() : null;
					_selectedDrinkType = hdt != null && hdt.toString().isNotEmpty ? hdt.toString() : null;
					_selectedProteinGoal = hgp != null && hgp.toString().isNotEmpty ? hgp.toString() : null;
					_selectedVegGoal = hgv != null && hgv.toString().isNotEmpty ? hgv.toString() : null;
					_selectedCarbGoal = hgc != null && hgc.toString().isNotEmpty ? hgc.toString() : null;

					// If server explicitly reports both food and drink null, unlock
					if (hv == null && hd == null) {
						locked = false;
					} else {
						locked = serverLocked;
					}
				});
			}
		}
	} catch (e) {
		if (kDebugMode) print('loadExistingGoalFromServer error: $e');
	}
}

	void _authListener() {
		if (!mounted) return;
		// When auth state changes (profile/tempSelections/guestSelections),
		// refresh the latest user from server (if available) and then
		// restore the selected health goal so the radio shows the saved
		// choice even when the page is locked. Do not clear `_selectedGoal`.
		Future.microtask(() async {
			// Avoid forcing a profile reload here: calling `loadToken(force:true)`
			// triggers `notifyListeners()` which would call this listener again
			// and cause a loop. Instead, simply restore selection from the
			// already-updated AuthService state and refresh the UI.
			try {
				_restoreSelectionFromAuth();
				if (mounted) setState(() {});
			} catch (_) {
				if (mounted) setState(() {});
			}
		});
	}

	void _restoreSelectionFromAuth() {
		try {
			final auth = AuthService();
			// Prefer permanent user value, then tempSelections, then guestSelections
			String? weightGoal = auth.user?['weight_goal']?.toString();
			if (weightGoal == null || weightGoal.isEmpty) {
				weightGoal = auth.tempSelections?['weight_goal']?.toString();
			}
			if (weightGoal == null || weightGoal.isEmpty) {
				weightGoal = auth.guestSelections?['weight_goal']?.toString();
			}
			if (weightGoal != null && weightGoal.isNotEmpty) _selectedWeightGoal = weightGoal;
			String? label;
			String? group;
			String? drinkGoal;
			String? drinkType;
			String? proteinGoal;
			String? vegGoal;
			String? carbGoal;
			if (auth.user != null) {
				String? hv = auth.user!['health_goal']?.toString();
				String? hg = auth.user!['health_goal_group']?.toString();
				String? hd = auth.user!['health_goal_drink']?.toString();
				String? hdt = auth.user!['health_goal_drink_types']?.toString();
				String? hgp = auth.user!['health_goal_protein']?.toString();
				String? hgv = auth.user!['health_goal_veg']?.toString();
				String? hgc = auth.user!['health_goal_carb']?.toString();
				if (hv != null) hv = hv.trim();
				if (hg != null) hg = hg.trim();
				if (hd != null) hd = hd.trim();
				if (hdt != null) hdt = hdt.trim();
				if (hgp != null) hgp = hgp.trim();
				if (hgv != null) hgv = hgv.trim();
				if (hgc != null) hgc = hgc.trim();
				if (hv != null && (hv.isNotEmpty && hv.toLowerCase() != 'null')) label = hv;
				if (hg != null && (hg.isNotEmpty && hg.toLowerCase() != 'null')) group = hg;
				if (hd != null && (hd.isNotEmpty && hd.toLowerCase() != 'null')) drinkGoal = hd;
				if (hdt != null && (hdt.isNotEmpty && hdt.toLowerCase() != 'null')) drinkType = hdt;
				if (hgp != null && (hgp.isNotEmpty && hgp.toLowerCase() != 'null')) proteinGoal = hgp;
				if (hgv != null && (hgv.isNotEmpty && hgv.toLowerCase() != 'null')) vegGoal = hgv;
				if (hgc != null && (hgc.isNotEmpty && hgc.toLowerCase() != 'null')) carbGoal = hgc;
			}
			// If tempSelections explicitly contains drink keys, prefer them (override user)
			if (auth.tempSelections != null) {
				final thd = auth.tempSelections!['health_goal_drink'];
				final thdt = auth.tempSelections!['health_goal_drink_types'];
				if (thd != null && thd.toString().isNotEmpty) drinkGoal = thd.toString();
				if (thdt != null && thdt.toString().isNotEmpty) drinkType = thdt.toString();
			}
			if (label == null && auth.tempSelections != null) {
				final tv = auth.tempSelections!['health_goal'];
				final tg = auth.tempSelections!['health_goal_group'];
				final thd = auth.tempSelections!['health_goal_drink'];
				final thdt = auth.tempSelections!['health_goal_drink_types'];
				if (tv != null && tv.toString().isNotEmpty) label = tv.toString();
				if (tg != null && tg.toString().isNotEmpty) group = tg.toString();
				if ((drinkGoal == null || drinkGoal.isEmpty) && thd != null && thd.toString().isNotEmpty) drinkGoal = thd.toString();
				if ((drinkType == null || drinkType.isEmpty) && thdt != null && thdt.toString().isNotEmpty) drinkType = thdt.toString();
			}
			if (auth.tempSelections != null) {
				final tgp = auth.tempSelections!['health_goal_protein'];
				final tgv = auth.tempSelections!['health_goal_veg'];
				final tgc = auth.tempSelections!['health_goal_carb'];
				if (tgp != null && tgp.toString().isNotEmpty) proteinGoal = tgp.toString();
				if (tgv != null && tgv.toString().isNotEmpty) vegGoal = tgv.toString();
				if (tgc != null && tgc.toString().isNotEmpty) carbGoal = tgc.toString();
			}
			if (label == null && auth.guestSelections != null) {
				final gv = auth.guestSelections!['health_goal'];
				final gg = auth.guestSelections!['health_goal_group'];
				final gd = auth.guestSelections!['health_goal_drink'];
				final gdt = auth.guestSelections!['health_goal_drink_types'];
				if (gv != null && gv.toString().isNotEmpty) label = gv.toString();
				if (gg != null && gg.toString().isNotEmpty) group = gg.toString();
				if (gd != null && gd.toString().isNotEmpty) drinkGoal = gd.toString();
				if (gdt != null && gdt.toString().isNotEmpty) drinkType = gdt.toString();
			}
			if (auth.guestSelections != null) {
				final ggp = auth.guestSelections!['health_goal_protein'];
				final ggv = auth.guestSelections!['health_goal_veg'];
				final ggc = auth.guestSelections!['health_goal_carb'];
				if (ggp != null && ggp.toString().isNotEmpty) proteinGoal = ggp.toString();
				if (ggv != null && ggv.toString().isNotEmpty) vegGoal = ggv.toString();
				if (ggc != null && ggc.toString().isNotEmpty) carbGoal = ggc.toString();
			}
			if (label != null || drinkType != null || proteinGoal != null || vegGoal != null || carbGoal != null) {
				if (mounted) {
					setState(() {
						_selectedFoodGoal = label;
						_selectedFoodGroup = group;
						_selectedDrinkGoal = drinkGoal;
						_selectedDrinkType = drinkType;
						_selectedProteinGoal = proteinGoal;
						_selectedVegGoal = vegGoal;
						_selectedCarbGoal = carbGoal;
					});
				}
			}
		} catch (_) {}
	}

	Future<void> _loadGoalGroups() async {
		setState(() => _loadingGoals = true);
		try {
			// Use static grouped goals per requirements
			_groupedGoals = [
				{
					'group': 'เมนูโปรตีน',
					'items': [
						{'id': 'โปรตีนครบ5หมู่', 'label': 'โปรตีนครบ5หมู่'},
						{'id': 'โปรตีนลดน้ำหนัก', 'label': 'โปรตีนลดน้ำหนัก'},
						{'id': 'โปรตีนสร้างกล้ามเนื้อ', 'label': 'โปรตีนสร้างกล้ามเนื้อ'},
					],
				},
				{
					'group': 'เมนูผักและผลไม้',
					'items': [
						{'id': 'ผักผลไม้ครบ5หมู่', 'label': 'ผักผลไม้ครบ5หมู่'},
						{'id': 'ผักผลไม้ลดน้ำหนัก', 'label': 'ผักผลไม้ลดน้ำหนัก'},
						{'id': 'ผักผลไม้บำรุงสุขภาพ', 'label': 'ผักผลไม้บำรุงสุขภาพ'},
					],
				},
				{
					'group': 'เมนูคาร์โบไฮเดรต',
					'items': [
						{'id': 'คาร์โบไฮเดรตครบ5หมู่', 'label': 'คาร์โบไฮเดรตครบ5หมู่'},
						{'id': 'คาร์โบไฮเดรตลดน้ำหนัก', 'label': 'คาร์โบไฮเดรตลดน้ำหนัก'},
						{'id': 'คาร์โบไฮเดรตให้พลังงานสูง', 'label': 'คาร์โบไฮเดรตให้พลังงานสูง'},
					],
				},
				{
					'group': 'เมนูเครื่องดื่ม',
					'items': [
						{'id': 'เครื่องดื่มเพื่อสุขภาพ', 'label': 'เครื่องดื่มเพื่อสุขภาพ'},
						{'id': 'เครื่องดื่มลดน้ำหนัก', 'label': 'เครื่องดื่มลดน้ำหนัก'},
						{'id': 'เครื่องดื่มเพิ่มพลังงาน', 'label': 'เครื่องดื่มเพิ่มพลังงาน'},
					],
				},
			];
		} catch (e) {
			if (kDebugMode) print('Failed to load goal groups: $e');
		} finally {
			if (mounted) setState(() => _loadingGoals = false);
		}
	}

	@override
  Widget build(BuildContext context) {
    final auth = AuthService();

		// Determine locked state: prefer server-refreshed flag (class `locked`), fall back to auth.user
		final bool isLocked = locked || (auth.user != null && auth.user!['health_goal_locked'] == true);

    final String displayName = auth.user != null
        ? (auth.user!['username'] ?? auth.user!['name'] ?? (auth.user!['id']?.toString() ?? ''))
        : (auth.isGuest ? 'Guest' : '');

    final personal = auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {};
    final stats = _computeBmiAndCalories(personal);
    final bmi = stats['bmi'] ?? '';
    final cal = stats['cal'] ?? '';

		return SafeArea(
			child: Scaffold(
        backgroundColor: const Color(0xFFF6F8F6),
				appBar: AppBar(
					backgroundColor: const Color(0xFFF6F8F6),
					elevation: 0,
					iconTheme: const IconThemeData(color: _accentGreen),
					leading: IconButton(
						icon: const Icon(Icons.arrow_back_ios),
						color: _accentGreen,
						onPressed: () => Navigator.of(context).maybePop(),
					),
					systemOverlayStyle: const SystemUiOverlayStyle(
						statusBarColor: Colors.white,
						statusBarIconBrightness: Brightness.dark,
					),
					title: Text('เลือกเป้าหมายด้านสุขภาพ', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold).copyWith(color: Colors.black)),
					centerTitle: true,
					actions: [
						Padding(
							padding: const EdgeInsets.only(right: 12.0),
							child: Center(child: Text(displayName, style: TextStyle(color: Colors.black, fontSize: 12))),
						),
					],
				),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                const Text('เลือกเป้าหมายด้านสุขภาพ', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w600)),
				if (isLocked)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Text('(เป้าหมายถูกล็อกถาวรหลังจากบันทึกแล้ว)', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                if (displayName.isNotEmpty) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0), 
                    child: Text('ผู้ใช้งาน: $displayName', style: const TextStyle(color: Colors.black54, fontSize: 14))
                  ),
                
                if (bmi.isNotEmpty || cal.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (bmi.isNotEmpty) Text('BMI: $bmi', style: const TextStyle(color: Colors.black87)),
                        if (cal.isNotEmpty) Text('แคลอรีที่แนะนำ: $cal', style: const TextStyle(color: Colors.black87)),
                      ],
                    ),
                  ),

				const SizedBox(height: 6),
					const Text(
						'เป้าหมายน้ำหนัก',
						style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
					),
					const Padding(
						padding: EdgeInsets.only(top: 2.0, bottom: 8.0),
						child: Text(
							'มีผลต่อแคลอรีเป้าหมายต่อวันโดยตรง',
							style: TextStyle(color: Colors.black54, fontSize: 12),
						),
					),
					if (!isLocked)
						...(_weightGoalOptions.map((g) {
							final bool isSelected = _selectedWeightGoal == g;
							return ListTile(
								dense: true,
								leading: Icon(
									isSelected ? Icons.check_circle : Icons.radio_button_off,
									color: isSelected ? _accentGreen : AppColors.inkSoft,
								),
								title: Text(g, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
								tileColor: isSelected ? _accentGreen.withValues(alpha: 0.06) : null,
								selected: isSelected,
								onTap: () => setState(() => _selectedWeightGoal = g),
							);
						}))
					else
						Padding(
							padding: const EdgeInsets.only(bottom: 8.0),
							child: Text('เป้าหมายน้ำหนัก: ${_selectedWeightGoal ?? '-'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87)),
						),

					const SizedBox(height: 16),
					const Text(
						'เป้าหมายด้านสุขภาพ', // เปลี่ยนชื่อหัวข้อหลักตรงนี้ให้ถูกต้องถาวร
						style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
					),
					const SizedBox(height: 8),

								// ส่วนแสดงผลเมื่อล็อก (Locked UI) — แสดงเป็นกล่องสรุปแยกบรรทัดสำหรับแต่ละหมวดอาหารและเครื่องดื่ม
								if (isLocked && (_selectedProteinGoal != null || _selectedVegGoal != null || _selectedCarbGoal != null || _selectedDrinkType != null)) ...[
									Padding(
										padding: const EdgeInsets.symmetric(vertical: 12.0),
										child: Container(
											width: double.infinity,
											padding: const EdgeInsets.all(16.0),
											decoration: BoxDecoration(
												color: _accentGreen.withValues(alpha: 0.08),
												borderRadius: BorderRadius.circular(12),
												border: Border.all(color: _accentGreen, width: 1.5),
											),
											child: Column(
												crossAxisAlignment: CrossAxisAlignment.start,
												mainAxisSize: MainAxisSize.min,
												children: [
													Row(
														children: [
															const Icon(Icons.check_circle, color: _accentGreen, size: 22),
															const SizedBox(width: 8),
															Text(
																'บันทึกเป้าหมายสุขภาพสำเร็จแล้ว',
																style: TextStyle(
																	fontSize: 16,
																	fontWeight: FontWeight.bold,
																	color: AppColors.inkSoft,
																),
														),
														],
													),
													const Divider(height: 20, thickness: 1, color: AppColors.inkSoft),
													// แต่ละหมวดอาหารแยกบรรทัดอย่างชัดเจน ไม่แย่งกันแสดงผล
													if (_selectedProteinGoal != null && _selectedProteinGoal!.isNotEmpty)
														Padding(
															padding: const EdgeInsets.only(bottom: 8.0),
															child: Text('🍗 เมนูโปรตีน: ${_selectedProteinGoal!}',
																style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
															),
														),
													if (_selectedVegGoal != null && _selectedVegGoal!.isNotEmpty)
														Padding(
															padding: const EdgeInsets.only(bottom: 8.0),
															child: Text('🥦 เมนูผักและผลไม้: ${_selectedVegGoal!}',
																style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
															),
														),
													if (_selectedCarbGoal != null && _selectedCarbGoal!.isNotEmpty)
														Padding(
															padding: const EdgeInsets.only(bottom: 8.0),
															child: Text('🍚 เมนูคาร์โบไฮเดรต: ${_selectedCarbGoal!}',
																style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
															),
														),
													// เครื่องดื่ม (แยกบรรทัดอย่างชัดเจน)
													if (_selectedDrinkType != null && _selectedDrinkType!.isNotEmpty)
														Text(
															(_selectedDrinkGoal != null && _selectedDrinkGoal!.isNotEmpty)
																? '🥤 เครื่องดื่ม: ${_selectedDrinkGoal!} — ${_selectedDrinkType!}'
																: '🥤 เครื่องดื่ม: เมนูเครื่องดื่ม — ${_selectedDrinkType!}',
															style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
													),
												],
											),
										),
									),
								],

				// ส่วนเลือกเป้าหมาย (Editable UI)
				if (!isLocked) ...[
                  if (_loadingGoals) 
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Center(child: CircularProgressIndicator())),
                  
				  if (!_loadingGoals && _groupedGoals.isNotEmpty) 
					..._groupedGoals.map((g) {
                      final List items = g['items'] as List;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0, bottom: 4.0), 
                            child: Text(g['group']?.toString() ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))
                          ),
													...items.map<Widget>((it) {
														final itemGroup = g['group']?.toString() ?? '';
														final itemValue = (it['id'] ?? it['label'])?.toString() ?? '';
														final bool isDrinkGroup = itemGroup.contains('เครื่องดื่ม');
														final String? categoryKey = _categoryKeyForGroup(itemGroup);
														final bool isSelected = isDrinkGroup
															? (_selectedDrinkType != null && _selectedDrinkType == itemValue)
															: (categoryKey != null && _foodGoalFor(categoryKey) == itemValue);
														return ListTile(
															leading: Icon(
															  isSelected ? Icons.check_circle : Icons.radio_button_off,
															  color: isSelected ? _accentGreen : AppColors.inkSoft,
															),
															title: Text(
															  it['label'] ?? it['id'],
															  style: TextStyle(
																fontSize: 14,
																fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
															  ),
															),
															tileColor: isSelected ? _accentGreen.withValues(alpha: 0.06) : null,
															selected: isSelected,
															onTap: isLocked ? null : () {
																setState(() {
																	if (isDrinkGroup) {
																		_selectedDrinkGoal = 'เมนูเครื่องดื่ม';
																		_selectedDrinkType = itemValue;
																	} else if (categoryKey != null) {
																		_setFoodGoalFor(categoryKey, itemValue);
																		_syncPrimaryFoodGoal();
																	}
																});
															},
														);
													}),
                        ],
                      );
                    }),

									if (!_loadingGoals && _groupedGoals.isEmpty) 
										..._fallbackGoalOptions.map((g) {
											final itemValue = g['id']!;
											final bool isSelected = (_selectedFoodGoal != null && _selectedFoodGoal == itemValue);
																						return ListTile(
																								leading: Icon(
																									isSelected ? Icons.check_circle : Icons.radio_button_off,
																									color: isSelected ? _accentGreen : AppColors.inkSoft,
																								),
																								title: Text(
																									g['label']!,
																									style: TextStyle(
																										fontSize: 14,
																										fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
																									),
																								),
																								selected: isSelected,
																								onTap: isLocked ? null : () => setState(() { _selectedFoodGoal = itemValue; _selectedFoodGroup = null; }),
																						);
										}),
                ],

                const SizedBox(height: 20),
                Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.disabled)) return AppColors.inkSoft;
                          return _accentGreen;
                        }),
                        foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                        elevation: WidgetStateProperty.all<double>(0),
                        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                        ),
                      ),
											// ปุ่มจะกดได้ก็ต่อเมื่อผู้ใช้เลือกครบ: เป้าหมายน้ำหนัก + อาหารคาว + เครื่องดื่ม
											onPressed: (isLocked || _saving || _selectedWeightGoal == null || !_allFoodGoalsSelected || _selectedDrinkType == null)
												? null
												: () async { await _showSummaryAndConfirm(); },
											child: _saving 
												? const CircularProgressIndicator()
												: Text(isLocked ? 'บันทึกแล้ว' : 'ตกลง'),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

	String _selectedGoalLabel() {
		// Compose a combined summary including all 3 food topics and the drink when available
		final List<String> parts = [];
		if (_selectedProteinGoal != null && _selectedProteinGoal!.isNotEmpty) {
			parts.add('เมนูโปรตีน — ${_selectedProteinGoal!}');
		}
		if (_selectedVegGoal != null && _selectedVegGoal!.isNotEmpty) {
			parts.add('เมนูผักและผลไม้ — ${_selectedVegGoal!}');
		}
		if (_selectedCarbGoal != null && _selectedCarbGoal!.isNotEmpty) {
			parts.add('เมนูคาร์โบไฮเดรต — ${_selectedCarbGoal!}');
		}
		if (_selectedDrinkType != null && _selectedDrinkType!.isNotEmpty) {
			final drinkLabel = (_selectedDrinkGoal != null && _selectedDrinkGoal!.isNotEmpty)
				? _selectedDrinkGoal!
				: 'เมนูเครื่องดื่ม';
			parts.add('$drinkLabel — ${_selectedDrinkType!}');
		}
		return parts.isNotEmpty ? parts.join(' และ ') : '';
	}

  @override
  void dispose() {
    try {
      AuthService().removeListener(_authListener);
    } catch (_) {}
    super.dispose();
  }
}