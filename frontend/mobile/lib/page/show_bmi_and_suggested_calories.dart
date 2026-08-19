import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:convert';

import 'choose_a_health_goal.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/app_config.dart';
import '../utils/bmi_calculator.dart' as bmi_calc;

class ShowBMIAndSuggestedCalories extends StatefulWidget {
	final String userId;
	final String bmi;
	final String calories;
	final String activity;
	final String chronicDiseases;
	final String foodAllergies;
	final String consumedCalories; // new: actual calories consumed by user

	const ShowBMIAndSuggestedCalories({
		super.key,
		this.userId = '',
		this.bmi = '',
		this.calories = '',
		this.activity = '',
		this.chronicDiseases = '',
		this.foodAllergies = '',
		this.consumedCalories = '0',
	});

	@override
	State<ShowBMIAndSuggestedCalories> createState() => _ShowBMIAndSuggestedCaloriesState();
}

class _ShowBMIAndSuggestedCaloriesState extends State<ShowBMIAndSuggestedCalories> {
	static const Color _accentGreen = AppColors.leaf;

	bool _isLoading = false;
	String _bmi = '';
	String _bmr = '';
	String _bmiStatus = '';

	double? _parseDouble(dynamic value) {
		if (value == null) return null;
		try {
			if (value is num) return value.toDouble();
			return double.tryParse(value.toString().trim());
		} catch (_) {
			return null;
		}
	}

	int? _parseInt(dynamic value) {
		if (value == null) return null;
		try {
			if (value is int) return value;
			return int.tryParse(value.toString().trim());
		} catch (_) {
			return null;
		}
	}

	double? _computeBmrFromPersonal(Map<String, dynamic> personal) {
		return bmi_calc.calcBmr(
			weight: _parseDouble(personal['weight']),
			height: _parseDouble(personal['height']),
			age: _parseInt(personal['age']),
			gender: personal['gender']?.toString(),
		);
	}

	double _diseaseAdjustmentFactor(String? diseases) {
		if (diseases == null || diseases.trim().isEmpty) return 0.0;
		final text = diseases.toLowerCase();
		double adjustments = 0.0;
		if (text.contains('เบาหวาน') || text.contains('diabetes')) adjustments -= 0.05;
		if (text.contains('ความดัน') || text.contains('hypertension')) adjustments -= 0.03;
		if (text.contains('โรคไต') || text.contains('ไต')) adjustments -= 0.05;
		if (text.contains('มะเร็ง')) adjustments += 0.10;
		if (text.contains('หืด')) adjustments -= 0.02;
		return adjustments;
	}

	@override
	void initState() {
		super.initState();
		_bmi = widget.bmi;
		// Compute an immediate local estimate so the UI matches the PersonalInformationPage
		try {
			final auth = AuthService();
			final personal = auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {};
			_bmiStatus = bmi_calc.bmiStatus(_parseDouble(_bmi)) ?? '';
			final localBmr = _computeBmrFromPersonal(personal);
			if (localBmr != null) {
				_bmr = localBmr.round().toString();
			}
		} catch (_) {
			_bmiStatus = bmi_calc.bmiStatus(_parseDouble(_bmi)) ?? '';
		}
		_fetchLatestHealthSummary();
	}


	Future<void> _fetchLatestHealthSummary() async {
		try {
			setState(() {
				_isLoading = true;
			});
			final auth = AuthService();
			// Prefer authenticated user's id when available; fall back to widget.userId when it's provided and non-empty.
			String? uid;
			try {
				if (auth.user != null && auth.user!['id'] != null) {
					uid = auth.user!['id'].toString();
				} else if (widget.userId.isNotEmpty && widget.userId != 'User ID') {
					uid = widget.userId;
				}
			} catch (_) {
				uid = (widget.userId.isNotEmpty && widget.userId != 'User ID') ? widget.userId : null;
			}
			if (uid == null || uid.isEmpty) {
				setState(() {
					_isLoading = false;
				});
				return;
			}

			final api = ApiClient(getApiBase());
			final resp = await api.get('/user/$uid');
			if (resp.statusCode == 200) {
				final decoded = json.decode(resp.body);
				setState(() {
					final personal = auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {};
					_bmi = decoded['bmi'] != null ? decoded['bmi'].toString() : (_bmi.isNotEmpty ? _bmi : '');
					_bmiStatus = bmi_calc.bmiStatus(_parseDouble(_bmi)) ?? '';
					if (decoded['bmr'] != null) {
						final serverBmr = decoded['bmr'];
						_bmr = serverBmr is num ? serverBmr.round().toString() : serverBmr.toString();
					} else {
						final localBmr = _computeBmrFromPersonal(personal);
						if (localBmr != null) {
							_bmr = localBmr.round().toString();
						}
					}
					if (_bmiStatus.isEmpty) {
						_bmiStatus = bmi_calc.bmiStatus(_parseDouble(_bmi)) ?? '';
					}
					_isLoading = false;
				});
			} else {
				if (kDebugMode) debugPrint('ShowBMI: non-200 ${resp.statusCode}');
				setState(() {
					_isLoading = false;
				});
			}
		} catch (e) {
			if (kDebugMode) debugPrint('Error fetching health summary: $e');
			setState(() {
				_isLoading = false;
			});
		}
	}

	String _formatKcal(double? value) {
		if (value == null || !value.isFinite) return '-';
		return '${value.round()} kcal';
	}

	// ========== BMI bar (segmented gauge with a marker at the user's BMI) ==========
	static const double _bmiMin = 15.0;
	static const double _bmiMax = 40.0;
	static const List<_BmiZone> _bmiZones = [
		_BmiZone('ผอม', 18.5, Color(0xFF60A5FA)),
		_BmiZone('ปกติ', 25.0, AppColors.leaf),
		_BmiZone('อวบ', 30.0, Color(0xFFFBBF24)),
		_BmiZone('อ้วน', _bmiMax, Color(0xFFEF4444)),
	];

	Widget _buildBmiBar(double? bmi) {
		final clamped = (bmi ?? (_bmiMin + _bmiMax) / 2).clamp(_bmiMin, _bmiMax);
		final fraction = (clamped - _bmiMin) / (_bmiMax - _bmiMin);

		double prevBound = _bmiMin;
		final segments = _bmiZones.map((z) {
			final flex = ((z.upperBound - prevBound) / (_bmiMax - _bmiMin) * 1000).round();
			prevBound = z.upperBound;
			return Expanded(flex: flex, child: Container(color: z.color));
		}).toList();

		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				LayoutBuilder(
					builder: (context, constraints) {
						final barWidth = constraints.maxWidth;
						const markerSize = 18.0;
						final markerLeft = (fraction * barWidth - markerSize / 2).clamp(0.0, barWidth - markerSize);
						return SizedBox(
							height: 34,
							child: Stack(
								clipBehavior: Clip.none,
								children: [
									Positioned(
										top: 10,
										left: 0,
										right: 0,
										child: ClipRRect(
											borderRadius: BorderRadius.circular(8),
											child: SizedBox(height: 14, child: Row(children: segments)),
										),
									),
									if (bmi != null)
										Positioned(
											left: markerLeft,
											top: 0,
											child: Column(
												children: [
													Icon(Icons.arrow_drop_down, color: Colors.black87, size: markerSize + 6),
												],
											),
										),
								],
							),
						);
					},
				),
				const SizedBox(height: 6),
				Row(
					mainAxisAlignment: MainAxisAlignment.spaceBetween,
					children: _bmiZones
							.map((z) => Text(z.label, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)))
							.toList(),
				),
			],
		);
	}

	Widget _buildMetricRow(IconData icon, String label, String value) {
		return Row(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				Container(
					width: 36,
					height: 36,
					decoration: BoxDecoration(
						color: _accentGreen.withValues(alpha: 0.12),
						borderRadius: BorderRadius.circular(10),
					),
					child: Icon(icon, color: _accentGreen, size: 18),
				),
				const SizedBox(width: 10),
				Expanded(
					child: Column(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							Text(label, style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
							Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
						],
					),
				),
			],
		);
	}

	Widget _buildCard({required Widget child}) {
		return Container(
			width: double.infinity,
			padding: const EdgeInsets.all(16),
			margin: const EdgeInsets.only(bottom: 14),
			decoration: BoxDecoration(
				color: Colors.white,
				borderRadius: BorderRadius.circular(16),
				boxShadow: [
					BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
				],
			),
			child: child,
		);
	}

	Widget _buildCalorieGoalRow(Color color, String text) {
		return Padding(
			padding: const EdgeInsets.symmetric(vertical: 4.0),
			child: Row(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Container(
						width: 14,
						height: 14,
						margin: const EdgeInsets.only(top: 2),
						decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
					),
					const SizedBox(width: 10),
					Expanded(
						child: Text(text, style: const TextStyle(color: Colors.black87, fontSize: 13)),
					),
				],
			),
		);
	}

	@override
	Widget build(BuildContext context) {
		final auth = AuthService();
		String normalize(dynamic v) {
			try {
				if (v == null) return '';
				final s = v.toString().trim();
				if (s.isEmpty) return '';
				final low = s.toLowerCase();
				if (low == 'null' || low == 'none' || low == 'nan') return '';
				return s;
			} catch (_) {
				return '';
			}
		}

    final String displayBmi = normalize(_bmi.isNotEmpty ? _bmi : widget.bmi);
    final String displayBmr = normalize(_bmr);

    final Map<String, dynamic> personal = auth.user ?? auth.tempPersonal ?? auth.guestPersonal ?? {};
    final String activityLabel = widget.activity.isNotEmpty
        ? widget.activity
        : (personal['activity']?.toString() ?? '');
    final String diseasesLabel = widget.chronicDiseases.isNotEmpty
        ? widget.chronicDiseases
        : (personal['chronic_diseases']?.toString() ?? '');
    final double diseaseAdjustment = _diseaseAdjustmentFactor(diseasesLabel);

    final double? bmiValue = _parseDouble(displayBmi);
    // เดิมคำนวณ TDEE จาก BMR ที่ปัดเศษเป็นจำนวนเต็มไปแล้ว (parse กลับจาก
    // displayBmr) ทำให้เพี้ยนไปได้ 1 kcal ในบางเคส (ดู bmi_calculator.dart)
    // คำนวณจากน้ำหนัก/ส่วนสูง/อายุ/เพศตรงๆ แทน ให้ได้ BMR ดิบไม่ปัดเศษก่อน
    final double? tdeeValue = bmi_calc.calcTdee(
      weight: _parseDouble(personal['weight']),
      height: _parseDouble(personal['height']),
      age: _parseInt(personal['age']),
      gender: personal['gender']?.toString(),
      activity: activityLabel,
    );
    final double? adjustedTdeeValue = tdeeValue != null ? tdeeValue * (1.0 + diseaseAdjustment) : null;
    final String displayTdee = _formatKcal(adjustedTdeeValue ?? tdeeValue);
    final String lose05Text = _formatKcal(adjustedTdeeValue != null ? adjustedTdeeValue - 500 : null);
    final String lose1Text = _formatKcal(adjustedTdeeValue != null ? adjustedTdeeValue - 1000 : null);
    final String gain05Text = _formatKcal(adjustedTdeeValue != null ? adjustedTdeeValue + 500 : null);
    final String gain1Text = _formatKcal(adjustedTdeeValue != null ? adjustedTdeeValue + 1000 : null);
    final String bmiStatusText = bmi_calc.bmiStatus(bmiValue) ?? _bmiStatus;

		String displayName = '';
		try {
			if (auth.user != null) {
				displayName = auth.user!['username']?.toString() ??
					auth.user!['name']?.toString() ??
					auth.user!['display_name']?.toString() ??
					auth.user!['id']?.toString() ??
					'';
			}
			if (displayName.isEmpty) displayName = auth.isGuest ? 'Guest' : '';
		} catch (_) {}

		return Scaffold(
			backgroundColor: const Color(0xFFF6F8F6),
			appBar: AppBar(
				backgroundColor: const Color(0xFFF6F8F6),
				elevation: 0,
				leading: IconButton(
					icon: const Icon(Icons.arrow_back),
					color: _accentGreen,
					onPressed: () => Navigator.of(context).maybePop(),
				),
				title: const Text(
					'BMI และแคลอรีแนะนำ',
					style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w700),
				),
				actions: [
					Padding(
						padding: const EdgeInsets.only(right: 12.0),
						child: Center(
							child: Text(displayName, style: const TextStyle(color: Colors.black, fontSize: 12)),
						),
					),
				],
			),
			body: SafeArea(
				child: SingleChildScrollView(
					padding: const EdgeInsets.all(16.0),
					child: Column(
						crossAxisAlignment: CrossAxisAlignment.stretch,
						children: [
							_buildCard(
								child: Column(
									crossAxisAlignment: CrossAxisAlignment.start,
									children: [
										Row(
											mainAxisAlignment: MainAxisAlignment.spaceBetween,
											children: [
												const Text('ดัชนีมวลกาย (BMI)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
												Text(
													'${displayBmi.isNotEmpty ? displayBmi : '-'} ${bmiStatusText.isNotEmpty ? '($bmiStatusText)' : ''}',
													style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black),
												),
											],
										),
										const SizedBox(height: 14),
										_buildBmiBar(bmiValue),
									],
								),
							),
							_buildCard(
								child: Row(
									children: [
										Expanded(child: _buildMetricRow(Icons.local_fire_department_outlined, 'BMR (พลังงานพื้นฐาน)', displayBmr.isNotEmpty ? '$displayBmr kcal' : '-')),
										const SizedBox(width: 12),
										Expanded(child: _buildMetricRow(Icons.bolt_outlined, 'TDEE (พลังงานที่ใช้/วัน)', displayTdee)),
									],
								),
							),
							if (_isLoading)
								const Padding(
									padding: EdgeInsets.symmetric(vertical: 8),
									child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
								),
							_buildCard(
								child: Column(
									crossAxisAlignment: CrossAxisAlignment.start,
									children: [
										const Text('คำแนะนำแคลอรีต่อวัน', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
										const SizedBox(height: 4),
										Text(
											'กิจกรรม: ${activityLabel.isNotEmpty ? activityLabel : 'ไม่ระบุ'}',
											style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
										),
										const SizedBox(height: 12),
										_buildCalorieGoalRow(Colors.orange.shade600, 'ลดน้ำหนัก 0.5 กก./สัปดาห์: $lose05Text'),
										_buildCalorieGoalRow(Colors.red.shade600, 'ลดน้ำหนัก 1 กก./สัปดาห์: $lose1Text'),
										_buildCalorieGoalRow(_accentGreen, 'เพิ่มน้ำหนัก 0.5 กก./สัปดาห์: $gain05Text'),
										_buildCalorieGoalRow(Colors.blue.shade600, 'เพิ่มน้ำหนัก 1 กก./สัปดาห์: $gain1Text'),
									],
								),
							),
							const SizedBox(height: 8),
							SizedBox(
								height: 48,
								child: ElevatedButton(
									style: ElevatedButton.styleFrom(
										backgroundColor: _accentGreen,
										foregroundColor: Colors.white,
										shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
										elevation: 0,
									),
									onPressed: () {
										Navigator.of(context).pushReplacement(
											MaterialPageRoute(builder: (_) => ChooseAHealthGoal(userId: widget.userId)),
										);
									},
									child: const Text('ถัดไป: เลือกเป้าหมายสุขภาพ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
								),
							),
						],
					),
				),
			),
		);
	}
}

class _BmiZone {
	final String label;
	final double upperBound;
	final Color color;
	const _BmiZone(this.label, this.upperBound, this.color);
}
