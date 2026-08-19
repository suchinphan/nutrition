import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:math' as math;
import 'package:translator/translator.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';
import 'selection_summary_page.dart';

class ImageGallerySheet extends StatefulWidget {
  final String title;
  final Future<List<String>> Function(int page) fetcher;
  const ImageGallerySheet({
    super.key,
    required this.title,
    required this.fetcher,
  });

  @override
  State<ImageGallerySheet> createState() => _ImageGallerySheetState();
}

class _ImageGallerySheetState extends State<ImageGallerySheet> {
  List<String> images = [];
  int page = 1;
  bool loading = false;
  bool hasMore = true;
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPage();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 300 &&
          !loading &&
          hasMore) {
        _loadPage();
      }
    });
  }

  Future<void> _loadPage() async {
    setState(() => loading = true);
    try {
      final res = await widget.fetcher(page);
      if (res.isEmpty) {
        setState(() => hasMore = false);
      } else {
        setState(() {
          images.addAll(res);
          page += 1;
        });
      }
    } catch (e) {
      if (kDebugMode) print('ImageGallerySheet._loadPage error: $e');
      setState(() => hasMore = false);
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.leaf),
        title: Text(
          widget.title,
          style: const TextStyle(color: AppColors.leaf),
        ),
      ),
      body: GridView.builder(
        controller: _sc,
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 16 / 9,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: images.length + (hasMore ? 1 : 0),
        itemBuilder: (ctx, idx) {
          if (idx >= images.length) {
            return Center(
              child: loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _loadPage,
                      child: const Text('Load more'),
                    ),
            );
          }
          final url = images[idx];
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.card,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ChooseFoodTypePage extends StatefulWidget {
  const ChooseFoodTypePage({super.key});

  @override
  State<ChooseFoodTypePage> createState() => _ChooseFoodTypePageState();
}

class _ChooseFoodTypePageState extends State<ChooseFoodTypePage> {
  final Color primaryGreen = AppColors.leaf;

  late final ApiClient api;
  late final AuthService _auth;

  bool _authLoaded = false;
  String? selectedHealthGoalLabel;
  String? selectedHealthGoalGroup;
  bool lockCategoryMenu = false;
  // Drink-specific health goal stored in state
  String? healthGoalDrink;
  List<String> healthGoalDrinkTypes = [];

  // ===== selections (id) =====
  int? selectedFoodTypeId;
  int? selectedCategoryId;
  int? selectedFoodMenuId;
  int? selectedDrinkTypeId;
  int? selectedDrinkMenuId;
  int? selectedDessertId;
  // Controllers for free-text inputs (replace dropdowns)
  late final TextEditingController foodTypeController;
  String? foodTypeLabel;
  late final TextEditingController categoryController;
  late final TextEditingController foodMenuController;
  late final TextEditingController dessertMenuController;
  late final TextEditingController drinkTypeController;
  late final TextEditingController drinkMenuController;
  // New independent text controllers for idea #2 (three free-text search fields)
  late final TextEditingController foodController;
  late final TextEditingController dessertController;
  late final TextEditingController drinkController;

  bool _isFetchingRandomFood = false;
  bool _isFetchingRandomDessert = false;
  bool _isFetchingRandomDrink = false;

  // Matched items from backend search (one per independent field)
  Map<String, dynamic>? matchedFood;
  Map<String, dynamic>? matchedDessert;
  Map<String, dynamic>? matchedDrink;

  // Selected quantities per matched item
  int? selectedFoodQty;
  int? selectedDessertQty;
  int? selectedDrinkQty;

  // Error / advice messages
  String? foodError;
  String? foodMenuError;
  String? dessertError;
  String? drinkError;

  String? foodAdvice;
  String? dessertAdvice;
  String? drinkAdvice;

  // Image urls from Pexels
  String? foodImageUrl;
  String? dessertImageUrl;
  String? drinkImageUrl;
  // Image selected from the gallery sheet (returned via Navigator.pop)
  String? selectedImageFromGallery;
  // Safety check state
  bool isSafetyChecked = false;
  bool isFoodSafe = false;
  // Per-category gating flags: dessert is optional so it must NOT share a
  // single flag with food/drink, otherwise typing+clearing the optional
  // dessert field wedges the shared flag false and permanently blocks Next.
  bool _foodSafetyOk = false;
  bool _drinkSafetyOk = false;

  // Strict Next-button getter: require both savory and drink filled, matched and safety-checked
  bool get _canAttemptNext {
    final savoryValid =
        foodController.text.trim().isNotEmpty &&
        matchedFood != null &&
        _foodSafetyOk;
    final drinkValid =
        drinkController.text.trim().isNotEmpty &&
        matchedDrink != null &&
        _drinkSafetyOk;
    return savoryValid && drinkValid;
  }

  bool get nextEnabled {
    return _canAttemptNext && !_fieldsLocked;
  }

  // Pexels API key for fetching images
  final String pexelsApiKey =
      'WcelMh34eAWQsMaVgwZnAO9PtAsdFvlA34NgCRqkC3HojHjkX5Fv8xzy';

  // --- Live calculation / conditional UI state ---
  // หมวดหมู่อาหารคาว
  int foodQuantity = 1;
  String selectedFoodUnit = 'จาน';
  final List<String> foodUnits = [
    'จาน',
    'ชาม',
    'ถ้วย',
    'ชุด',
    'กล่อง',
    'ห่อ',
    'ที่',
    'ชิ้น',
    'ไม้',
    'ถาด',
  ];
  double? calculatedFoodCalories;

  // หมวดหมู่ของหวาน
  int dessertQuantity = 1;
  String selectedDessertUnit = 'ถ้วย';
  final List<String> dessertUnits = [
    'ถ้วย',
    'ชาม',
    'จาน',
    'ชิ้น',
    'ก้อน',
    'ลูก',
    'ถาด',
    'ถ้วยเล็ก',
  ];
  double? calculatedDessertCalories;

  // หมวดหมู่เครื่องดื่ม
  int drinkQuantity = 1;
  String selectedDrinkUnit = 'แก้ว';
  final List<String> drinkUnits = [
    'แก้ว',
    'ขวด',
    'กระป๋อง',
    'ถ้วย',
    'แก้วมัค',
    'เหยือก',
    'ช็อต',
    'แก้วใหญ่',
    'แก้วเล็ก',
    'กล่อง',
    'ซอง',
  ];
  double? calculatedDrinkCalories;

  // ===== data from API =====
  List<Map<String, dynamic>> foodTypes = [];
  // keep an unfiltered copy so we can re-apply filters
  List<Map<String, dynamic>> allFoodTypes = [];
  List<Map<String, dynamic>> foodCategories = [];
  List<Map<String, dynamic>> foodMenus = [];
  List<Map<String, dynamic>> foods = [];
  List<Map<String, dynamic>> desserts = [];
  List<Map<String, dynamic>> drinks = [];
  List<Map<String, dynamic>> drinkTypes = [];
  List<Map<String, dynamic>> drinkMenus = [];
  // search results for food-menu typeahead
  List<Map<String, dynamic>> searchedFoodMenus = [];
  List<Map<String, dynamic>> searchedDesserts = [];
  List<Map<String, dynamic>> searchedDrinks = [];
  Timer? _searchDebounce;
  // realtime debounce timers for independent free-text fields
  Timer? _realtimeDebounceFood;
  Timer? _realtimeDebounceDessert;
  Timer? _realtimeDebounceDrink;
  // debounce timers to control when to show generated thumbnails
  Timer? _thumbnailDebounceFood;
  Timer? _thumbnailDebounceDrink;
  // simple cache for single-image thumbnails to avoid network in build()
  final Map<String, String?> _imageCache = {};
  bool _saving = false;
  bool _fieldsLocked = false;
  String? _activeMealLabel;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;
  Timer? _thaiClockTimer;
  Timer? _statusPollTimer;
  Timer?
  _midnightRedirectTimer; // ⏳ ตัวแปรใหม่: จับเวลาตรวจสอบสัญญาณตัดยอดหลังเที่ยงคืน
  bool _midnightDialogShown = false;
  DateTime? _thaiNow;
  List<String> _plannedMeals = [];
  DateTime? _lockUntil;
  bool _mealWindowLocked = false;
  String? _lastShownSummaryKey;
  int? selectedFoodMenuCalories;
  int? selectedDrinkMenuCalories;
  int? selectedDessertMenuCalories;
  // Server-provided dynamic safety / quota info
  double? remainingCaloriesToday;
  double? consumedCaloriesToday;
  bool? itemSafe;
  String? safetyMessage;
  String? upgradeTips;
  Map<String, dynamic>? swapSuggestion;
  // Plan / quota fields (from user selection)
  int? _planCaloriesGoalInt;
  int? _planDurationInt;
  double? _perMealQuota;
  bool _overQuota = false;
  String? _healthGoalWarning;
  // Smart Portion Slider state (0.5 .. 1.0)
  double _currentPortion = 1.0;
  // Adjusted values returned from backend
  double? adjustedCalories;
  double? adjustedSugar;
  int? adjustedSodium;

  @override
  void initState() {
    super.initState();
    api = ApiClient("http://127.0.0.1:5000");
    _auth = AuthService();

    foodTypeController = TextEditingController();
    categoryController = TextEditingController();
    foodMenuController = TextEditingController();
    dessertMenuController = TextEditingController();
    drinkTypeController = TextEditingController();
    drinkMenuController = TextEditingController();
    foodController = TextEditingController();
    dessertController = TextEditingController();
    drinkController = TextEditingController();

    Future.microtask(() async {
      _thaiNow = DateTime.now().toUtc().add(const Duration(hours: 7));
      _thaiClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _thaiNow = DateTime.now().toUtc().add(const Duration(hours: 7));
        });
      });

      await _auth.loadToken();
      // Try to refresh full profile from server after token is loaded
      try {
        final token = _auth.token;
        if (token != null && token.isNotEmpty) {
          await _auth.refreshProfile();
        }
      } catch (e) {
        if (kDebugMode) print("Error fetching fresh user info on init: $e");
      }

      await _loadFoodTypes();
      await _loadDrinkTypes();

      // Auto-fill from persisted user profile (`_auth.user`) when available
      try {
        final up = _auth.user;
        if (up != null) {
          // Ensure explicit mapping: `health_goal` => selectedHealthGoalLabel (user's goal),
          // and `health_goal_group` => selectedHealthGoalGroup (food type group).
          try {
            final hg = up['health_goal'];
            if (hg != null && hg.toString().trim().isNotEmpty) {
              selectedHealthGoalLabel = hg.toString();
              // show health goal in the category text (user-visible label)
              categoryController.text = _firstChoice(selectedHealthGoalLabel!);
            }
          } catch (e) {
            if (kDebugMode) print('Error parsing user.health_goal: $e');
          }

          try {
            final hgg = up['health_goal_group'];
            if (hgg != null && hgg.toString().trim().isNotEmpty) {
              selectedHealthGoalGroup = hgg.toString();
              // show food type group in the food type controller
              foodTypeController.text = _firstChoice(
                selectedHealthGoalGroup!.trim(),
              );
              foodTypeLabel = foodTypeController.text;
            }
          } catch (e) {
            if (kDebugMode) print('Error parsing user.health_goal_group: $e');
          }
        }

        // If we resolved a readable foodTypeLabel (health_goal_group), try mapping it to an ID and load categories
        try {
          final fLabel = foodTypeLabel;
          if (fLabel != null && fLabel.isNotEmpty) {
            final match = foodTypes.firstWhere(
              (e) =>
                  (e['name'] ?? '').toString().trim().toLowerCase() ==
                  fLabel.toLowerCase(),
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              final idVal = match['id'] is int
                  ? match['id'] as int
                  : int.tryParse(match['id'].toString());
              if (idVal != null) {
                selectedFoodTypeId = idVal;
                await _loadFoodCategories(idVal);
              }
            } else {
              selectedFoodTypeId = null;
            }
          }
        } catch (e) {
          if (kDebugMode) print('Error mapping foodTypeLabel to id: $e');
        }
      } catch (e) {
        if (kDebugMode) print('Auto-fill error: $e');
      }

      // If guest is locked or there are persisted temp/guest selections, preload them
      await _loadSavedSelections();
      // initialize quota from tempSelections or persisted user data
      _initializeQuotaFromTemp();
      // Immediately refresh local meal-window state so guest or temp selections
      // can be enforced even before any server lock info arrives.
      _refreshMealWindowState();
      // Restore lock state from server if there's an active lock
      await _restoreLockStateFromServer();
      // Start periodic polling of authoritative meal-window state from server
      // Reduced frequency from 5s to 30s to avoid excessive polling
      _statusPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        _pollMealWindowState();
      });

      // ⏳ ตั้งเวลาทำงานเบื้องหลัง คอยตรวจสอบเงื่อนไขเวลาเที่ยงคืนประเทศไทยทุกๆ 5 วินาที
      // Reduced midnight check frequency and add in-client guard to show dialog once
      _midnightRedirectTimer = Timer.periodic(const Duration(seconds: 30), (
        timer,
      ) {
        if (!mounted) return;
        _checkMidnightAutoSummaryStatus();
      });

      if (mounted) {
        setState(() => _authLoaded = true);
      }
    });
    // Listen for auth changes so lock state and selections refresh UI
    try {
      _auth.addListener(_authListener);
    } catch (e) {
      if (kDebugMode) print('Failed to add auth listener: $e');
    }
  }

  void _initializeQuotaFromTemp() {
    try {
      final sels = _auth.tempSelections ?? _auth.guestSelections ?? {};
      if (sels.containsKey('plan_calories_goal')) {
        final pcg = sels['plan_calories_goal'];
        _planCaloriesGoalInt = pcg is int
            ? pcg
            : int.tryParse(pcg?.toString() ?? '0');
      }
      if (sels.containsKey('duration')) {
        final dur = sels['duration'];
        _planDurationInt = dur is int
            ? dur
            : int.tryParse(dur?.toString() ?? '1');
      }
      if (_planCaloriesGoalInt != null &&
          _planDurationInt != null &&
          (_planDurationInt ?? 1) > 0) {
        _perMealQuota = (_planCaloriesGoalInt! / (_planDurationInt ?? 1));
      }
      _recomputeSelectedCalories();
    } catch (e) {
      if (kDebugMode) print('Failed to initialize quota: $e');
    }
  }

  void _startCountdown(int seconds) {
    try {
      _countdownTimer?.cancel();
      setState(() {
        _countdownSeconds = seconds;
        _thaiNow = DateTime.now().toUtc().add(const Duration(hours: 7));
      });
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() {
          _countdownSeconds = math.max(0, _countdownSeconds - 1);
          _thaiNow = DateTime.now().toUtc().add(const Duration(hours: 7));
        });
        if (_countdownSeconds <= 0) {
          t.cancel();
          _checkMealWindowState();
        }
      });
    } catch (e) {
      if (kDebugMode) print('Countdown start error: $e');
    }
  }

  void _stopCountdown() {
    try {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      setState(() {
        _countdownSeconds = 0;
      });
    } catch (_) {}
  }

  Future<void> _showDailySummaryDialog(bool isSuccess, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.cancel,
                color: isSuccess ? Colors.green : Colors.red,
                size: 30,
              ),
              const SizedBox(width: 10),
              Text(
                isSuccess ? 'เป้าหมายสำเร็จ!' : 'เป้าหมายไม่สำเร็จ',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(message, style: const TextStyle(fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () {
                if (!mounted) return;
                Navigator.of(context).pop();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text(
                'ตกลง',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkMealWindowState() async {
    if (!mounted) return;
    try {
      final token = _auth.token;
      if (token == null || token.isEmpty) return;
      final res = await api.get(
        '/meal-window-state',
        timeoutSeconds: 8,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return;

      final Map<String, dynamic> data = jsonDecode(res.body);
      if (data['now'] != null) {
        _thaiNow = DateTime.parse(data['now'].toString()).toLocal();
      }

      final bool apiLocked = data['locked'] ?? false;
      final String msg = data['message'] ?? '';
      final String state = data['state'] ?? 'open';
      final dynamic summary = data['daily_summary'];
      final bool cutoffReached =
          summary is Map && (summary['cutoff_reached'] == true);
      final String dayResult = summary is Map
          ? (summary['day_result'] ?? 'pending').toString()
          : 'pending';
      final List<dynamic>? planned = data['planned_meals'] is List
          ? data['planned_meals'] as List<dynamic>
          : null;

      String currentActiveMeal = '';
      if (state == 'open' && msg.isNotEmpty) {
        if (msg.contains('มื้อเช้า')) currentActiveMeal = 'เช้า';
        if (msg.contains('มื้อกลางวัน')) currentActiveMeal = 'กลางวัน';
        if (msg.contains('มื้อเย็น')) currentActiveMeal = 'เย็น';
      }

      String? summaryKey;
      if (summary is Map) {
        final plannedSummary =
            (summary['planned_meals'] as List?)?.whereType<String>().toList() ??
            [];
        final submittedSummary =
            (summary['submitted_meals'] as List?)
                ?.whereType<String>()
                .toList() ??
            [];
        final missingSummary =
            (summary['missing_meals'] as List?)?.whereType<String>().toList() ??
            [];
        summaryKey =
            '${summary['day_result'] ?? 'pending'}:${plannedSummary.join('|')}:${submittedSummary.join('|')}:${missingSummary.join('|')}:${summary['cutoff_reached'] ?? false}';
      }

      setState(() {
        final String? newActiveMeal = currentActiveMeal.isNotEmpty
            ? currentActiveMeal
            : null;
        final bool shouldClearInputs =
            newActiveMeal != null && newActiveMeal != _activeMealLabel;
        if (shouldClearInputs) {
          _clearInputControllers();
        }

        if (state == 'summary_pending') {
          _mealWindowLocked = true;
          _fieldsLocked = true;
          _clearInputControllers();
          if (data['deadline_at'] != null) {
            final dl = DateTime.parse(data['deadline_at'].toString()).toLocal();
            _countdownSeconds = dl
                .difference(_thaiNow ?? DateTime.now())
                .inSeconds;
            if (_countdownSeconds < 0) _countdownSeconds = 0;
          }
        } else if (state == 'waiting_next' && apiLocked) {
          _mealWindowLocked = false;
          _fieldsLocked = true;
          _clearInputControllers();
          if (data['deadline_at'] != null) {
            final dl = DateTime.parse(data['deadline_at'].toString()).toLocal();
            _countdownSeconds = dl
                .difference(_thaiNow ?? DateTime.now())
                .inSeconds;
            if (_countdownSeconds < 0) _countdownSeconds = 0;
          }
        } else {
          _mealWindowLocked = apiLocked;
          _fieldsLocked = apiLocked;
          if (_fieldsLocked) {
            _clearInputControllers();
          }
          if (data['deadline_at'] != null) {
            final dl = DateTime.parse(data['deadline_at'].toString()).toLocal();
            _countdownSeconds = dl
                .difference(_thaiNow ?? DateTime.now())
                .inSeconds;
            if (_countdownSeconds < 0) _countdownSeconds = 0;
          }
        }

        _activeMealLabel = newActiveMeal;

        if (planned != null) {
          _plannedMeals = planned.whereType<String>().toList();
        }
      });

      if (cutoffReached &&
          summaryKey != null &&
          summaryKey != _lastShownSummaryKey) {
        // Only show the daily summary dialog when there is meaningful activity
        // either locally on this page (user has selected or matched items) or
        // when the server-side summary contains planned/submitted meals.
        final List<String> submittedSummaryLocal =
            ((summary['submitted_meals'] as List?)
                      ?.whereType<String>()
                      .toList()) ??
            [];

        // Treat server activity as meaningful only when there are actual submissions
        // for the day (not merely planned meals). Also respect any_submission flag
        // when provided by the API.
        final bool serverHasActivity =
            submittedSummaryLocal.isNotEmpty ||
            ((summary['any_submission'] == true));
        final bool localHasActivity =
            matchedFood != null ||
            matchedDessert != null ||
            matchedDrink != null ||
            selectedFoodMenuId != null ||
            selectedDessertId != null ||
            selectedDrinkMenuId != null;

        // mark we already considered this summary key to avoid duplicates
        _lastShownSummaryKey = summaryKey;

        if (serverHasActivity || localHasActivity) {
          _countdownTimer?.cancel();
          _countdownTimer = null;
          _clearInputControllers();

          final String summaryMsg = (summary['message'] ?? 'สิ้นสุดรอบเวลาการประมวลผลประจำวัน')
                    .toString();
          final bool isSuccess = dayResult == 'success';

          await _showDailySummaryDialog(isSuccess, summaryMsg);
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error checking meal window state: $e');
    }
  }

  Future<void> _pollMealWindowState() async {
    await _checkMealWindowState();
  }

  // 2. ฟังก์ชันตรวจจับสัญญาณและพาเด้งกลับหน้าหลักทันทีเมื่อเลยเวลาเที่ยงคืน
  Future<void> _checkMidnightAutoSummaryStatus() async {
    try {
      final token = _auth.token;
      if (token == null || token.isEmpty) return;

      final res = await api.get(
        '/api/meal_window_state',
        timeoutSeconds: 8,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);

        // Prefer server-supplied midnight_summary flag when present
        if (data['midnight_summary'] != null &&
            data['midnight_summary']['show_dialog'] == true) {
          // Avoid showing the same midnight dialog repeatedly in short succession
          if (_midnightDialogShown) return;
          final ms = data['midnight_summary'];
          _midnightRedirectTimer?.cancel();

          // Only present the midnight summary dialog if the current page has
          // local selections from the user. This prevents surprising dialogs
          // when there's only historical server activity (e.g., previous meals submitted).
          final bool localHasActivity =
              matchedFood != null ||
              matchedDessert != null ||
              matchedDrink != null ||
              selectedFoodMenuId != null ||
              selectedDessertId != null ||
              selectedDrinkMenuId != null;

          if (localHasActivity) {
            if (mounted) {
              _showDailySummaryDialog(
                ms['day_result'] == 'SUCCESS',
                'ระบบได้สรุปผลประจำวันที่ผ่านมา',
              );
              _midnightDialogShown = true;
            }
          }
          return;
        }

        // Fallback to legacy should_redirect_main flag
        if (data['should_redirect_main'] == true) {
          _midnightRedirectTimer?.cancel(); // หยุดการทำงานของตัวจับเวลา
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.av_timer, color: Colors.green, size: 28),
                    SizedBox(width: 8),
                    Text(
                      'ระบบตัดยอดประจำวัน',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                content: const Text(
                  'ขณะนี้เลยเวลาเที่ยงคืน (00:00 น.) เป็นวันใหม่แล้ว ระบบได้สรุปผลลัพธ์สารอาหารประจำวันของคุณเรียบร้อยแล้ว '
                  'ระบบจะนำคุณกลับสู่หน้าหลัก ซึ่งคุณสามารถเปิดเข้ามาดูผลลัพธ์ย้อนหลังเวลาใดก็ได้ตามต้องการ (เช้า กลางวัน หรือเย็น)',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      if (!mounted) return;
                      Navigator.of(ctx).pop();
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/', (route) => false);
                    },
                    child: const Text(
                      'ตกลงกลับหน้าหลัก',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error checking midnight auto summary status: $e');
    }
  }

  void _clearInputControllers() {
    try {
      foodController.clear();
      dessertController.clear();
      drinkController.clear();
      foodMenuController.clear();
      dessertMenuController.clear();
      drinkMenuController.clear();
      // reset matched/selected state
      setState(() {
        matchedFood = null;
        matchedDessert = null;
        matchedDrink = null;
        selectedFoodMenuId = null;
        selectedDessertId = null;
        selectedDrinkMenuId = null;
        selectedFoodMenuCalories = 0;
        selectedDessertMenuCalories = 0;
        selectedDrinkMenuCalories = 0;
        calculatedFoodCalories = 0.0;
        calculatedDessertCalories = 0.0;
        calculatedDrinkCalories = 0.0;
        isSafetyChecked = false;
        isFoodSafe = false;
        _foodSafetyOk = false;
        _drinkSafetyOk = false;
      });
    } catch (e) {
      if (kDebugMode) print('clear controllers error: $e');
    }
  }

  String? _currentThaiMeal(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 10) return 'เช้า';
    if (hour >= 10 && hour < 15) return 'กลางวัน';
    if (hour >= 15 && hour < 21) return 'เย็น';
    return null;
  }

  String? _resolveMealLabelForCurrentWindow(List<String> plannedMeals) {
    final now =
        _thaiNow ?? DateTime.now().toUtc().add(const Duration(hours: 7));
    final windows = <String, DateTime>{
      'เช้า': DateTime(now.year, now.month, now.day, 5, 0),
      'กลางวัน': DateTime(now.year, now.month, now.day, 10, 0),
      'เย็น': DateTime(now.year, now.month, now.day, 15, 0),
    };
    final deadlines = <String, DateTime>{
      'เช้า': DateTime(now.year, now.month, now.day, 9, 59, 59),
      'กลางวัน': DateTime(now.year, now.month, now.day, 14, 59, 59),
      'เย็น': DateTime(now.year, now.month, now.day, 20, 59, 59),
    };

    for (final meal in ['เช้า', 'กลางวัน', 'เย็น']) {
      if (!plannedMeals.contains(meal)) continue;
      if (_isWithinWindow(now, windows[meal]!, deadlines[meal]!)) {
        return meal;
      }
    }

    return plannedMeals.isNotEmpty ? plannedMeals.first : null;
  }

  bool _isWithinWindow(DateTime now, DateTime start, DateTime end) {
    return !now.isBefore(start) && !now.isAfter(end);
  }

  DateTime? _nextPlannedMealOpenAt(List<String> planned, DateTime now) {
    final windows = <String, DateTime>{
      'เช้า': DateTime(now.year, now.month, now.day, 5, 0),
      'กลางวัน': DateTime(now.year, now.month, now.day, 10, 0),
      'เย็น': DateTime(now.year, now.month, now.day, 15, 0),
    };
    for (final meal in ['เช้า', 'กลางวัน', 'เย็น']) {
      if (!planned.contains(meal)) continue;
      final startAt = windows[meal]!;
      if (now.isBefore(startAt)) return startAt;
    }
    return null;
  }

  List<String> _parsePlannedMeals(dynamic value) {
    final List<String> labels = [];
    if (value is List) {
      for (final item in value) {
        final v = item?.toString().trim() ?? '';
        if (v.isNotEmpty) labels.add(v);
      }
    } else if (value is String && value.trim().isNotEmpty) {
      final plain = value.trim();
      try {
        final parsed = jsonDecode(plain);
        if (parsed is List) {
          for (final item in parsed) {
            final v = item?.toString().trim() ?? '';
            if (v.isNotEmpty) labels.add(v);
          }
        } else if (parsed is String) {
          labels.add(parsed.trim());
        } else {
          if (plain.contains('+')) {
            labels.addAll(
              plain.split('+').map((e) => e.trim()).where((e) => e.isNotEmpty),
            );
          } else {
            labels.add(plain);
          }
        }
      } catch (_) {
        if (plain.contains('+')) {
          labels.addAll(
            plain.split('+').map((e) => e.trim()).where((e) => e.isNotEmpty),
          );
        } else {
          labels.add(plain);
        }
      }
    }
    return labels
        .where((e) => {'เช้า', 'กลางวัน', 'เย็น'}.contains(e))
        .toList();
  }

  void _refreshMealWindowState({dynamic mealValue}) {
    try {
      final dynamic rawMeal =
          mealValue ??
          (_auth.tempSelections?['meal'] ??
              _auth.guestSelections?['meal'] ??
              _auth.user?['meal']);
      final List<String> planned = _parsePlannedMeals(rawMeal);
      final now = DateTime.now().toUtc().add(const Duration(hours: 7));
      final midnight = DateTime(now.year, now.month, now.day + 1, 0, 0);
      if (_lockUntil != null && now.isBefore(_lockUntil!)) {
        final secondsToLockEnd = _lockUntil!.difference(now).inSeconds;
        _clearInputControllers();
        setState(() {
          _mealWindowLocked = true;
          _fieldsLocked = true;
        });
        if (secondsToLockEnd > 0) {
          _startCountdown(secondsToLockEnd);
        } else {
          _stopCountdown();
        }
        return;
      }
      if (_lockUntil != null && now.isAfter(_lockUntil!)) {
        _lockUntil = null;
      }
      final windows = <String, DateTime>{
        'เช้า': DateTime(now.year, now.month, now.day, 5, 0),
        'กลางวัน': DateTime(now.year, now.month, now.day, 10, 0),
        'เย็น': DateTime(now.year, now.month, now.day, 15, 0),
      };
      final deadlines = <String, DateTime>{
        'เช้า': DateTime(now.year, now.month, now.day, 9, 59, 59),
        'กลางวัน': DateTime(now.year, now.month, now.day, 14, 59, 59),
        'เย็น': DateTime(now.year, now.month, now.day, 20, 59, 59),
      };

      setState(() {
        _plannedMeals = planned;
        _mealWindowLocked = false;
        _fieldsLocked = false;
      });

      if (planned.isEmpty) {
        if (_lockUntil != null && now.isBefore(_lockUntil!)) {
          final secondsToLockEnd = _lockUntil!.difference(now).inSeconds;
          setState(() {
            _mealWindowLocked = true;
            _fieldsLocked = true;
          });
          if (secondsToLockEnd > 0) {
            _startCountdown(secondsToLockEnd);
          } else {
            _stopCountdown();
          }
          return;
        }

        final secondsToMidnight = midnight.difference(now).inSeconds;
        if (secondsToMidnight > 0) {
          _startCountdown(secondsToMidnight);
        } else {
          _stopCountdown();
        }
        return;
      }

      final orderedMeals = ['เช้า', 'กลางวัน', 'เย็น'];
      String? nextMessage;
      DateTime? countdownTarget;
      String? activeMeal;
      bool inputAllowed = false;

      final currentMeal = _currentThaiMeal(now);
      if (currentMeal != null && planned.contains(currentMeal)) {
        final currentStart = windows[currentMeal]!;
        final currentEnd = deadlines[currentMeal]!;
        if (_isWithinWindow(now, currentStart, currentEnd)) {
          nextMessage = 'มื้อ$currentMeal เปิดอยู่';
          countdownTarget = currentEnd;
          activeMeal = currentMeal;
          inputAllowed = true;
        }
      }

      if (!inputAllowed) {
        if (_lockUntil != null && now.isBefore(_lockUntil!)) {
          nextMessage = 'บันทึกแล้ว รอเปิดมื้อถัดไป';
          countdownTarget = _lockUntil;
          activeMeal = null;
        } else {
          for (final meal in orderedMeals) {
            if (!planned.contains(meal)) continue;
            final startAt = windows[meal];
            if (startAt == null) continue;
            if (now.isBefore(startAt)) {
              nextMessage = 'มื้อ$meal จะเปิดใน';
              countdownTarget = startAt;
              activeMeal = null;
              break;
            }
          }
        }
      }

      if (!inputAllowed && (nextMessage == null || countdownTarget == null)) {
        nextMessage = 'หมดเวลากรอกแล้วสรุปผลตอนเที่ยงคืน';
        countdownTarget = midnight;
        activeMeal = null;
      }

      final seconds = countdownTarget != null
          ? countdownTarget.difference(now).inSeconds
          : 0;
      if (seconds > 0) {
        _startCountdown(seconds);
      } else {
        _stopCountdown();
      }

      final shouldClear =
          (activeMeal != null &&
          _activeMealLabel != null &&
          activeMeal != _activeMealLabel);
      if (shouldClear || (!inputAllowed && planned.isNotEmpty)) {
        _clearInputControllers();
      }

      setState(() {
        _mealWindowLocked = !inputAllowed;
        _fieldsLocked = !inputAllowed;
        _activeMealLabel = activeMeal;
      });
    } catch (e) {
      if (kDebugMode) print('refreshMealWindowState error: $e');
    }
  }

  Future<void> _restoreLockStateFromServer() async {
    /// Fetch the current selection from server and restore lock state if needed
    try {
      final token = _auth.token;
      if (token == null || token.isEmpty) return;

      // Fetch current user selections from server
      final res = await api.get(
        '/user-selections',
        timeoutSeconds: 8,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final List<dynamic> selections = jsonDecode(res.body) as List<dynamic>;
        if (selections.isEmpty) return;

        // Get the most recent selection
        final mostRecent = selections.isNotEmpty
            ? selections.first as Map<String, dynamic>
            : null;
        if (mostRecent == null) return;

        final String? nextMealOpenAt = mostRecent['next_meal_open_at']
            ?.toString();

        // 🔴 FIX: เรียกคืนชื่ออาหารไทยจาก API และแสดงใน TextEditingController
        String foodNameTh = (mostRecent['food_name_th']?.toString() ?? '')
            .trim();
        String dessertNameTh = (mostRecent['dessert_name_th']?.toString() ?? '')
            .trim();
        String drinkNameTh = (mostRecent['drink_name_th']?.toString() ?? '')
            .trim();

        _refreshMealWindowState(mealValue: mostRecent['meal']);
        if (_plannedMeals.isNotEmpty) {
          if (foodNameTh.isNotEmpty) foodController.text = foodNameTh;
          if (dessertNameTh.isNotEmpty) dessertController.text = dessertNameTh;
          if (drinkNameTh.isNotEmpty) drinkController.text = drinkNameTh;
          // Do not forcibly unlock when planned meals exist. The active meal window
          // should decide whether editing is allowed.
        }

        if (nextMealOpenAt != null && nextMealOpenAt.isNotEmpty) {
          try {
            final parsed = DateTime.parse(nextMealOpenAt);
            _lockUntil = parsed.toUtc().add(const Duration(hours: 7));
            final now = DateTime.now().toUtc().add(const Duration(hours: 7));
            if (_lockUntil != null && _lockUntil!.isAfter(now)) {
              int secs = _lockUntil!.difference(now).inSeconds;
              if (secs < 0) secs = 0;
              setState(() {
                _fieldsLocked = true;
                if (foodNameTh.isNotEmpty) foodController.text = foodNameTh;
                if (dessertNameTh.isNotEmpty) {
                  dessertController.text = dessertNameTh;
                }
                if (drinkNameTh.isNotEmpty) drinkController.text = drinkNameTh;
              });
              _startCountdown(secs);
            } else {
              _lockUntil = null;
              setState(() {
                _fieldsLocked = false;
                if (foodNameTh.isNotEmpty) foodController.text = foodNameTh;
                if (dessertNameTh.isNotEmpty) {
                  dessertController.text = dessertNameTh;
                }
                if (drinkNameTh.isNotEmpty) drinkController.text = drinkNameTh;
              });
              _stopCountdown();
            }
            // Refresh authoritative state from server
            await _pollMealWindowState();
          } catch (e) {
            if (kDebugMode) print('Error parsing next_meal_open_at: $e');
          }
        } else {
          setState(() {
            _fieldsLocked = false;
            if (foodNameTh.isNotEmpty) foodController.text = foodNameTh;
            if (dessertNameTh.isNotEmpty) {
              dessertController.text = dessertNameTh;
            }
            if (drinkNameTh.isNotEmpty) drinkController.text = drinkNameTh;
          });
          _stopCountdown();
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error restoring lock state: $e');
    }
  }

  Future<void> _saveSelection() async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });
    try {
      final int fqty = _getEffectiveQuantity(selectedFoodQty, foodQuantity);
      final int dqty = _getEffectiveQuantity(selectedDessertQty, dessertQuantity);
      final int drqty = _getEffectiveQuantity(selectedDrinkQty, drinkQuantity);
      final int fcal = calculatedFoodCalories != null
          ? calculatedFoodCalories!.toInt()
          : (selectedFoodMenuCalories ?? 0) * fqty;
      final int dcal = calculatedDessertCalories != null
          ? calculatedDessertCalories!.toInt()
          : (selectedDessertMenuCalories ?? 0) * dqty;
      final int drcal = calculatedDrinkCalories != null
          ? calculatedDrinkCalories!.toInt()
          : (selectedDrinkMenuCalories ?? 0) * drqty;
      final int total = fcal + dcal + drcal;

      // 🔴 FIX: เสมอดึงชื่ออาหารจาก TextEditingController เพื่อไม่ให้เป็นค่าว่าง
      String foodNameTh = foodController.text.trim();
      String drinkNameTh = drinkController.text.trim();
      String dessertNameTh = dessertController.text.trim();

      final List<String> plannedLabels = _plannedMeals.isNotEmpty
          ? _plannedMeals
          : _parsePlannedMeals(
              (_auth.tempSelections?['meal'] ??
                  _auth.guestSelections?['meal'] ??
                  _auth.user?['meal']),
            );
      final String? currentMealLabel =
          _resolveMealLabelForCurrentWindow(plannedLabels) ??
          _activeMealLabel ??
          (plannedLabels.isNotEmpty ? plannedLabels.first : null);
      final dynamic mealPayload = plannedLabels.isNotEmpty
          ? plannedLabels
          : (currentMealLabel != null ? [currentMealLabel] : '');

      final payload = {
        'duration': _planDurationInt ?? 1,
        'meal': mealPayload,
        'submission_meal': currentMealLabel,
        'menu_id': selectedFoodMenuId ?? 0,
        'dessert_menu_id': selectedDessertId ?? 0,
        'drink_menu_id': selectedDrinkMenuId ?? 0,
        'food_type_id': selectedFoodTypeId ?? 0,
        'category_id': selectedCategoryId ?? 0,
        'drink_type_id': selectedDrinkTypeId ?? 0,
        // Use canonical keys expected by backend: 'calories','sugar','sodium'
        'calories': total,
        'plan_calories_goal': _planCaloriesGoalInt ?? 0,
        // Sum per-category sugar/sodium (mirrors how `total` sums fcal+dcal+drcal above)
        // instead of using adjustedSugar/adjustedSodium, which only ever reflect
        // whichever single item's safety check ran most recently.
        'sugar': _getTotalSelectedSugar(),
        'sodium': _getTotalSelectedSodium(),
        'used_swap': (swapSuggestion != null),
        // เปิดใช้การล็อคช่วงเวลามื้ออาหารฝั่งเซิร์ฟเวอร์จริง (เดิมปิดไว้ตามการตัดสินใจ
        // ของโปรดักต์รอบก่อน — ตอนนี้เปิดใช้แล้วตามที่กำหนด)
        'enforce_meal_window': true,
        // Send quantity and unit metadata for each category
        'food_quantity': selectedFoodQty ?? 1,
        'food_unit': selectedFoodUnit,
        'dessert_quantity': selectedDessertQty ?? 1,
        'dessert_unit': selectedDessertUnit,
        'drink_quantity': selectedDrinkQty ?? 1,
        'drink_unit': selectedDrinkUnit,
        // 🔴 FIX: ส่งชื่ออาหารไทยจาก TextEditingController เสมอ ไม่ใช่ค่าว่าง
        'food_name_th': foodNameTh,
        'dessert_name_th': dessertNameTh,
        'drink_name_th': drinkNameTh,
      };

      final res = await api.post(
        '/save-selection',
        body: payload,
        timeoutSeconds: 12,
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        // Backend returns `is_fulllock` and optionally `next_meal_open_at` and `jump_to_summary`.
        try {
          // 🔴 FIX: อัปเดตค่าชื่ออาหารจาก response และรักษาค่าไว้ในช่องกรอกเมื่อหน้าจอถูกล็อก
          try {
            setState(() {
              // ใช้ค่าจาก response หากอนุญาต ลงถึง payload ที่ส่งได้
              foodController.text =
                  (body['food_name_th'] ?? payload['food_name_th'] ?? '')
                      .toString()
                      .trim();
              dessertController.text =
                  (body['dessert_name_th'] ?? payload['dessert_name_th'] ?? '')
                      .toString()
                      .trim();
              drinkController.text =
                  (body['drink_name_th'] ?? payload['drink_name_th'] ?? '')
                      .toString()
                      .trim();
              // persist per-item calories to show immediately
              selectedFoodMenuCalories = (calculatedFoodCalories != null)
                  ? calculatedFoodCalories!.toInt()
                  : (selectedFoodMenuCalories ?? 0);
              selectedDessertMenuCalories = (calculatedDessertCalories != null)
                  ? calculatedDessertCalories!.toInt()
                  : (selectedDessertMenuCalories ?? 0);
              selectedDrinkMenuCalories = (calculatedDrinkCalories != null)
                  ? calculatedDrinkCalories!.toInt()
                  : (selectedDrinkMenuCalories ?? 0);
            });
          } catch (_) {}
          // Persist server-returned selection fields into AuthService tempSelections
          try {
            final Map<String, dynamic> mergedSels = {};
            if (_auth.tempSelections != null) mergedSels.addAll(_auth.tempSelections!);
            // copy keys from response body
            if (body.containsKey('meal')) mergedSels['meal'] = body['meal'];
            if (body.containsKey('duration')) mergedSels['duration'] = body['duration'];
            if (body.containsKey('food_name_th')) mergedSels['food_name_th'] = body['food_name_th'];
            if (body.containsKey('dessert_name_th')) mergedSels['dessert_name_th'] = body['dessert_name_th'];
            if (body.containsKey('drink_name_th')) mergedSels['drink_name_th'] = body['drink_name_th'];
            if (body.containsKey('menu_id')) mergedSels['menu_id'] = body['menu_id'];
            if (body.containsKey('dessert_menu_id')) mergedSels['dessert_menu_id'] = body['dessert_menu_id'];
            if (body.containsKey('drink_menu_id')) mergedSels['drink_menu_id'] = body['drink_menu_id'];
            if (body.containsKey('category_id')) mergedSels['category_id'] = body['category_id'];
            if (body.containsKey('food_type_id')) mergedSels['food_type_id'] = body['food_type_id'];
            _auth.setTempSelections(mergedSels);
          } catch (_) {}
          _stopCountdown();
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('บันทึกสำเร็จ')));
          }
          final now = DateTime.now().toUtc().add(const Duration(hours: 7));
          final nextOpen = _nextPlannedMealOpenAt(plannedLabels, now);
          if (nextOpen != null) {
            _lockUntil = nextOpen;
          } else {
            _lockUntil = DateTime(now.year, now.month, now.day, 23, 59, 59);
          }
          _refreshMealWindowState(mealValue: plannedLabels);
          if (_lockUntil == null) {
            final now = DateTime.now().toUtc().add(const Duration(hours: 7));
            _lockUntil = DateTime(now.year, now.month, now.day, 23, 59, 59);
          }
          final Map<String, dynamic> mergedSels = {};
          if (_auth.tempSelections != null) mergedSels.addAll(_auth.tempSelections!);
          mergedSels['lock_until'] = _lockUntil?.toIso8601String();
          try {
            _auth.setTempSelections(mergedSels);
          } catch (_) {}
          if (_lockUntil != null) {
            final secondsToLock = _lockUntil!.difference(DateTime.now().toUtc().add(const Duration(hours: 7))).inSeconds;
            if (secondsToLock > 0) _startCountdown(secondsToLock);
          }
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => SelectionSummaryPage(
                  meal: currentMealLabel ?? plannedLabels.join(', '),
                  duration: _planDurationInt ?? 1,
                  foodName: foodController.text.trim(),
                  dessertName: dessertController.text.trim(),
                  drinkName: drinkController.text.trim(),
                  totalCalories: total,
                ),
              ),
            );
          }
        } catch (e) {
          if (kDebugMode) print('saveSelection parse error: $e');
          if (mounted) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('ข้อผิดพลาด'),
                content: const Text('ตอบกลับจากเซิร์ฟเวอร์ไม่ถูกต้อง'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ตกลง'),
                  ),
                ],
              ),
            );
          }
        }
      } else {
        final Map<String, dynamic> body = res.body.isNotEmpty
            ? jsonDecode(res.body)
            : {};
        final msg = body['message'] ?? body['error'] ?? 'ไม่สามารถบันทึกได้';
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('บันทึกไม่สำเร็จ'),
              content: Text(msg.toString()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ตกลง'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print('saveSelection error: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('ข้อผิดพลาด'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() {
        _saving = false;
      });
    }
  }

  void _recomputeSelectedCalories() {
    try {
      final int fcal = (selectedFoodMenuCalories ?? 0) * (foodQuantity);
      final int dcal = (selectedDessertMenuCalories ?? 0) * (dessertQuantity);
      final int drcal = (selectedDrinkMenuCalories ?? 0) * (drinkQuantity);
      final total = (fcal + dcal + drcal).toDouble();
      setState(() {
        calculatedFoodCalories = fcal.toDouble();
        calculatedDessertCalories = dcal.toDouble();
        calculatedDrinkCalories = drcal.toDouble();
        if (_perMealQuota != null) {
          _overQuota = total > (_perMealQuota ?? double.infinity);
        } else {
          _overQuota = false;
        }

        // health goal simple heuristic: if user aims to lose weight (contains 'ลด')
        // and chosen calories exceed 90% of per-meal quota, show suggestion
        try {
          _healthGoalWarning = null;
          final up = _auth.user ?? {};
          final hg = (up['health_goal'] ?? '').toString().toLowerCase();
          final hgg = (up['health_goal_group'] ?? '').toString().toLowerCase();
          final hgd = (up['health_goal_drink'] ?? '').toString().toLowerCase();
          final hgdtypes = (up['health_goal_drink_types'] ?? '')
              .toString()
              .toLowerCase();

          if (hg.contains('ลด') &&
              _perMealQuota != null &&
              total > (_perMealQuota! * 0.9)) {
            _healthGoalWarning =
                'เมนูนี้อาจไม่สอดคล้องกับเป้าหมายสุขภาพของคุณ ควรเลือกเมนูแคลอรีต่ำลง';
          }

          // Check food group suggestion: if user has set a preferred group and the typed food doesn't include it, suggest
          try {
            if (hgg.isNotEmpty && foodController.text.trim().isNotEmpty) {
              final ftxt = foodController.text.toLowerCase();
              if (!ftxt.contains(hgg)) {
                _healthGoalWarning =
                    'คำแนะนำ: เป้าหมายของคุณคือ "$hgg" — พิจารณาเลือกรายการที่สอดคล้องกับกลุ่มนี้';
              }
            }
          } catch (_) {}

          // Check drink-specific goals: if user expects certain drink types and the chosen drink doesn't match
          try {
            if (hgd.isNotEmpty && drinkController.text.trim().isNotEmpty) {
              final dtxt = drinkController.text.toLowerCase();
              if (hgdtypes.isNotEmpty) {
                final parts = hgdtypes
                    .split(RegExp(r'[;,\|/]'))
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final matches = parts.any((p) => dtxt.contains(p));
                if (!matches) {
                  _healthGoalWarning =
                      'คำแนะนำ: สำหรับเป้าหมายเครื่องดื่มของคุณ ควรเลือกเครื่องดื่มประเภท: ${parts.join(', ')}';
                }
              } else if (!dtxt.contains(hgd)) {
                _healthGoalWarning =
                    'คำแนะนำ: เครื่องดื่มนี้อาจไม่สอดคล้องกับเป้าหมายของคุณ';
              }
            }
          } catch (_) {}
        } catch (e) {
          if (kDebugMode) print('healthGoal check error: $e');
        }
      });
    } catch (e) {
      if (kDebugMode) print('Recompute calories error: $e');
    }
  }

  String _firstChoice(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    // split on common separators and take first non-empty part
    final parts = t
        .split(RegExp(r"[\/|,;]"))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) return parts.first;
    return t;
  }

  @override
  void dispose() {
    try {
      foodTypeController.dispose();
      categoryController.dispose();
      foodMenuController.dispose();
      dessertMenuController.dispose();
      _thumbnailDebounceFood?.cancel();
      drinkTypeController.dispose();
      drinkMenuController.dispose();
      foodController.dispose();
      dessertController.dispose();
      drinkController.dispose();
      _realtimeDebounceFood?.cancel();
      _realtimeDebounceDessert?.cancel();
      _realtimeDebounceDrink?.cancel();
      _thumbnailDebounceDrink?.cancel();
      _searchDebounce?.cancel();
      _countdownTimer?.cancel();
      _thaiClockTimer?.cancel();
      _statusPollTimer?.cancel();
      _midnightRedirectTimer
          ?.cancel(); // 🚨 สำคัญมาก: ต้อง cancel ไทเมอร์ทุกครั้งที่ออกจากหน้านี้ เพื่อป้องกัน Memory Leak
      try {
        _auth.removeListener(_authListener);
      } catch (e) {
        if (kDebugMode) print('Failed to remove auth listener: $e');
      }
    } catch (e) {
      if (kDebugMode) print('Dispose error in ChooseFoodTypePage: $e');
    }
    super.dispose();
  }

  Future<Map<String, dynamic>?> _fetchRandomMenuFromAI(String category) async {
    try {
      final ApiResponse res = await api.post(
        '/api/ai/random',
        body: {'category': category},
      );
      if (res.statusCode != 200 || res.body.isEmpty) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      return {
        'menu_name': decoded['menu_name']?.toString() ?? '',
        'portion_size': decoded['portion_size']?.toString() ?? '',
        'calories': decoded['calories'],
        'image_url': decoded['image_url']?.toString() ?? '',
      };
    } catch (e) {
      if (kDebugMode) print('[ChooseFoodTypePage] fetchRandomMenuFromAI error: $e');
      return null;
    }
  }

  void _ensurePortionUnitExists(String category, String portionSize) {
    if (portionSize.trim().isEmpty) return;
    final list = category == 'dessert'
        ? dessertUnits
        : category == 'drink'
            ? drinkUnits
            : foodUnits;
    if (!list.contains(portionSize)) {
      list.insert(0, portionSize);
    }
  }

  Future<void> _randomizeCategory(String category) async {
    if (!mounted) return;
    setState(() {
      if (category == 'dessert') {
        _isFetchingRandomDessert = true;
      } else if (category == 'drink') {
        _isFetchingRandomDrink = true;
      } else {
        _isFetchingRandomFood = true;
      }
    });

    try {
      final item = await _fetchRandomMenuFromAI(category);
      if (item == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ไม่สามารถสุ่มเมนู $category ได้ กรุณาลองใหม่อีกครั้ง'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
        return;
      }

      final menuName = item['menu_name']?.toString() ?? '';
      final portionSize = item['portion_size']?.toString() ?? '';
      final caloriesRaw = item['calories'];
      final String? imageUrl = (item['image_url']?.toString() ?? '').trim().isNotEmpty
          ? item['image_url']?.toString().trim()
          : null;
      final calories = caloriesRaw is num
          ? caloriesRaw.toDouble()
          : double.tryParse(caloriesRaw?.toString() ?? '') ?? 0.0;
      final caloriesInt = calories.round();

      final String keyName = menuName.trim();
      String? finalImageUrl;

      // Immediately update UI with the generated menu (no image yet)
      if (category == 'food') {
        _ensurePortionUnitExists('food', portionSize);
        final unit = portionSize.isNotEmpty ? portionSize : selectedFoodUnit;
        setState(() {
          foodController.text = menuName;
          matchedFood = {
            'id': 999999,
            'name': menuName,
            'calories': calories,
            'image_url': '',
          };
          selectedFoodQty = 1;
          selectedFoodUnit = unit;
          selectedFoodMenuCalories = caloriesInt;
          foodImageUrl = null;
          calculatedFoodCalories = calories;
          foodError = _validateNutritionAndGoal(
            text: menuName,
            category: 'อาหารคาว',
            quantity: 1,
            unit: unit,
            computedCalories: calories,
          );
          foodAdvice = null;
          isSafetyChecked = true;
          isFoodSafe = true;
          _foodSafetyOk = true;
        });
        // ponytail: the controller.text assignment above fires the field's
        // onChanged, which schedules a manual-search debounce that would
        // clobber this random pick's image once it fires. Cancel it.
        _realtimeDebounceFood?.cancel();
      } else if (category == 'dessert') {
        _ensurePortionUnitExists('dessert', portionSize);
        final unit = portionSize.isNotEmpty ? portionSize : selectedDessertUnit;
        setState(() {
          dessertController.text = menuName;
          matchedDessert = {
            'id': 999998,
            'name': menuName,
            'calories': calories,
            'image_url': '',
          };
          selectedDessertQty = 1;
          selectedDessertUnit = unit;
          selectedDessertMenuCalories = caloriesInt;
          dessertImageUrl = null;
          calculatedDessertCalories = calories;
          dessertError = _validateNutritionAndGoal(
            text: menuName,
            category: 'ของหวาน',
            quantity: 1,
            unit: unit,
            computedCalories: calories,
          );
          dessertAdvice = null;
          isSafetyChecked = true;
          isFoodSafe = true;
        });
        _realtimeDebounceDessert?.cancel();
      } else {
        _ensurePortionUnitExists('drink', portionSize);
        final unit = portionSize.isNotEmpty ? portionSize : selectedDrinkUnit;
        setState(() {
          drinkController.text = menuName;
          matchedDrink = {
            'id': 999997,
            'name': menuName,
            'calories': calories,
            'image_url': '',
          };
          selectedDrinkQty = 1;
          selectedDrinkUnit = unit;
          selectedDrinkMenuCalories = caloriesInt;
          drinkImageUrl = null;
          calculatedDrinkCalories = calories;
          drinkError = _validateNutritionAndGoal(
            text: menuName,
            category: 'เครื่องดื่ม',
            quantity: 1,
            unit: unit,
            computedCalories: calories,
          );
          drinkAdvice = null;
          isSafetyChecked = true;
          isFoodSafe = true;
          _drinkSafetyOk = true;
        });
        _realtimeDebounceDrink?.cancel();
      }

      // then load image async and update when available
      if (_imageCache.containsKey(keyName)) {
        finalImageUrl = _imageCache[keyName];
      } else {
        final String? pexelsImage = (imageUrl != null && imageUrl.trim().isNotEmpty)
            ? imageUrl.trim()
            : await _fetchPexelsImage(
                menuName,
                categoryHint: category == 'dessert'
                    ? 'sweet dessert'
                    : category == 'drink'
                        ? 'beverage drink'
                        : 'thai food',
              );

        final String? apiImageFallback = (pexelsImage == null || pexelsImage.trim().isEmpty)
            ? await _fetchImageUrl(menuName)
            : pexelsImage;

        if (apiImageFallback != null && apiImageFallback.trim().isNotEmpty) {
          finalImageUrl = apiImageFallback.trim();
        } else {
          try {
            if (kDebugMode) print('[ImageFetch] no pexels/backend image, requesting backend debug for: $menuName');
            final resp = await api.get('/api/food-image?name=${Uri.encodeComponent(menuName)}&debug=1');
            if (resp.statusCode == 200) {
              final j = json.decode(resp.body);
              if (j is Map) {
                if (kDebugMode) print('[ImageFetch] backend debug attempts: ${j['attempts'] ?? j}');
                final maybe = (j['image_url'] ?? '')?.toString();
                if (maybe != null && maybe.trim().isNotEmpty) finalImageUrl = maybe.trim();
              }
            }
          } catch (e) {
            if (kDebugMode) print('[ImageFetch] backend debug call failed: $e');
          }
        }

        _imageCache[keyName] = finalImageUrl;
      }

      if (finalImageUrl != null && finalImageUrl.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
          if (category == 'food') {
            foodImageUrl = finalImageUrl;
            matchedFood?['image_url'] = finalImageUrl;
          } else if (category == 'dessert') {
            dessertImageUrl = finalImageUrl;
            matchedDessert?['image_url'] = finalImageUrl;
          } else {
            drinkImageUrl = finalImageUrl;
            matchedDrink?['image_url'] = finalImageUrl;
          }
        });
        }
      }

      if (category == 'food') {
        _ensurePortionUnitExists('food', portionSize);
        final unit = portionSize.isNotEmpty ? portionSize : selectedFoodUnit;
        setState(() {
          foodController.text = menuName;
          matchedFood = {
            'id': 999999,
            'name': menuName,
            'calories': calories,
            'image_url': finalImageUrl ?? '',
          };
          selectedFoodQty = 1;
          selectedFoodUnit = unit;
          selectedFoodMenuCalories = caloriesInt;
          foodImageUrl = finalImageUrl;
          calculatedFoodCalories = calories;
          foodError = _validateNutritionAndGoal(
            text: menuName,
            category: 'อาหารคาว',
            quantity: 1,
            unit: unit,
            computedCalories: calories,
          );
          foodAdvice = null;
          isSafetyChecked = true;
          isFoodSafe = true;
          _foodSafetyOk = true;
        });
      } else if (category == 'dessert') {
        _ensurePortionUnitExists('dessert', portionSize);
        final unit = portionSize.isNotEmpty ? portionSize : selectedDessertUnit;
        setState(() {
          dessertController.text = menuName;
          matchedDessert = {
            'id': 999998,
            'name': menuName,
            'calories': calories,
            'image_url': finalImageUrl ?? '',
          };
          selectedDessertQty = 1;
          selectedDessertUnit = unit;
          selectedDessertMenuCalories = caloriesInt;
          dessertImageUrl = finalImageUrl;
          calculatedDessertCalories = calories;
          dessertError = _validateNutritionAndGoal(
            text: menuName,
            category: 'ของหวาน',
            quantity: 1,
            unit: unit,
            computedCalories: calories,
          );
          dessertAdvice = null;
          isSafetyChecked = true;
          isFoodSafe = true;
        });
      } else {
        _ensurePortionUnitExists('drink', portionSize);
        final unit = portionSize.isNotEmpty ? portionSize : selectedDrinkUnit;
        setState(() {
          drinkController.text = menuName;
          matchedDrink = {
            'id': 999997,
            'name': menuName,
            'calories': calories,
            'image_url': finalImageUrl ?? '',
          };
          selectedDrinkQty = 1;
          selectedDrinkUnit = unit;
          selectedDrinkMenuCalories = caloriesInt;
          drinkImageUrl = finalImageUrl;
          calculatedDrinkCalories = calories;
          drinkError = _validateNutritionAndGoal(
            text: menuName,
            category: 'เครื่องดื่ม',
            quantity: 1,
            unit: unit,
            computedCalories: calories,
          );
          drinkAdvice = null;
          isSafetyChecked = true;
          isFoodSafe = true;
          _drinkSafetyOk = true;
        });
      }

      _computeGiAndSatiety();
      _applyComboFilters();
    } finally {
      if (mounted) {
        setState(() {
          if (category == 'dessert') {
            _isFetchingRandomDessert = false;
          } else if (category == 'drink') {
            _isFetchingRandomDrink = false;
          } else {
            _isFetchingRandomFood = false;
          }
        });
      }
    }
  }

  Future<void> _randomizeAllCategories() async {
    if (!mounted) return;
    await Future.wait([
      _randomizeCategory('food'),
      _randomizeCategory('drink'),
      _randomizeCategory('dessert'),
    ]);
  }

  /// Translates Thai text to English using Google Translator
  /// Returns the translated text if successful, otherwise returns the original text
  Future<String> _translateThaiToEnglish(String text) async {
    try {
      final bool hasThai = RegExp(r'[\u0E00-\u0E7F]').hasMatch(text);
      
      // Only translate if the text contains Thai characters
      if (!hasThai) {
        return text;
      }
      
      final translator = GoogleTranslator();
      var translation = await translator.translate(
        text,
        from: 'th',
        to: 'en',
      );
      
      if (kDebugMode) {
        print('[ChooseFoodTypePage] Translated "$text" to "${translation.text}"');
      }
      
      return translation.text;
    } catch (e) {
      if (kDebugMode) {
        print('[ChooseFoodTypePage] Translation error: $e - using fallback');
      }
      // Return original text if translation fails
      return text;
    }
  }

  /// Mapping of Thai dish names to proper English names/transliterations
  /// for accurate Pexels image search
  static final Map<String, String> thaiDishMapping = {
    // Savory dishes (อาหารคาว)
    'ข้าวมันไก่': 'Khao Man Gai poached steamed chicken white rice cucumber',
    'ไข่เจียว': 'Thai yellow fried rice scrambled egg',
    'ผัดกะเพรา': 'Pad Krapow minced pork holy basil Thai',
    'ส้มตำ': 'Som Tam papaya salad spicy lime Thai',
    'ก๋วยเตี๋ยว': 'Pad Thai thin rice noodles shrimp',
    'ราดหน้า': 'Rad Na Thai thick gravy noodles',
    'ผัดซีอิ๊ว': 'Pad See Ew wide flat noodles soy Thai',
    'ชาบู': 'Thai hot pot shabu shabu broth',
    'หมูกระทะ': 'Thai pork hot plate',
    'ต้มยำ': 'Tom Yum Thai hot sour soup',
    'ต้มเลือด': 'Tom Lhuad Thai blood soup',
    'ผัดไทย': 'Pad Thai stir fried rice noodles',
    'ก๋วยจั๊บ': 'Kuai Chap rice noodle soup',
    'เนื้อย่าง': 'Thai grilled beef lemongrass',
    'หมูย่าง': 'Thai grilled pork satay',
    'ไก่ย่าง': 'Thai grilled chicken marinated',
    'ปลาย่าง': 'Thai grilled fish',
    'ปลาเค็ม': 'Thai salted fish',
    'สตูแกง': 'Thai curry',
    'แกงเขียวหวาน': 'Thai green curry with chicken',
    'แกงแดง': 'Thai red curry paste',
    'แกงเหลือง': 'Thai yellow curry',
    'แกงมัสมั่น': 'Thai massaman curry beef',
    'แกงป่า': 'Thai panang curry',
    'ข้าวขาหมู': 'Khao Kha Moo pork leg rice',
    'ข้าวหมกไก่': 'Khao Mok Gai chicken rice',
    'ข้าวมันเป็ด': 'Khao Man Ped duck rice',
    'ลาบ': 'Larb Thai spicy minced meat salad',
    'ยำ': 'Yum Thai spicy salad',
    'แตงโม': 'Thai watermelon',
    'น้ำพริกอ่อง': 'Nam Prik Thai spicy dip',
    'ส่วนแบ่ง': 'Thai shared dish',
    // Desserts (ของหวาน)
    'ข้าวเหนียวมะม่วง': 'Khao Niao Mamuang sticky rice mango Thai dessert',
    'ขนมหวาน': 'Thai sweet dessert',
    'ชาเย็น': 'Thai iced sweet tea dessert',
    'ขนมไทย': 'Thai sweet snack traditional',
    'ขนมเบื้อง': 'Khao Beung Thai traditional dessert',
    'ส้มโอ': 'Thai pomelo grapefruit fruit',
    'ทุเรียน': 'Thai durian spiky fruit',
    'มะม่วง': 'Thai mango yellow fruit sweet',
    'มะละกอ': 'Thai papaya orange fruit',
    'ลำไย': 'Thai longans sweet fruit',
    'สตรอเบอร์รี่': 'Thai strawberry fresh fruit',
    'กล้วยทอด': 'Thai fried bananas honey sweet',
    'ขนมจีน': 'Thai sweet dessert noodles',
    'แครงลาดชา': 'Thai coconut milk dessert',
    'ขนมครกลูกช้าง': 'Thai sweet sticky dessert',
    'โครงสร้างน้ำแข็ง': 'Thai shaved ice dessert',
    // Non-alcoholic drinks (เครื่องดื่มไม่มีแอลกอฮอล์)
    'น้ำเปล่า': 'glass of water clear beverage',
    'น้ำตาล': 'Thai sugarcane juice fresh squeezed',
    'กาแฟ': 'Thai iced coffee dark beverage cup',
    'ชาไทย': 'Thai iced orange tea traditional',
    'นมสด': 'Thai fresh milk white beverage glass',
    'นม': 'Thai milk beverage glass white',
    'น้ำมะนาว': 'Fresh lime juice Thai lemonade',
    'น้ำส้ม': 'Thai fresh orange juice citrus',
  };

  Future<String?> _fetchPexelsImage(
    String query, {
    String categoryHint = 'food',
  }) async {
    if (query.trim().isEmpty) return null;
    try {
      final dio = Dio();
      dio.options.headers['Authorization'] = pexelsApiKey;

      final String base = query.trim();
      final bool hasThai = RegExp(r'[\u0E00-\u0E7F]').hasMatch(base);

      // 🌐 Check if the Thai input matches a known dish name first
      // If yes, use the mapped English name for better image results
      String searchBase = base;
      if (hasThai && thaiDishMapping.containsKey(base)) {
        searchBase = thaiDishMapping[base]!;
        if (kDebugMode) {
          print(
              '[ChooseFoodTypePage._fetchPexelsImage] Thai dish "$base" -> "$searchBase" (mapped)');
        }
      } else if (hasThai) {
        // For unmapped Thai dishes, translate using Google Translator
        searchBase = await _translateThaiToEnglish(base);
        if (kDebugMode) {
          print(
              '[ChooseFoodTypePage._fetchPexelsImage] Thai input "$base" -> "$searchBase" (translated)');
        }
      }

      // Build prioritized query variants to improve relevance.
      // Requirements implemented:
      // 1) Try exact popular-menu matches first.
      // 2) When using contains-like variants, prefer long/specific phrases
      //    and push short tokens (e.g. 'ไข่','ข้าว') to the end.
      // 3) If nothing else matches, try the raw trimmed food name first.
      final List<String> variants = [];

      // Check if input is a recognized popular/mapped dish
      bool isMappedDish = thaiDishMapping.containsKey(base);

      if (isMappedDish) {
        // For mapped Thai dishes, use aggressive specific search strategy
        // The mapped name already has good keywords (e.g., "Khao Man Gai steamed chicken rice plate")
        variants.add(searchBase); // Primary: full mapped term
        variants.add('$searchBase plate'); // Add "plate" to get plated dish images
        variants.add('$searchBase served'); // Add "served" for restaurant plating
        variants.add(searchBase.split(' ').take(2).join(' ')); // Main dish name (e.g., "Khao Man Gai")
        variants.add('$searchBase restaurant'); // Restaurant quality plating
      } else {
        // For non-mapped dishes, use standard strategy
        // Always try the raw trimmed name as the primary attempt so the
        // user's exact text is searched first (requirement #3).
        // If it was Thai, use the translated version
        variants.add(searchBase);

        // Tokenize and prepare contains-style variants. Generate all
        // contiguous substrings of the input tokens, sort them by length
        // (longer / more specific first) and append; short tokens like
        // single-word 'ไข่' or 'ข้าว' will naturally fall to the end.
        final List<String> toks = searchBase
            .split(RegExp(r'\s+'))
            .where((t) => t.trim().isNotEmpty)
            .toList();
        final List<String> substrings = [];
        for (int i = 0; i < toks.length; i++) {
          for (int j = i; j < toks.length; j++) {
            substrings.add(toks.sublist(i, j + 1).join(' '));
          }
        }
        // Remove duplicates and the full-base (already added)
        final uniq = <String>{};
        for (var s in substrings) {
          final trimmed = s.trim();
          if (trimmed.isEmpty) continue;
          if (trimmed == searchBase) continue;
          if (!uniq.contains(trimmed)) {
            uniq.add(trimmed);
          }
        }
        final List<String> orderedSub = uniq.toList()
          ..sort((a, b) => b.length.compareTo(a.length)); // longer first

        // Append ordered substrings with category hints
        for (var s in orderedSub) {
          // avoid promoting very short single-token queries too early
          variants.add('$s $categoryHint');
          variants.add(s);
        }
      }

      // Add English/intent hints for Thai queries, keep these lower priority
      // For mapped Thai dishes, the mapped value already includes context
      // For unmapped Thai dishes, enhance with category hints
      if (hasThai && searchBase != base) {
        // Only add extra hints if this wasn't from the dish mapping
        // (mapped dishes already have good keywords like "Khao Man Gai steamed chicken rice plate")
        if (!isMappedDish) {
          if (categoryHint.toLowerCase().contains('dessert')) {
            variants.add('$searchBase dessert');
            variants.add('$searchBase sweet dessert');
          } else if (categoryHint.toLowerCase().contains('drink') ||
              categoryHint.toLowerCase().contains('beverage')) {
            variants.add('$searchBase beverage');
            variants.add('$searchBase drink');
          } else {
            variants.add('$searchBase thai food');
            variants.add('$searchBase thai dish');
          }
        }
      }

      // As a final fallback, when the search base is long try shortened prefixes
      // But skip this for mapped dishes as their names are already optimized
      if (!isMappedDish) {
        final List<String> toks = searchBase
            .split(RegExp(r'\s+'))
            .where((t) => t.trim().isNotEmpty)
            .toList();
        if (toks.length >= 2) {
          variants.add(toks.take(2).join(' '));
          variants.add(toks.sublist(math.max(0, toks.length - 2)).join(' '));
        } else if (searchBase.length > 12) {
          variants.add(searchBase.substring(0, math.min(12, searchBase.length)));
        }
      }

      // Deduplicate preserving order
      final seen = <String>{};
      final queries = <String>[];
      for (var v in variants) {
        final s = v.trim();
        if (s.isEmpty) continue;
        if (!seen.contains(s)) {
          seen.add(s);
          queries.add(s);
        }
      }

      // Try each variant with slightly generous per_page and landscape orientation
      for (var q in queries) {
        try {
          final resp = await dio.get(
            'https://api.pexels.com/v1/search',
            queryParameters: {
              'query': q,
              'per_page': 3,
              'orientation': 'landscape',
            },
          );
          if (resp.statusCode == 200 && resp.data != null) {
            final List photos = resp.data['photos'] as List? ?? [];
            if (photos.isNotEmpty) {
              // pick best src: prefer 'landscape', then 'large', then 'original', then 'medium'
              Map? best;
              int bestScore = -1;
              for (var p in photos) {
                final src = p['src'] ?? {};
                int score = 0;
                if (src['landscape'] != null) score += 4;
                if (src['large'] != null) score += 3;
                if (src['original'] != null) score += 2;
                if (src['medium'] != null) score += 1;
                if (score > bestScore) {
                  bestScore = score;
                  best = p as Map;
                }
              }
              if (best != null) {
                final src = best['src'] ?? {};
                return (src['landscape'] ??
                        src['large'] ??
                        src['original'] ??
                        src['medium'])
                    ?.toString();
              }
            }
          }
        } catch (e) {
          if (kDebugMode) print('Pexels variant "$q" failed: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) print('Pexels fetch error: $e');
    }
    return null;
  }

  // Base calories mapping per unit
  double _getBaseCaloriesByUnit(String unit) {
    switch (unit) {
      case 'ถุง':
        return 350.0;
      case 'ชาม':
      case 'แก้ว':
        return 300.0;
      case 'จาน':
      case 'ถ้วย':
        return 250.0;
      case 'ขวด':
        return 200.0;
      case 'ชิ้น':
      case 'ตัว':
        return 150.0;
      case 'กระป๋อง':
        return 140.0;
      default:
        return 250.0;
    }
  }

  double _getUnitSizeMultiplier(String unit) {
    switch (unit) {
      case 'ถ้วย':
      case 'จาน':
      case 'แก้ว':
        return 1.0;
      case 'ชาม':
        return 1.2;
      case 'ถ้วยเล็ก':
        return 0.65;
      case 'ชิ้น':
      case 'ตัว':
        return 0.4;
      case 'ก้อน':
        return 0.8;
      case 'ลูก':
        return 0.5;
      case 'ถาด':
        return 1.4;
      case 'ขวด':
        return 1.0;
      case 'กระป๋อง':
        return 0.9;
      case 'ถุง':
        return 1.3;
      default:
        return 1.0;
    }
  }

  double _calculateMatchedItemCalories(
    Map<String, dynamic> item,
    String selectedUnit,
    int quantity,
  ) {
    final baseCal = _parseNumericValue(item['calories'] ?? item['kcal']);
    if (baseCal <= 0) {
      return _getBaseCaloriesByUnit(selectedUnit) * quantity;
    }

    final itemUnit = (item['unit'] as String?)?.trim() ?? '';
    final baselineFactor = itemUnit.isNotEmpty
        ? _getUnitSizeMultiplier(itemUnit)
        : _getUnitSizeMultiplier('ถ้วย');
    final selectedFactor = _getUnitSizeMultiplier(selectedUnit);
    final ratio = baselineFactor > 0 ? selectedFactor / baselineFactor : 1.0;
    return baseCal * ratio * quantity;
  }

  // Nutrition & health-goal validation using AuthService user profile
  String? _validateNutritionAndGoal({
    required String text,
    required String category,
    required int quantity,
    required String unit,
    required double computedCalories,
  }) {
    if (text.trim().isEmpty) return null;
    final textLower = text.toLowerCase().trim();

    final userProfile = _auth.user ?? {};
    // If validating a drink category, prefer the drink-specific health goal
    String healthGoal = '';
    try {
      if (category == 'เครื่องดื่ม') {
        final v = (userProfile['health_goal_drink'] ?? healthGoalDrink ?? '');
        healthGoal = v.toString().toLowerCase();
      } else {
        healthGoal = (userProfile['health_goal'] ?? '')
            .toString()
            .toLowerCase();
      }
    } catch (_) {
      healthGoal = (userProfile['health_goal'] ?? '').toString().toLowerCase();
    }
    String allergies =
        (userProfile['food_allergies'] ?? userProfile['allergies'] ?? '')
            .toString()
            .toLowerCase();
    if (allergies.trim() == 'null') allergies = '';
    String chronicDiseases = (userProfile['chronic_diseases'] ?? '')
        .toString()
        .toLowerCase();
    if (chronicDiseases.trim() == 'null') chronicDiseases = '';
    // Full allergy list, same split convention as the backend
    // (get_food_safety_message / /api/food-menus use `[,;\n]`), so every
    // allergy the user has on file is checked -- not just one hardcoded word.
    final allergyList = allergies
        .split(RegExp(r'[,;\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != 'ไม่มี' && e != 'none')
        .toList();

    // derive recommended calories and nutrient limits from user profile
    double recommendedCalories = 2000.0;
    try {
      final rc =
          userProfile['recommended_calories'] ??
          userProfile['recommendedCalories'] ??
          userProfile['recommendedCal'];
      if (rc != null) {
        recommendedCalories =
            double.tryParse(rc.toString()) ?? recommendedCalories;
      }
    } catch (_) {}

    // (no local display vars here — summary card computes display values separately)
    final double perSnackThreshold =
        recommendedCalories / 6.0; // snack-like threshold
    final double perMealThreshold =
        recommendedCalories / 3.0; // per-meal threshold

    // Prevent category mismatches
    if (category == 'อาหารคาว') {
      final dessertWords = [
        'บัวลอย',
        'ทองหยิบ',
        'ฝอยทอง',
        'เค้ก',
        'ไอศกรีม',
        'ขนมหวาน',
        'โรตี',
        'มะม่วง',
        'ข้าวเหนียวมะม่วง',
      ];
      for (var word in dessertWords) {
        if (textLower.contains(word)) {
          return "กรุณาเขียนลงในช่องที่ถูกต้อง (เมนูนี้จัดอยู่ในหมวดหมู่ของหวาน)";
      }
        }
    }
    if (category == 'เครื่องดื่ม') {
      final foodWords = [
        'ข้าว',
        'ต้มยำ',
        'แกง',
        'ผัดกะเพรา',
        'บัวลอย',
        'เค้ก',
        'สเต็ก',
      ];
      for (var word in foodWords) {
        if (textLower.contains(word)) {
          return "กรุณาเขียนลงในช่องที่ถูกต้อง (เมนูนี้จัดอยู่ในหมวดหมู่อาหารหรือของหวาน)";
      }
        }
    }

    // Allergy checks — data-driven: check every allergy the user has on
    // file (not just a hardcoded shrimp keyword) as a substring against the
    // candidate menu name, mirroring the backend's split-and-check pattern.
    for (final a in allergyList) {
      if (textLower.contains(a)) {
        return "🚨 แจ้งเตือนอันตราย: เมนูนี้มีส่วนผสมของ$a ซึ่งขัดต่อประวัติการแพ้อาหารของคุณ!";
      }
    }

    // Chronic disease checks
    if (chronicDiseases.contains('เบาหวาน') ||
        chronicDiseases.contains('diabetes')) {
      if (category == 'ของหวาน' ||
          textLower.contains('ชานม') ||
          textLower.contains('น้ำอัดลม') ||
          textLower.contains('โค้ก')) {
        return "⚠️ คำแนะนำแพทย์: มีปริมาณน้ำตาลและค่า GI สูงเกินไป ไม่ปลอดภัยสำหรับผู้ป่วยโรคเบาหวาน";
      }
    }
    if (chronicDiseases.contains('ความดัน') ||
        chronicDiseases.contains('หัวใจ')) {
      if (textLower.contains('กาแฟ') ||
          textLower.contains('เอสเพรสโซ่') ||
          textLower.contains('เครื่องดื่มชูกำลัง')) {
        return "⚠️ คำแนะนำแพทย์: มีระดับคาเฟอีนเข้มข้น อาจส่งผลต่อความดันโลหิตหรืออัตราการเต้นของหัวใจ";
      }
    }

    // Goal-based guidance
    // For drinks, apply drink-specific goal rules when selected
    if (category == 'เครื่องดื่ม') {
      if (healthGoal.contains('ลดน้ำหนัก') || healthGoal.contains('loss')) {
        if (computedCalories > perSnackThreshold) {
          return "⚠️ เครื่องดื่มลดน้ำหนัก: พลังงานหรือน้ำตาลสูง แนะนำเครื่องดื่มน้ำเปล่าหรือน้ำหวานต่ำ";
        }
      }
      if (healthGoal.contains('เพิ่มพลังงาน') ||
          healthGoal.contains('ให้พลังงาน') ||
          healthGoal.contains('gain')) {
        if (computedCalories < (perSnackThreshold * 0.5)) {
          return "💡 เครื่องดื่มเพิ่มพลังงาน: พลังงานต่ำ แนะนำเลือกเครื่องดื่มที่ให้พลังงานมากขึ้น (เช่น นมหรือสมูทตี้โปรตีน)";
        }
      }
      // for general health-drink goals, prefer gentle suggestions (no hard reject)
    }
    if (healthGoal.contains('loss') ||
        healthGoal.contains('ลดน้ำหนัก') ||
        healthGoal.contains('fat_loss')) {
      if ((category == 'ของหวาน' || category == 'เครื่องดื่ม') &&
          computedCalories > perSnackThreshold) {
        return "⚠️ เกณฑ์ลดน้ำหนัก: พลังงานมื้อว่าง (${computedCalories.toStringAsFixed(0)} kcal) สูงเกินเกณฑ์ แนะนำให้ลดจำนวนหรือหน่วยลงครับ";
      }
      if (category == 'อาหารคาว' && computedCalories > perMealThreshold) {
        return "⚠️ เกณฑ์ลดน้ำหนัก: ปริมาณรวมให้พลังงานสูงเกิน ${perMealThreshold.toStringAsFixed(0)} kcal ไม่สอดคล้องกับเป้าหมายการควบคุมน้ำหนัก";
      }
    }

    if (healthGoal.contains('gain') || healthGoal.contains('เพิ่มกล้ามเนื้อ')) {
      final lowProteinItems = [
        'ข้าวเหนียวเปล่า',
        'เฟรนช์ฟรายส์',
        'มันทอด',
        'ตบแป้ง',
      ];
      for (var item in lowProteinItems) {
        if (textLower.contains(item)) {
          return "💡 แนะนำเพิ่มกล้ามเนื้อ: เมนูนี้มีโปรตีนต่ำ แนะนำให้เลือกรับประทานร่วมกับ อกไก่ หรือ ไข่ต้ม เพื่อเพิ่มสารอาหารโปรตีน";
      }
        }
    }

    return null;
  }

  // Reusable conditional nutrient input UI (simplified)
  Widget _buildConditionalNutrientField({
    String? label,
    TextEditingController? controller,
    String? validationError,
    String? imageUrl,
    required int quantity,
    required String selectedUnit,
    required List<String> unitList,
    required double? calculatedCalories,
    required String category,
    Function(String)? onChanged,
    required Function(int) onQuantityChanged,
    required Function(String) onUnitChanged,
  }) {
    final imageHeight = MediaQuery.of(context).size.height * 0.32;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller != null) ...[
          TextField(
            controller: controller,
            enabled: !_fieldsLocked,
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: label,
              errorText: validationError,
              errorStyle: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (imageUrl != null &&
            imageUrl.trim().isNotEmpty &&
            validationError == null &&
            ((controller == null) || controller.text.trim().isNotEmpty)) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      "จำนวน: ",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.red,
                      ),
                      onPressed: quantity > 1
                          ? () => onQuantityChanged(quantity - 1)
                          : null,
                    ),
                    Text(
                      '$quantity',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.green,
                      ),
                      onPressed: () => onQuantityChanged(quantity + 1),
                    ),
                    const Spacer(),
                    const Text(
                      "หน่วย: ",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      value: selectedUnit,
                      items: unitList
                          .map(
                            (String u) => DropdownMenuItem<String>(
                              value: u,
                              child: Text(u),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) onUnitChanged(val);
                      },
                    ),
                  ],
                ),
                if (calculatedCalories != null) ...[
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "ประเมินพลังงานตามเป้าหมายสุขภาพ:",
                        style: TextStyle(fontSize: 14, color: AppColors.inkSoft),
                      ),
                      Text(
                        "${calculatedCalories.toStringAsFixed(0)} kcal",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            height: imageHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: _buildSafeImage(
              imageUrl: imageUrl,
              width: double.infinity,
              height: imageHeight,
              fit: BoxFit.cover,
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  // Analyze and filter menu input (no-AI logic)
  Future<void> _showValidationWarningDialog(String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text(
              'อินพุตไม่ถูกต้อง',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'ตกลง',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _validateAndProcessInput(String input, String category) async {
    final text = input.trim();
    if (text.isEmpty) return;

    final pageType = category == 'food'
        ? 'อาหารคาว'
        : category == 'dessert'
        ? 'ของหวาน'
        : 'เครื่องดื่ม';
    try {
      final res = await api.post(
        '/api/validate_food_category',
        body: {'menu_name': text, 'page_type': pageType},
      );

      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['is_blocked'] == true) {
        final message = (decoded['message'] ?? 'ข้อมูลไม่ถูกต้อง').toString();
        if (category == 'food') {
          setState(() {
            foodController.clear();
            matchedFood = null;
            foodError = message;
            foodAdvice = null;
            foodImageUrl = null;
            selectedFoodQty = null;
            selectedFoodMenuId = null;
            selectedFoodMenuCalories = 0;
            calculatedFoodCalories = 0.0;
          });
        } else if (category == 'dessert') {
          setState(() {
            dessertController.clear();
            matchedDessert = null;
            dessertError = message;
            dessertAdvice = null;
            dessertImageUrl = null;
            selectedDessertQty = null;
            selectedDessertId = null;
            selectedDessertMenuCalories = 0;
            calculatedDessertCalories = 0.0;
          });
        } else if (category == 'drink') {
          setState(() {
            drinkController.clear();
            matchedDrink = null;
            drinkError = message;
            drinkAdvice = null;
            drinkImageUrl = null;
            selectedDrinkQty = null;
            selectedDrinkMenuId = null;
            selectedDrinkMenuCalories = 0;
            calculatedDrinkCalories = 0.0;
          });
        }
        await _showValidationWarningDialog(message);
        return;
      }

      await _analyzeMenu(text, category);
    } catch (e) {
      if (kDebugMode) print('Strict food validation error: $e');
    }
  }

  Future<void> _analyzeMenu(String input, String category) async {
    if (input.trim().isEmpty) return;
    // Clear the current image immediately to avoid showing stale images
    if (category == 'food') {
      setState(() {
        foodImageUrl = null;
      });
    } else if (category == 'dessert') {
      setState(() {
        dessertImageUrl = null;
      });
    } else if (category == 'drink') {
      setState(() {
        drinkImageUrl = null;
      });
    }
    // Quick client-side blacklist for obviously non-food inputs (supplemental)
    final forbidden = [
      'ตุ๊กแก',
      'จิ้งจก',
      'งู',
      'สุนัข',
      'แมว',
      'สิงโต',
      'เสือ',
      'กวาง',
      'ปลาเถื่อน',
      'หญ้า',
      'ดอกไม้พิษ',
      'วัชพืช',
      'ของเล่น',
      'รองเท้า',
      'ไม้',
    ];
    final low = input.toString().trim().toLowerCase();
    for (final f in forbidden) {
      if (low.contains(f)) {
        final reason =
            'คำค้นหานี้เป็นสิ่งที่ไม่เหมาะสมหรือไม่ใช่อาหารตามหลักโภชนาการ';
        if (category == 'food') {
          setState(() {
            matchedFood = null;
            selectedFoodMenuId = null;
            selectedFoodMenuCalories = 0;
            calculatedFoodCalories = 0.0;
            foodImageUrl = null;
            foodError = reason;
          });
        } else if (category == 'dessert') {
          setState(() {
            matchedDessert = null;
            selectedDessertId = null;
            selectedDessertMenuCalories = 0;
            calculatedDessertCalories = 0.0;
            dessertImageUrl = null;
            dessertError = reason;
          });
        } else if (category == 'drink') {
          setState(() {
            matchedDrink = null;
            selectedDrinkMenuId = null;
            selectedDrinkMenuCalories = 0;
            calculatedDrinkCalories = 0.0;
            drinkImageUrl = null;
            drinkError = reason;
          });
        }
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'แจ้งเตือนระบบโภชนาการ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Text(reason, style: const TextStyle(fontSize: 15)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'ตกลง',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }
    }
    // Only reset state for the field being typed to avoid cross-field side-effects
    if (category == 'food') {
      matchedFood = null;
      foodError = null;
      foodAdvice = null;
      foodImageUrl = null;
      selectedFoodQty = null;
    } else if (category == 'dessert') {
      matchedDessert = null;
      dessertError = null;
      dessertAdvice = null;
      dessertImageUrl = null;
      selectedDessertQty = null;
    } else if (category == 'drink') {
      matchedDrink = null;
      drinkError = null;
      drinkAdvice = null;
      drinkImageUrl = null;
      selectedDrinkQty = null;
    }

    // ✅ โค้ดที่แก้ไขเรียบร้อยแล้ว
    try {
      // เปลี่ยนไปใช้ตัวแปร _auth ของคลาสที่ถูก init ไว้แล้วแทนการสร้างตัวแปรใหม่
      final userProfile = _auth.user ?? {};
      List<dynamic> userAllergies = (userProfile['food_allergies'] is String)
          ? (userProfile['food_allergies'] as String).split(',')
          : (userProfile['food_allergies'] ?? []);
      List<dynamic> userDiseases = (userProfile['chronic_diseases'] is String)
          ? (userProfile['chronic_diseases'] as String).split(',')
          : (userProfile['chronic_diseases'] ?? []);

      // Determine endpoint from category, but be defensive: only accept
      // recognized categories. Default to food-menus to avoid accidental
      // requests to the wrong endpoint.
      final catNorm = category.trim().toLowerCase();
      String path = '/api/food-menus';
      if (catNorm == 'dessert') {
        path = '/api/dessert-menus';
      } else if (catNorm == 'drink') {
        path = '/api/drink-menus';
      }
      // Debugging: log chosen endpoint when in debug mode
      if (kDebugMode) {
        print(
          '[ChooseFoodTypePage] _analyzeMenu search "$input" -> endpoint: $path',
        );
      }
      // Include selected category_id and food_type_id when available to scope backend search
      // When performing free-text search, do NOT send category_id or food_type_id
      // so backend can search across all categories/types and return matches.
      // Include the intended category so backend can perform strict classification
      // Attach user context (user id, duration, meal) when available so backend
      // can apply personalized validation and warnings.
      final userId = userProfile['id'] != null
          ? userProfile['id'].toString()
          : '';
      final durationVal =
          (userProfile['duration'] != null)
          ? userProfile['duration'].toString()
          : '1';
      final mealVal = (userProfile['meal'] != null)
          ? userProfile['meal'].toString()
          : '';

      String query =
          '?search=${Uri.encodeComponent(input.trim())}&category=${Uri.encodeComponent(catNorm)}';
      if (userId.isNotEmpty) query += '&user_id=${Uri.encodeComponent(userId)}';
      if (durationVal.isNotEmpty) {
        query += '&duration=${Uri.encodeComponent(durationVal)}';
      }
      if (mealVal.isNotEmpty) query += '&meal=${Uri.encodeComponent(mealVal)}';

      final ApiResponse respApi = await api.get('$path$query');
      dynamic decoded;
      try {
        decoded =
            (respApi.statusCode == 200 &&
                respApi.body.isNotEmpty)
            ? jsonDecode(respApi.body)
            : null;
      } catch (e) {
        decoded = null;
      }

      // If backend returns a strict validation failure (is_valid: false)
      if (decoded is Map &&
          (decoded['is_valid'] == false ||
              decoded['is_valid']?.toString() == 'false')) {
        final reason =
            (decoded['reason'] ??
                    decoded['error'] ??
                    'ข้อมูลที่ระบุไม่ถูกต้องตามหมวดหมู่โภชนาการ')
                .toString();
        // Clear the relevant field to prevent rendering stale images or items
        if (category == 'food') {
          setState(() {
            matchedFood = null;
            selectedFoodMenuId = null;
            selectedFoodMenuCalories = 0;
            calculatedFoodCalories = 0.0;
            foodImageUrl = null;
            foodError = reason;
          });
        } else if (category == 'dessert') {
          setState(() {
            matchedDessert = null;
            selectedDessertId = null;
            selectedDessertMenuCalories = 0;
            calculatedDessertCalories = 0.0;
            dessertImageUrl = null;
            dessertError = reason;
          });
        } else if (category == 'drink') {
          setState(() {
            matchedDrink = null;
            selectedDrinkMenuId = null;
            selectedDrinkMenuCalories = 0;
            calculatedDrinkCalories = 0.0;
            drinkImageUrl = null;
            drinkError = reason;
          });
        }
        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext ctx) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 28,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'แจ้งเตือนระบบโภชนาการ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                content: Text(reason, style: const TextStyle(fontSize: 15)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(
                      'ตกลง',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }
        return;
      }

      // Handle cross-category error_type returned by backend
      if (decoded is Map && decoded.containsKey('error_type')) {
        final et = (decoded['error_type'] ?? '').toString();
        if (category == 'food') {
          if (et == 'is_dessert_error') {
            setState(() {
              matchedFood = null;
              selectedFoodMenuId = null;
              selectedFoodMenuCalories = 0;
              calculatedFoodCalories = 0.0;
              foodImageUrl = null;
              foodError = 'เมนูของหวานไม่ได้อยู่ในหมวดอาหารคาว';
            });
            return;
          }
          if (et == 'is_drink_error') {
            setState(() {
              matchedFood = null;
              selectedFoodMenuId = null;
              selectedFoodMenuCalories = 0;
              calculatedFoodCalories = 0.0;
              foodImageUrl = null;
              foodError = 'เมนูเครื่องดื่มไม่ได้อยู่ในหมวดอาหารคาว';
            });
            return;
          }
        } else if (category == 'dessert') {
          if (et == 'is_food_error') {
            setState(() {
              matchedDessert = null;
              selectedDessertId = null;
              selectedDessertMenuCalories = 0;
              calculatedDessertCalories = 0.0;
              dessertImageUrl = null;
              dessertError = 'เมนูอาหารคาวไม่เหมาะสมที่จะอยู่ในเมนูของหวาน';
            });
            return;
          }
          if (et == 'is_drink_error') {
            setState(() {
              matchedDessert = null;
              selectedDessertId = null;
              selectedDessertMenuCalories = 0;
              calculatedDessertCalories = 0.0;
              dessertImageUrl = null;
              dessertError =
                  'เมนูเครื่องดื่มนี้ไม่เหมาะกับการอยู่ในหมวดของหวาน';
            });
            return;
          }
        } else if (category == 'drink') {
          if (et == 'is_food_error') {
            setState(() {
              matchedDrink = null;
              selectedDrinkMenuId = null;
              selectedDrinkMenuCalories = 0;
              calculatedDrinkCalories = 0.0;
              drinkImageUrl = null;
              drinkError = 'ไม่เหมาะสมที่จะอยู่ในหมวดเครื่องดื่ม';
            });
            return;
          }
          if (et == 'is_dessert_error') {
            setState(() {
              matchedDrink = null;
              selectedDrinkMenuId = null;
              selectedDrinkMenuCalories = 0;
              calculatedDrinkCalories = 0.0;
              drinkImageUrl = null;
              drinkError = 'เมนูของหวานไม่เหมาะสมกับการอยู่ในหมวดเครื่องดื่ม';
            });
            return;
          }
        }
      }

      final List menus = (decoded is List) ? decoded : [];
      final matched = (menus.isNotEmpty) ? menus[0] : null;

      if (matched == null) {
        // No candidate returned by backend
        final errMsg = (category == 'food')
            ? 'ไม่พบเมนูนี้ในระบบ โปรดตรวจสอบชื่อเมนูอาหาร'
            : (category == 'dessert'
                  ? 'ไม่พบเมนูนี้ในระบบ โปรดตรวจสอบชื่อเมนูของหวาน'
                  : 'ไม่พบเมนูนี้ในระบบ โปรดตรวจสอบชื่อเมนูเครื่องดื่ม');
        if (category == 'food') {
          setState(() {
            matchedFood = null;
            selectedFoodMenuId = null;
            selectedFoodMenuCalories = 0;
            calculatedFoodCalories = 0.0;
            foodImageUrl = null;
            foodError = errMsg;
          });
        } else if (category == 'dessert') {
          setState(() {
            matchedDessert = null;
            selectedDessertId = null;
            selectedDessertMenuCalories = 0;
            calculatedDessertCalories = 0.0;
            dessertImageUrl = null;
            dessertError = errMsg;
          });
        } else if (category == 'drink') {
          setState(() {
            matchedDrink = null;
            selectedDrinkMenuId = null;
            selectedDrinkMenuCalories = 0;
            calculatedDrinkCalories = 0.0;
            drinkImageUrl = null;
            drinkError = errMsg;
          });
        }
        return;
      }

      // Allergy filter (string match against ingredients and name)
      String ingredients = (matched['ingredients']?.toString() ?? '')
          .toLowerCase();
      final String matchedName =
          matched['name']?.toString().toLowerCase() ?? '';
      List<String> foundAllergens = [];
      for (var allergy in userAllergies) {
        if (allergy == null) continue;
        final a = allergy.toString().trim().toLowerCase();
        if (a.isEmpty) continue;
        if (ingredients.contains(a) || matchedName.contains(a)) {
          foundAllergens.add(a);
        }
      }
      if (foundAllergens.isNotEmpty) {
        final msg =
            'ไม่ผ่านเนื่องจากคุณแพ้${foundAllergens.join(', ')} โปรดเลือกเมนูอาหารอื่นที่ไม่มีส่วนผสมนี้';
        setState(() {
          if (category == 'food') foodError = msg;
          if (category == 'dessert') dessertError = msg;
          if (category == 'drink') drinkError = msg;
        });
        return;
      }

      // Chronic disease checks
      String adviceText = "✅ เมนูนี้ปลอดภัยสำหรับคุณ ทานได้ในปริมาณที่เหมาะสม";
      String name = matched['name'].toString().toLowerCase();
      List<String> matchedDiseases = [];
      for (var disease in userDiseases) {
        final d = disease.toString().trim();
        if (d.isEmpty) continue;
        if ((d == 'เบาหวาน' || d.toLowerCase().contains('diabetes')) &&
            (category == 'dessert' ||
                name.contains('หวาน') ||
                ingredients.contains('น้ำตาล'))) {
          matchedDiseases.add(d);
        }
        if ((d == 'ความดันโลหิตสูง' ||
                d.contains('ความดัน') ||
                d.toLowerCase().contains('hypertension')) &&
            (ingredients.contains('เกลือ') ||
                name.contains('เค็ม') ||
                name.contains('ไตปลา'))) {
          matchedDiseases.add(d);
        }
        if ((d == 'ไขมันในเลือดสูง' ||
                d.toLowerCase().contains('cholesterol') ||
                d.contains('ไขมัน')) &&
            (name.contains('ขาหมู') ||
                name.contains('ทอด') ||
                name.contains('เจียว'))) {
          matchedDiseases.add(d);
        }
      }
      if (matchedDiseases.isNotEmpty) {
        final msg =
            'ไม่ผ่านเนื่องจากโรคประจำตัว: ${matchedDiseases.join(', ')} โปรดเลือกเมนูอื่นที่ปลอดภัยต่อโรคประจำตัวของคุณ';
        setState(() {
          if (category == 'food') foodError = msg;
          if (category == 'dessert') dessertError = msg;
          if (category == 'drink') drinkError = msg;
        });
        return;
      }

      // Chronic disease micro-targeting: CKD (ไต) and Hypertension
      try {
        final cdsRaw =
            (userProfile['chronic_diseases'] ??
                    userProfile['chronic_diseases'] ??
                    '')
                .toString()
                .toLowerCase();
        if (cdsRaw.contains('ไต') || cdsRaw.contains('ckd')) {
          // warn about high-phosphorus / high-potassium ingredients (milk, nuts, cheese)
          final phosWords = ['นม', 'milk', 'cheese', 'ถั่ว', 'nuts', 'soy'];
          for (var w in phosWords) {
            if (ingredients.contains(w) || matchedName.contains(w)) {
              final warn =
                  '⚠️ เตือนผู้ป่วยโรคไต: อาหารนี้อาจมีฟอสฟอรัส/โพแทสเซียมสูง (เช่น นม, ถั่ว) กรุณาตรวจสอบปริมาณหรือเลือกเมนูทางเลือก';
              if (category == 'food') foodAdvice = warn;
              if (category == 'dessert') dessertAdvice = warn;
              if (category == 'drink') drinkAdvice = warn;
              break;
            }
          }
        }
        if (cdsRaw.contains('ความดัน') || cdsRaw.contains('hypertension')) {
          // suggest potassium/magnesium rich swaps
          final tip =
              '💡 สำหรับผู้ป่วยความดัน: เพิ่มผักใบเขียวหรือผลไม้ที่มีโพแทสเซียม/แมกนีเซียม ช่วยลดความดันได้ เช่น กล้วย หรือผักใบเขียว';
          if (category == 'food') {
            foodAdvice = (foodAdvice == null) ? tip : '$foodAdvice\n$tip';
          }
          if (category == 'dessert') {
            dessertAdvice = (dessertAdvice == null)
                ? tip
                : '$dessertAdvice\n$tip';
          }
          if (category == 'drink') {
            drinkAdvice = (drinkAdvice == null) ? tip : '$drinkAdvice\n$tip';
          }
        }
      } catch (_) {}

      // 📝 Prepare the search query for Pexels: first try to get English name from DB,
      // then translate if Thai name is found, then add "Thai style" for all categories
      String searchQueryEn = '';
      
      // 1. Try to get English name from the database based on category
      if (matched != null) {
        if (catNorm == 'dessert') {
          searchQueryEn = matched['dessert_name']?.toString() ?? '';
        } else {
          searchQueryEn = matched['name']?.toString() ?? '';
        }
      }
      
      // 2. If we don't have a search query yet, translate from user input
      if (searchQueryEn.isEmpty) {
        try {
          final translator = GoogleTranslator();
          var translation = await translator.translate(input, from: 'th', to: 'en');
          searchQueryEn = translation.text;
          
          if (kDebugMode) {
            print('[ChooseFoodTypePage._analyzeMenu] Translation: $input -> $searchQueryEn');
          }
        } catch (e) {
          // Fallback: use category hint if translation fails
          searchQueryEn = (catNorm == 'dessert') 
              ? 'sweet dessert' 
              : (catNorm == 'drink' ? 'beverage drink' : 'thai food');
          if (kDebugMode) {
            print('[ChooseFoodTypePage._analyzeMenu] Translation error: $e, using fallback: $searchQueryEn');
          }
        }
      }
      
      // 3. Lock Thai style context for savory and dessert categories
      // but avoid forcing Thai style on generic drinks like water.
      if (catNorm != 'drink' &&
          searchQueryEn.isNotEmpty &&
          !searchQueryEn.toLowerCase().contains('thai style')) {
        searchQueryEn = "$searchQueryEn Thai style";
      }
      
      if (kDebugMode) {
        print('[ChooseFoodTypePage._analyzeMenu] Final search query: "$searchQueryEn" (category: $catNorm)');
      }

      String? img = await _fetchPexelsImage(
        searchQueryEn,  // ✅ Use translated English name instead of Thai
        categoryHint: (catNorm == 'dessert')
            ? 'sweet dessert'
            : (catNorm == 'drink' ? 'beverage drink' : 'thai food'),
      );

      if (category == 'food') {
        // If backend indicated this item belongs to dessert or another group, show error
        if ((matched.containsKey('is_dessert') &&
                matched['is_dessert'] == true) ||
            (matched.containsKey('group') && matched['group'] != 'food')) {
          setState(() {
            matchedFood = null;
            selectedFoodMenuId = null;
            selectedFoodMenuCalories = 0;
            calculatedFoodCalories = 0.0;
            foodImageUrl = null;
            foodError = 'เมนูนี้ไม่เหมาะสม ควรอยู่ในช่องที่ถูกต้อง';
          });
          return;
        }
        final newItem = Map<String, dynamic>.from(matched);
        setState(() {
          matchedFood = newItem;
          foodAdvice = (newItem['is_estimated'] == true)
              ? '⚠️ ไม่พบเมนูนี้ในระบบ ค่าโภชนาการเป็นการประมาณคร่าวๆ ไม่ใช่ข้อมูลจริง\n$adviceText'
              : adviceText;
          foodImageUrl = (img?.trim().isNotEmpty == true) ? img : null;
          foodError = null;
          selectedFoodMenuId = newItem['id'] is int
              ? newItem['id'] as int
              : int.tryParse(newItem['id']?.toString() ?? '') ??
                    selectedFoodMenuId;
          selectedFoodMenuCalories = (newItem['calories'] != null)
              ? (int.tryParse(newItem['calories']?.toString() ?? '') ??
                    (newItem['kcal'] is num
                        ? (newItem['kcal'] as num).toInt()
                        : 0))
              : (newItem['kcal'] is num ? (newItem['kcal'] as num).toInt() : 0);
          calculatedFoodCalories =
              selectedFoodMenuCalories?.toDouble() ?? calculatedFoodCalories;
          // if flagged unsafe, prepare behavioral nudge alternatives
          if (newItem['safe'] != null &&
              (newItem['safe'] == false || newItem['safe'] == 0)) {
            _showBehavioralNudge = true;
            _nudgeAlternatives = _findSmartSwaps(newItem);
          } else {
            _showBehavioralNudge = false;
            _nudgeAlternatives = [];
          }
          _computeGiAndSatiety();
          _applyComboFilters();
        });
        _recomputeSelectedCalories();
        // Mark safety checked and safe when backend returned a valid match with no errors
        if (mounted) {
          setState(() {
            isSafetyChecked = true;
            isFoodSafe = true;
            _foodSafetyOk = true;
            safetyMessage = 'ตรวจสอบข้อมูลโภชนาการและความปลอดภัยเรียบร้อยแล้ว';
          });
        }
      } else if (category == 'dessert') {
        // If backend returned a non-dessert for dessert field, show error
        if ((matched.containsKey('is_dessert') &&
                matched['is_dessert'] == false) ||
            (matched.containsKey('group') && matched['group'] != 'dessert')) {
          setState(() {
            matchedDessert = null;
            selectedDessertId = null;
            selectedDessertMenuCalories = 0;
            calculatedDessertCalories = 0.0;
            dessertImageUrl = null;
            dessertError = 'เมนูนี้ไม่เหมาะสม ควรอยู่ในช่องที่ถูกต้อง';
          });
          return;
        }
        final newItem = Map<String, dynamic>.from(matched);
        setState(() {
          matchedDessert = newItem;
          dessertAdvice = (newItem['is_estimated'] == true)
              ? '⚠️ ไม่พบเมนูนี้ในระบบ ค่าโภชนาการเป็นการประมาณคร่าวๆ ไม่ใช่ข้อมูลจริง\n$adviceText'
              : adviceText;
          dessertImageUrl = (img?.trim().isNotEmpty == true) ? img : null;
          dessertError = null;
          selectedDessertId = newItem['id'] is int
              ? newItem['id'] as int
              : int.tryParse(newItem['id']?.toString() ?? '') ??
                    selectedDessertId;
          selectedDessertMenuCalories = (newItem['calories'] != null)
              ? (int.tryParse(newItem['calories']?.toString() ?? '') ??
                    (newItem['kcal'] is num
                        ? (newItem['kcal'] as num).toInt()
                        : 0))
              : (newItem['kcal'] is num ? (newItem['kcal'] as num).toInt() : 0);
          calculatedDessertCalories =
              selectedDessertMenuCalories?.toDouble() ??
              calculatedDessertCalories;
          if (newItem['safe'] != null &&
              (newItem['safe'] == false || newItem['safe'] == 0)) {
            _showBehavioralNudge = true;
            _nudgeAlternatives = _findSmartSwaps(newItem);
          } else {
            _showBehavioralNudge = false;
            _nudgeAlternatives = [];
          }
          _computeGiAndSatiety();
          _applyComboFilters();
        });
        _recomputeSelectedCalories();
        // Mark safety checked and safe when backend returned a valid match with no errors
        if (mounted) {
          setState(() {
            isSafetyChecked = true;
            isFoodSafe = true;
            safetyMessage = 'ตรวจสอบข้อมูลโภชนาการและความปลอดภัยเรียบร้อยแล้ว';
          });
        }
      } else if (category == 'drink') {
        // Ensure this item is actually a drink
        if ((matched.containsKey('is_dessert') &&
                matched['is_dessert'] == true) ||
            (matched.containsKey('group') && matched['group'] != 'drink')) {
          setState(() {
            matchedDrink = null;
            selectedDrinkMenuId = null;
            selectedDrinkMenuCalories = 0;
            calculatedDrinkCalories = 0.0;
            drinkImageUrl = null;
            drinkError = 'เมนูนี้ไม่เหมาะสม ควรอยู่ในช่องที่ถูกต้อง';
          });
          return;
        }
        final newItem = Map<String, dynamic>.from(matched);
        setState(() {
          matchedDrink = newItem;
          drinkAdvice = (newItem['is_estimated'] == true)
              ? '⚠️ ไม่พบเมนูนี้ในระบบ ค่าโภชนาการเป็นการประมาณคร่าวๆ ไม่ใช่ข้อมูลจริง\n$adviceText'
              : adviceText;
          drinkImageUrl = (img?.trim().isNotEmpty == true) ? img : null;
          drinkError = null;
          selectedDrinkMenuId = newItem['id'] is int
              ? newItem['id'] as int
              : int.tryParse(newItem['id']?.toString() ?? '') ??
                    selectedDrinkMenuId;
          selectedDrinkMenuCalories = (newItem['calories'] != null)
              ? (int.tryParse(newItem['calories']?.toString() ?? '') ??
                    (newItem['kcal'] is num
                        ? (newItem['kcal'] as num).toInt()
                        : 0))
              : (newItem['kcal'] is num ? (newItem['kcal'] as num).toInt() : 0);
          calculatedDrinkCalories =
              selectedDrinkMenuCalories?.toDouble() ?? calculatedDrinkCalories;
          if (newItem['safe'] != null &&
              (newItem['safe'] == false || newItem['safe'] == 0)) {
            _showBehavioralNudge = true;
            _nudgeAlternatives = _findSmartSwaps(newItem);
          } else {
            _showBehavioralNudge = false;
            _nudgeAlternatives = [];
          }
          _computeGiAndSatiety();
          _applyComboFilters();
        });
        _recomputeSelectedCalories();
        // Mark safety checked and safe when backend returned a valid match with no errors
        if (mounted) {
          setState(() {
            isSafetyChecked = true;
            isFoodSafe = true;
            _drinkSafetyOk = true;
            safetyMessage = 'ตรวจสอบข้อมูลโภชนาการและความปลอดภัยเรียบร้อยแล้ว';
          });
        }
      }
    } catch (e) {
      setState(() {
        if (category == 'food') {
          foodError = 'เกิดข้อผิดพลาดในการเชื่อมต่อฐานข้อมูล';
        }
        if (category == 'dessert') {
          dessertError = 'เกิดข้อผิดพลาดในการเชื่อมต่อฐานข้อมูล';
        }
        if (category == 'drink') {
          drinkError = 'เกิดข้อผิดพลาดในการเชื่อมต่อฐานข้อมูล';
        }
      });
    }
  }

  // Fetch safety message for a specific menu id with current portion ratio
  Future<void> _fetchSafetyForMenu(int menuId) async {
    try {
      // Attach user_id, duration and meal so backend can evaluate period-based quotas
      final user = _auth.user ?? {};
      final tempSels = _auth.tempSelections ?? {};
      final int? userId = user['id'] is int
          ? user['id'] as int
          : (user['id'] != null ? int.tryParse(user['id'].toString()) : null);
      final int duration = tempSels['duration'] != null
          ? (int.tryParse(tempSels['duration'].toString()) ?? 1)
          : (user['duration'] != null
                ? (int.tryParse(user['duration'].toString()) ?? 1)
                : 1);
      final String meal =
          (tempSels['meal'] ?? user['meal'] ?? '')?.toString() ?? '';
      final body = {
        'menu_id': menuId,
        'portion_ratio': _currentPortion,
        'duration': duration,
        'meal': meal,
      };
      if (userId != null) body['user_id'] = userId;
      final ApiResponse safetyResp = await api.post(
        '/api/get_food_safety_message',
        body: body,
      );
      if (safetyResp.statusCode == 200 && safetyResp.body.isNotEmpty) {
        try {
          final Map parsed =
              jsonDecode(safetyResp.body) as Map<String, dynamic>;
          setState(() {
            remainingCaloriesToday = parsed['remaining_calories_period'] != null
                ? double.tryParse(
                    parsed['remaining_calories_period'].toString(),
                  )
                : null;
            consumedCaloriesToday = parsed['consumed_for_period'] != null
                ? double.tryParse(parsed['consumed_for_period'].toString())
                : null;
            itemSafe = parsed['safe'] == true;
            // Prefer explicit advice field, fallback to safety_message/upgrade_tips
            final adv =
                (parsed['advice'] ??
                        parsed['safety_message'] ??
                        parsed['upgrade_tips'])
                    ?.toString();
            safetyMessage = (adv != null && adv.isNotEmpty)
                ? adv
                : (parsed['safety_message']?.toString() ?? '');
            upgradeTips = parsed['upgrade_tips']?.toString();
            swapSuggestion = parsed['swap_suggestion'] is Map
                ? Map<String, dynamic>.from(parsed['swap_suggestion'])
                : null;
            adjustedCalories = parsed['adjusted_calories'] != null
                ? double.tryParse(parsed['adjusted_calories'].toString())
                : null;
            adjustedSugar = parsed['adjusted_sugar'] != null
                ? double.tryParse(parsed['adjusted_sugar'].toString())
                : null;
            adjustedSodium = parsed['adjusted_sodium'] != null
                ? int.tryParse(parsed['adjusted_sodium'].toString())
                : null;
            try {
              _currentPortion = parsed['portion_ratio_applied'] != null
                  ? double.tryParse(
                          parsed['portion_ratio_applied'].toString(),
                        ) ??
                        _currentPortion
                  : _currentPortion;
            } catch (_) {}
          });
        } catch (e) {
          if (kDebugMode) print('parse safety resp error: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) print('safety check failed: $e');
    }
  }

  void _authListener() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadSavedSelections() async {
    try {
      final sels = _auth.tempSelections ?? _auth.guestSelections ?? {};
      if (sels.isEmpty) return;

      final String? lockUntilRaw = sels['lock_until']?.toString();
      if (lockUntilRaw != null && lockUntilRaw.isNotEmpty) {
        try {
          final parsed = DateTime.parse(lockUntilRaw);
          _lockUntil = parsed.isUtc
              ? parsed.toUtc().add(const Duration(hours: 7))
              : parsed.toUtc().add(const Duration(hours: 7));
        } catch (_) {
          _lockUntil = null;
        }
      }
      if (_lockUntil != null &&
          DateTime.now().toUtc().add(const Duration(hours: 7)).isAfter(_lockUntil!)) {
        _lockUntil = null;
      }

      setState(() {
        selectedFoodTypeId = sels['food_type_id'] is int
            ? sels['food_type_id'] as int
            : int.tryParse(sels['food_type_id']?.toString() ?? '');
        if (selectedFoodTypeId != null && selectedFoodTypeId == 0) {
          selectedFoodTypeId = null;
        }
        selectedCategoryId = sels['category_id'] is int
            ? sels['category_id'] as int
            : int.tryParse(sels['category_id']?.toString() ?? '');
        if (selectedCategoryId != null && selectedCategoryId == 0) {
          selectedCategoryId = null;
        }
        selectedFoodMenuId = sels['menu_id'] is int
            ? sels['menu_id'] as int
            : int.tryParse(sels['menu_id']?.toString() ?? '');
        if (selectedFoodMenuId != null && selectedFoodMenuId == 0) {
          selectedFoodMenuId = null;
        }
        selectedDrinkTypeId = sels['drink_type_id'] is int
            ? sels['drink_type_id'] as int
            : int.tryParse(sels['drink_type_id']?.toString() ?? '');
        if (selectedDrinkTypeId != null && selectedDrinkTypeId == 0) {
          selectedDrinkTypeId = null;
        }
        selectedDrinkMenuId = sels['drink_menu_id'] is int
            ? sels['drink_menu_id'] as int
            : int.tryParse(sels['drink_menu_id']?.toString() ?? '');
        if (selectedDrinkMenuId != null && selectedDrinkMenuId == 0) {
          selectedDrinkMenuId = null;
        }
        selectedDessertId = sels['dessert_menu_id'] is int
            ? sels['dessert_menu_id'] as int
            : int.tryParse(sels['dessert_menu_id']?.toString() ?? '');
        if (selectedDessertId != null && selectedDessertId == 0) {
          selectedDessertId = null;
        }
        // lockCategoryMenu remains unused for free-text mode; ensure false
        lockCategoryMenu = false;

        // populate controllers from persisted human-readable names where available
        try {
          final sType =
              sels['selectedType'] ?? sels['selectedTypeName'];
          if (sType != null) {
            foodTypeController.text = _firstChoice(sType.toString());
          }
          final sCat =
              sels['selectedCategory'] ?? sels['selectedCategoryName'];
          if (sCat != null) {
            categoryController.text = _firstChoice(sCat.toString());
          }
          final sMenu =
              sels['selectedMenu'] ?? sels['selectedMenuName'];
          if (sMenu != null) foodMenuController.text = sMenu.toString();
          final sDrinkType = sels['selectedDrinkType'];
          if (sDrinkType != null) {
            drinkTypeController.text = sDrinkType.toString();
          }
          final sDrinkMenu = sels['selectedDrinkMenu'];
          if (sDrinkMenu != null) {
            drinkMenuController.text = sDrinkMenu.toString();
          }
          final sDessert = sels['selectedDessert'];
          if (sDessert != null) {
            dessertMenuController.text = sDessert.toString();
          }
        } catch (e) {
          if (kDebugMode) print('Choose_food_type_page caught error: $e');
        }
        // if controllers still empty but ids present, fill with resolved names
        try {
          if ((foodTypeController.text.trim()).isEmpty &&
              selectedFoodTypeId != null) {
            foodTypeController.text = _firstChoice(
              _nameForId(foodTypes, selectedFoodTypeId),
            );
          }
          if ((categoryController.text.trim()).isEmpty &&
              selectedCategoryId != null) {
            categoryController.text = _nameForId(
              foodCategories,
              selectedCategoryId,
            );
          }
          if ((foodMenuController.text.trim()).isEmpty &&
              selectedFoodMenuId != null) {
            foodMenuController.text = _nameForId(foodMenus, selectedFoodMenuId);
          }
          if ((drinkTypeController.text.trim()).isEmpty &&
              selectedDrinkTypeId != null) {
            drinkTypeController.text = _nameForId(
              drinkTypes,
              selectedDrinkTypeId,
            );
          }
          if ((drinkMenuController.text.trim()).isEmpty &&
              selectedDrinkMenuId != null) {
            drinkMenuController.text = _nameForId(
              drinkMenus,
              selectedDrinkMenuId,
            );
          }
          if ((dessertMenuController.text.trim()).isEmpty &&
              selectedDessertId != null) {
            dessertMenuController.text = _nameForId(
              desserts,
              selectedDessertId,
            );
          }
        } catch (e) {
          if (kDebugMode) print('Choose_food_type_page caught error: $e');
        }
      });

      // capture any health goal label and group stored by the previous page
      try {
        final sels = _auth.tempSelections ?? _auth.guestSelections ?? {};
        if (sels.containsKey('health_goal')) {
          selectedHealthGoalLabel = sels['health_goal']?.toString();
        }
        if (sels.containsKey('health_goal_group')) {
          selectedHealthGoalGroup = sels['health_goal_group']?.toString();
        }
        if (sels.containsKey('health_goal_drink')) {
          final v = sels['health_goal_drink'];
          healthGoalDrink = v?.toString();
        }
        if (sels.containsKey('health_goal_drink_types')) {
          final v = sels['health_goal_drink_types'];
          try {
            if (v is List) {
              healthGoalDrinkTypes = v.map((e) => e.toString()).toList();
            } else if (v is String) {
              final parsed = jsonDecode(v);
              if (parsed is List) {
                healthGoalDrinkTypes = parsed.map((e) => e.toString()).toList();
              } else {
                healthGoalDrinkTypes = v
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
              }
            }
          } catch (_) {
            if (v is String) {
              healthGoalDrinkTypes = v
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
          }
        }
        // If no temp selection exists, fall back to persisted user profile
        // (fetch goal from DB so it's displayed even after app restart).
        final shgl = selectedHealthGoalLabel;
        if ((shgl == null || shgl.isEmpty) && _auth.user != null) {
          try {
            final u = _auth.user!;
            final hg = u['health_goal'];
            if (hg != null && hg.toString().trim().isNotEmpty) {
              selectedHealthGoalLabel = hg.toString();
            }
          } catch (e) {
            if (kDebugMode) print('Choose_food_type_page caught error: $e');
          }
        }
        // fallback: load drink-specific goal/types from persisted profile if not present in temp selections
        if ((healthGoalDrink == null ||
                (healthGoalDrink?.trim().isEmpty ?? true)) &&
            _auth.user != null) {
          try {
            final u = _auth.user!;
            final hd = u['health_goal_drink'];
            if (hd != null && hd.toString().trim().isNotEmpty) {
              healthGoalDrink = hd.toString();
            }
            final hdt = u['health_goal_drink_types'];
            try {
              if (hdt is List) {
                healthGoalDrinkTypes = hdt.map((e) => e.toString()).toList();
              } else if (hdt is String) {
                final parsed = jsonDecode(hdt);
                if (parsed is List) {
                  healthGoalDrinkTypes = parsed
                      .map((e) => e.toString())
                      .toList();
                } else {
                  healthGoalDrinkTypes = hdt
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                }
              }
            } catch (_) {
              if (hdt is String) {
                healthGoalDrinkTypes = hdt
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
              }
            }
          } catch (_) {}
        }

        // If a health goal group (food type name) exists, try to map it
        // to a foodType id so we can preselect the proper food type.
        final shgg = selectedHealthGoalGroup;
        if (shgg != null) {
          final gName = shgg.trim().toLowerCase();
          final match = foodTypes.firstWhere(
            (e) => (e['name'] ?? '').toString().toLowerCase() == gName,
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            final idVal = match['id'] is int
                ? match['id'] as int
                : int.tryParse(match['id'].toString());
            if (idVal != null) {
              selectedFoodTypeId = idVal;
              // load categories for this type so names are available
              await _loadFoodCategories(idVal);
            }
          }
        }

        // If a health goal label exists, try to map it to a category id
        final shgl2 = selectedHealthGoalLabel;
        if (shgl2 != null) {
          final label = shgl2.trim().toLowerCase();
          final matchCat = foodCategories.firstWhere(
            (e) => (e['name'] ?? '').toString().toLowerCase() == label,
            orElse: () => {},
          );
          if (matchCat.isNotEmpty) {
            final cid = matchCat['id'] is int
                ? matchCat['id'] as int
                : int.tryParse(matchCat['id'].toString());
            if (cid != null) selectedCategoryId = cid;
          } else {
            // If no numeric category id found, keep the label in the controller
            // and avoid assigning any synthetic numeric id. This prevents
            // accidental sending of invalid sentinel ids to the backend.
            categoryController.text = shgl2;
            selectedCategoryId = null;
          }
        }

        // Note: do not lock dropdowns here — allow user to change menu/type.
      } catch (e) {
        if (kDebugMode) print('Choose_food_type_page caught error: $e');
      }

      // Ensure the two top text controllers reflect the choices from Choose_a_health_goal (if present)
      try {
        final shgg2 = selectedHealthGoalGroup;
        if (shgg2 != null && shgg2.trim().isNotEmpty) {
          foodTypeController.text = _firstChoice(shgg2.trim());
        }
        final shgl3 = selectedHealthGoalLabel;
        if (shgl3 != null && shgl3.trim().isNotEmpty) {
          categoryController.text = _firstChoice(shgl3.trim());
        }
      } catch (e) {
        if (kDebugMode) print('Error filling top controllers: $e');
      }

      // Apply health-goal-based filtering to the food types (e.g., lock to protein menus)
      try {
        _applyHealthGoalFilter();
      } catch (e) {
        if (kDebugMode) print('applyHealthGoalFilter error: $e');
      }

      // If we have a food type and category, try loading categories/menus so names are available
      final sftInit = selectedFoodTypeId;
      if (sftInit != null) await _loadFoodCategories(sftInit);
      if (selectedCategoryId != null) await _fetchMenus();
      final sdtInit = selectedDrinkTypeId;
      if (sdtInit != null) await _loadDrinkMenus(sdtInit);
      await _loadDesserts();
      // Load persisted selection from server (if any) so UI restores previous inputs
      try {
        await _loadCurrentSelectionFromServer();
      } catch (e) {
        if (kDebugMode) {
          print('Failed to load current selection from server: $e');
        }
      }
      // Ensure tempSelections always include meal/duration from persisted user
      try {
        final Map<String, dynamic> current = _auth.tempSelections != null
            ? Map<String, dynamic>.from(_auth.tempSelections!)
            : <String, dynamic>{};
        bool changed = false;
        if (!current.containsKey('meal')) {
          final m = _auth.user != null ? _auth.user!['meal'] : null;
          if (m != null) {
            current['meal'] = m;
            changed = true;
          }
        }
        if (!current.containsKey('duration')) {
          final d = _auth.user != null ? _auth.user!['duration'] : null;
          if (d != null) {
            current['duration'] = d;
            changed = true;
          }
        }
        if (changed) {
          _auth.setTempSelections(current);
        }
      } catch (e) {
        if (kDebugMode) print('Error updating tempSelections: $e');
      }
    } catch (e) {
      debugPrint('Failed to load saved selections: $e');
    }
  }

  Future<void> _loadCurrentSelectionFromServer() async {
    try {
      final res = await api.get('/user_selections/current');
      if (res.statusCode != 200) return;
      final Map<String, dynamic> body = jsonDecode(res.body);
      final us = body['user_selection'];
      if (us == null) return;
      // apply persisted ids
      setState(() {
        try {
          selectedFoodMenuId = us['selected_food_menu_id'] is int
              ? us['selected_food_menu_id'] as int
              : int.tryParse(us['selected_food_menu_id']?.toString() ?? '');
        } catch (_) {
          selectedFoodMenuId = null;
        }
        try {
          selectedDessertId = us['selected_dessert_menu_id'] is int
              ? us['selected_dessert_menu_id'] as int
              : int.tryParse(us['selected_dessert_menu_id']?.toString() ?? '');
        } catch (_) {
          selectedDessertId = null;
        }
        try {
          selectedDrinkMenuId = us['selected_drink_menu_id'] is int
              ? us['selected_drink_menu_id'] as int
              : int.tryParse(us['selected_drink_menu_id']?.toString() ?? '');
        } catch (_) {
          selectedDrinkMenuId = null;
        }

        // names and per-item calories
        try {
          foodController.text = (us['food_name_th'] ?? '').toString();
        } catch (_) {}
        try {
          dessertController.text = (us['dessert_name_th'] ?? '').toString();
        } catch (_) {}
        try {
          drinkController.text = (us['drink_name_th'] ?? '').toString();
        } catch (_) {}

        try {
          selectedFoodMenuCalories = (us['calculated_food_calories'] != null)
              ? ((us['calculated_food_calories'] as num).toInt())
              : (selectedFoodMenuCalories ?? 0);
        } catch (_) {}
        try {
          selectedDessertMenuCalories =
              (us['calculated_dessert_calories'] != null)
              ? ((us['calculated_dessert_calories'] as num).toInt())
              : (selectedDessertMenuCalories ?? 0);
        } catch (_) {}
        try {
          selectedDrinkMenuCalories = (us['calculated_drink_calories'] != null)
              ? ((us['calculated_drink_calories'] as num).toInt())
              : (selectedDrinkMenuCalories ?? 0);
        } catch (_) {}

        // update live-calculated display
        calculatedFoodCalories = (selectedFoodMenuCalories ?? 0).toDouble();
        calculatedDessertCalories = (selectedDessertMenuCalories ?? 0)
            .toDouble();
        calculatedDrinkCalories = (selectedDrinkMenuCalories ?? 0).toDouble();

        // restore lock state only after re-evaluating actual meal window
        try {
          _fieldsLocked = false;
        } catch (_) {}
      });
      _recomputeSelectedCalories();
      _refreshMealWindowState(mealValue: us['meal']);
      if (us['is_fulllock'] == true && us['next_meal_open_at'] != null) {
        try {
          final nextOpen = DateTime.parse(
            us['next_meal_open_at'].toString(),
          ).toLocal();
          final now = DateTime.now();
          if (nextOpen.isAfter(now)) {
            final secs = nextOpen.difference(now).inSeconds;
            _clearInputControllers();
            setState(() {
              _fieldsLocked = true;
            });
            _startCountdown(secs > 0 ? secs : 0);
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) print('Error loading current selection: $e');
    }
  }

  // ================= SAFE JSON HELPER =================
  List<dynamic> _toListSafe(dynamic val) {
    try {
      if (val == null) return [];
      if (val is List) return val;
      if (val is String) {
        final parsed = jsonDecode(val);
        if (parsed is List) return parsed;
        if (parsed is Map) {
          if (parsed['foods'] is List) return parsed['foods'];
          if (parsed['items'] is List) return parsed['items'];
        }
        return [];
      }
      if (val is Map) {
        for (final k in [
          'foods',
          'items',
          'data',
          'results',
          'desserts',
          'drinks',
        ]) {
          if (val[k] is List) return val[k];
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error parsing safe list: $e');
    }
    return [];
  }

  List<Map<String, dynamic>> _toListOfMap(dynamic val) {
    try {
      final lst = _toListSafe(val);
      return lst
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error converting to list of maps: $e');
      return [];
    }
  }

  // flag) and remove duplicates.
  List<Map<String, dynamic>> _filterDesserts(List<Map<String, dynamic>> list) {
    final filtered = list.where((e) {
      if (e.containsKey('is_dessert')) {
        final v = e['is_dessert'];
        if (v is int) return v == 1;
        if (v is bool) return v;
      }
      // fallback: if category field exists and equals 'dessert'
      if (e.containsKey('category')) {
        final c = e['category']?.toString().toLowerCase() ?? '';
        if (c == 'dessert' || c == 'ของหวาน') return true;
      }
      // otherwise keep it (best-effort) — but we'll still dedupe
      return true;
    }).toList();

    return _uniqueByName(filtered);
  }

  List<Map<String, dynamic>> _safeList(dynamic res, String key) {
    try {
      if (res == null) return [];
      // ApiResponse case (from ApiClient)
      if (res is ApiResponse) {
        if (res.statusCode != 200) return [];
        final j = jsonDecode(res.body);
        // try safe extraction using helpers
        if (j is Map && j.containsKey(key)) return _toListOfMap(j[key]);
        if (j is List) return _toListOfMap(j);
        return [];
      }
      // already decoded JSON map
      if (res is Map) {
        return _toListOfMap(res[key] ?? []);
      }
    } catch (_) {}
    return [];
  }

  List<Map<String, dynamic>> _uniqueByName(List<Map<String, dynamic>> list) {
    final Map<String, Map<String, dynamic>> seen = {};
    for (final e in list) {
      try {
        final name = (e['name'] ?? '').toString().trim().toLowerCase();
        if (name.isEmpty) continue;
        if (!seen.containsKey(name)) seen[name] = e;
      } catch (_) {}
    }
    return seen.values.toList();
  }

  List<Map<String, dynamic>> _sortByName(List<Map<String, dynamic>> list) {
    final copy = List<Map<String, dynamic>>.from(list);
    copy.sort((a, b) {
      final an = (a['name'] ?? '').toString().toLowerCase();
      final bn = (b['name'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });
    return copy;
  }

  List<Map<String, dynamic>> _orderFoodTypes(List<Map<String, dynamic>> list) {
    // Order food types according to a preferred sequence when possible.
    // Preferred sequence (top to bottom): โปรตีน, ผักและผลไม้, คาร์โบไฮเดตร
    final preferred = ['เมนูโปรตีน', 'เมนูผักและผลไม้', 'เมนูคาร์โบไฮเดตร'];
    final lowerToItems = <String, List<Map<String, dynamic>>>{};
    for (final e in list) {
      final name = (e['name'] ?? '').toString();
      final key = name.toLowerCase();
      lowerToItems.putIfAbsent(key, () => []).add(e);
    }

    final result = <Map<String, dynamic>>[];
    final used = <Map<String, dynamic>>[];

    for (final pref in preferred) {
      final key = pref.toLowerCase();
      if (lowerToItems.containsKey(key)) {
        for (final it in lowerToItems[key]!) {
          result.add(it);
          used.add(it);
        }
      }
    }

    // Append remaining items that weren't in preferred list (preserve their order)
    for (final e in list) {
      if (!used.contains(e)) result.add(e);
    }

    return result;
  }

  List<Map<String, dynamic>> _orderFoodCategories(
    int foodTypeId,
    List<Map<String, dynamic>> raw,
  ) {
    try {
      final ft = foodTypes.firstWhere(
        (e) =>
            (e['id'] is int
                ? e['id'] as int
                : int.tryParse(e['id']?.toString() ?? '')) ==
            foodTypeId,
        orElse: () => {},
      );
      final ftName = (ft['name'] ?? '').toString().trim().toLowerCase();

      // If this is the 'เมนูผักและผลไม้' type, apply a preferred ordering for its categories
      if (ftName == 'เมนูผักและผลไม้' || ftName == 'เมนู ผักและผลไม้') {
        final preferred = [
          'อาหารครบ5หมู่',
          'อาหารลดน้ำหนัก',
          'อาหารบำรุงสุขภาพ',
        ];

        final lowerToItems = <String, List<Map<String, dynamic>>>{};
        for (final e in raw) {
          final name = (e['name'] ?? '').toString();
          final key = name.trim().toLowerCase();
          lowerToItems.putIfAbsent(key, () => []).add(e);
        }

        final result = <Map<String, dynamic>>[];
        final used = <Map<String, dynamic>>[];

        for (final pref in preferred) {
          final key = pref.toLowerCase();
          if (lowerToItems.containsKey(key)) {
            for (final it in lowerToItems[key]!) {
              result.add(it);
              used.add(it);
            }
          }
        }

        for (final e in raw) {
          if (!used.contains(e)) result.add(e);
        }

        return result;
      }
    } catch (_) {}
    return raw;
  }

  // =============== Multi-condition filtering helper ===============
  String? _lastFilterRejectMessage;

  bool _itemMatchesSelection(Map<String, dynamic> item) {
    try {
      // Clear previous reject message unless this check sets a new one
      _lastFilterRejectMessage = null;

      // Helper to read bool-like field
      bool boolField(Map<String, dynamic> m, String key) {
        final v = m[key];
        if (v is bool) return v;
        if (v is int) return v == 1;
        if (v is String) return v.toLowerCase() == 'true' || v == '1';
        return false;
      }

      // 1) Food-type constraint (e.g., โปรตีน, ผัก, คาร์โบไฮเดรต)
      if (selectedFoodTypeId != null) {
        final ftName = _nameForId(foodTypes, selectedFoodTypeId).toLowerCase();
        if (ftName.contains('โปรตีน')) {
          final ok =
              boolField(item, 'contains_protein') ||
              (item['protein'] is num && (item['protein'] as num) > 0) ||
              boolField(item, 'high_protein');
          if (!ok) {
            _lastFilterRejectMessage = 'เมนูนี้ไม่เหมาะสมกับประเภทเมนูโปรตีน';
            try {
              debugPrint(
                '[filter] reject item: ${item['name'] ?? '<no-name>'} id=${item['id'] ?? '<no-id>'} reason=$_lastFilterRejectMessage (checked: contains_protein, protein>0, high_protein)',
              );
            } catch (_) {}
            return false;
          }
        } else if (ftName.contains('ผัก')) {
          final ok =
              boolField(item, 'is_vegetable') ||
              boolField(item, 'contains_vegetable') ||
              (item['vegetable_portion'] is num &&
                  (item['vegetable_portion'] as num) > 0);
          if (!ok) {
            _lastFilterRejectMessage = 'เมนูนี้ไม่เหมาะสมกับประเภทผัก/ผลไม้';
            try {
              debugPrint(
                '[filter] reject item: ${item['name'] ?? '<no-name>'} id=${item['id'] ?? '<no-id>'} reason=$_lastFilterRejectMessage (checked: is_vegetable, contains_vegetable, vegetable_portion)',
              );
            } catch (_) {}
            return false;
          }
        } else if (ftName.contains('คาร์โบ')) {
          final ok =
              boolField(item, 'contains_carb') ||
              (item['carbs'] is num && (item['carbs'] as num) > 0) ||
              boolField(item, 'is_carb');
          if (!ok) {
            _lastFilterRejectMessage = 'เมนูนี้ไม่เหมาะสมกับประเภทคาร์โบไฮเดรต';
            try {
              debugPrint(
                '[filter] reject item: ${item['name'] ?? '<no-name>'} id=${item['id'] ?? '<no-id>'} reason=$_lastFilterRejectMessage (checked: contains_carb, carbs>0, is_carb)',
              );
            } catch (_) {}
            return false;
          }
        }
      }

      // 2) Category / health-goal constraint (e.g., ครบ5หมู่, ลดน้ำหนัก, สร้างกล้ามเนื้อ)
      // Determine a label from either typed category or selectedCategoryId
      String catLabel = '';
      if ((categoryController.text.trim()).isNotEmpty) {
        catLabel = categoryController.text.trim().toLowerCase();
      } else if (selectedCategoryId != null) {
        catLabel = _nameForId(foodCategories, selectedCategoryId).toLowerCase();
      }
      if (catLabel.isEmpty) {
        final shgl4 = selectedHealthGoalLabel;
        if (shgl4 != null) catLabel = shgl4.trim().toLowerCase();
      }

      if (catLabel.isNotEmpty) {
        if (catLabel.contains('ครบ') ||
            catLabel.contains('ครบ5') ||
            catLabel.contains('ครบ 5') ||
            catLabel.contains('ครบ5หมู่')) {
          final ok =
              boolField(item, 'is_complete_meal') ||
              boolField(item, 'is_complete') ||
              (item['meal_components'] is int &&
                  (item['meal_components'] as int) >= 5);
          if (!ok) {
            _lastFilterRejectMessage =
                'เมนูนี้ไม่เหมาะสมกับหมวดอาหารครบ 5 หมู่';
            try {
              debugPrint(
                '[filter] reject item: ${item['name'] ?? '<no-name>'} id=${item['id'] ?? '<no-id>'} reason=$_lastFilterRejectMessage (checked: is_complete_meal, is_complete, meal_components>=5)',
              );
            } catch (_) {}
            return false;
          }
        } else if (catLabel.contains('ลดน้ำหนัก') ||
            catLabel.contains('ลด น้ำหนัก')) {
          final ok =
              boolField(item, 'is_for_weight_loss') ||
              boolField(item, 'low_cal') ||
              (item['calories'] is num && (item['calories'] as num) <= 400);
          if (!ok) {
            _lastFilterRejectMessage = 'เมนูนี้ไม่เหมาะสำหรับการลดน้ำหนัก';
            try {
              debugPrint(
                '[filter] reject item: ${item['name'] ?? '<no-name>'} id=${item['id'] ?? '<no-id>'} reason=$_lastFilterRejectMessage (checked: is_for_weight_loss, low_cal, calories<=400)',
              );
            } catch (_) {}
            return false;
          }
        } else if (catLabel.contains('สร้างกล้าม') ||
            catLabel.contains('เพิ่มกล้าม')) {
          final ok =
              boolField(item, 'is_muscle_gain') ||
              boolField(item, 'high_protein') ||
              (item['protein'] is num && (item['protein'] as num) >= 20);
          if (!ok) {
            _lastFilterRejectMessage =
                'เมนูนี้ไม่เหมาะสำหรับการสร้างกล้ามเนื้อ';
            try {
              debugPrint(
                '[filter] reject item: ${item['name'] ?? '<no-name>'} id=${item['id'] ?? '<no-id>'} reason=$_lastFilterRejectMessage (checked: is_muscle_gain, high_protein, protein>=20)',
              );
            } catch (_) {}
            return false;
          }
        } else if (catLabel.contains('บำรุง') ||
            catLabel.contains('บำรุงสุขภาพ') ||
            catLabel.contains('สุขภาพ')) {
          final ok =
              boolField(item, 'is_health_food') ||
              boolField(item, 'is_for_health') ||
              (item['fiber'] is num && (item['fiber'] as num) > 2);
          if (!ok) {
            _lastFilterRejectMessage = 'เมนูนี้ไม่เหมาะสำหรับการบำรุงสุขภาพ';
            try {
              debugPrint(
                '[filter] reject item: ${item['name'] ?? '<no-name>'} id=${item['id'] ?? '<no-id>'} reason=$_lastFilterRejectMessage (checked: is_health_food, is_for_health, fiber>2)',
              );
            } catch (_) {}
            return false;
          }
        } else if (catLabel.contains('พลังงาน') ||
            catLabel.contains('ให้พลังงาน') ||
            catLabel.contains('ให้พลังงานสูง')) {
          final ok =
              boolField(item, 'is_high_energy') ||
              (item['calories'] is num && (item['calories'] as num) >= 500) ||
              boolField(item, 'high_energy');
          if (!ok) {
            _lastFilterRejectMessage = 'เมนูนี้ไม่เหมาะสำหรับหมวดให้พลังงานสูง';
            try {
              debugPrint(
                '[filter] reject item: ${item['name'] ?? '<no-name>'} id=${item['id'] ?? '<no-id>'} reason=$_lastFilterRejectMessage (checked: is_high_energy, calories>=500, high_energy)',
              );
            } catch (_) {}
            return false;
          }
        }
      }

      // If no failing check, accept the item
      return true;
    } catch (_) {
      // conservative: if any error, allow the item so UX not overly restrictive
      _lastFilterRejectMessage = null;
      return true;
    }
  }

  // ================= API LOADERS =================

  // Safe wrapper for API GETs: catches exceptions and shows user-friendly snackbar
  Future<dynamic> _safeApiGet(String path, {String? userMessage}) async {
    try {
      final res = await api.get(path);
      if (res.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userMessage ?? 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์'),
            ),
          );
        }
        return null;
      }
      return res;
    } catch (e) {
      debugPrint('[api] request failed $path: $e');
      // Only show a SnackBar for likely network errors — for unexpected
      // response shapes (JSON parsing, null bodies, etc.) prefer a silent
      // fallback to avoid crashing the UI with a modal error.
      final msg = e.toString().toLowerCase();
      final isNetworkError =
          msg.contains('socket') ||
          msg.contains('network') ||
          msg.contains('timeout') ||
          msg.contains('handshake') ||
          msg.contains('tls');
      if (mounted && isNetworkError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage ?? 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์'),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _loadFoodTypes() async {
    // clear previous list immediately and refresh UI
    setState(() {
      allFoodTypes = [];
      foodTypes = [];
      selectedFoodTypeId = null;
    });

    String path = "/api/food-types";
    try {
      final uid = (_auth.user != null && _auth.user!["id"] != null)
          ? _auth.user!["id"].toString()
          : null;
      if (uid != null) path += '?user_id=${Uri.encodeComponent(uid)}';
    } catch (_) {}
    final res = await _safeApiGet(
      path,
      userMessage: 'ไม่สามารถโหลดหมวดหมู่อาหารได้',
    );
    if (res == null) return;
    setState(() {
      final list = _orderFoodTypes(
        _sortByName(_uniqueByName(_safeList(res, "food-types"))),
      );
      allFoodTypes = List<Map<String, dynamic>>.from(list);
      foodTypes = list;
      // If server returned exactly one, auto-select and lock the control
      if (foodTypes.length == 1) {
        try {
          final idVal = foodTypes[0]['id'] is int
              ? foodTypes[0]['id'] as int
              : int.tryParse(foodTypes[0]['id']?.toString() ?? '');
          if (idVal != null) {
            selectedFoodTypeId = idVal;
            foodTypeController.text = foodTypes[0]['name']?.toString() ?? '';
          }
        } catch (e) {
          if (kDebugMode) print('Choose_food_type_page caught error: $e');
        }
      }
    });
  }

  void _applyHealthGoalFilter() {
    try {
      String goal = '';
      final shgl5 = selectedHealthGoalLabel;
      final shgg5 = selectedHealthGoalGroup;
      if (shgl5 != null && shgl5.trim().isNotEmpty) {
        goal = shgl5;
      } else if (shgg5 != null && shgg5.trim().isNotEmpty) {
        goal = shgg5;
      } else {
        try {
          goal = (_auth.user != null && _auth.user!['health_goal'] != null)
              ? _auth.user!['health_goal'].toString()
              : '';
        } catch (_) {}
      }
      final g = goal.toLowerCase();
      if (g.contains('สร้างกล้าม') ||
          g.contains('เพิ่มกล้าม') ||
          g.contains('สร้าง กล้าม')) {
        final prot = allFoodTypes.where((e) {
          final n = (e['name'] ?? '').toString().toLowerCase();
          return n.contains('โปรตีน') || n.contains('protein');
        }).toList();
        if (prot.isNotEmpty) {
          setState(() {
            foodTypes = prot;
            // if only one protein type, auto-select it
            if (foodTypes.length == 1) {
              final idVal = foodTypes[0]['id'] is int
                  ? foodTypes[0]['id'] as int
                  : int.tryParse(foodTypes[0]['id']?.toString() ?? '');
              if (idVal != null) {
                selectedFoodTypeId = idVal;
                foodTypeController.text =
                    foodTypes[0]['name']?.toString() ?? '';
                // load categories for this type asynchronously
                _loadFoodCategories(idVal);
              }
            }
          });
        }
      } else {
        setState(() {
          foodTypes = _orderFoodTypes(_sortByName(_uniqueByName(allFoodTypes)));
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFoodCategories(int foodTypeId) async {
    final res = await _safeApiGet(
      "/api/food-categories?food_type_id=$foodTypeId",
      userMessage: 'ไม่สามารถโหลดหมวดย่อยได้',
    );
    if (res == null) return;
    setState(() {
      final raw = _sortByName(_uniqueByName(_safeList(res, "food-categories")));
      foodCategories = _orderFoodCategories(foodTypeId, raw);

      // If the caller cleared `selectedCategoryId` before calling (user
      // actively changed food type), keep the clearing behavior. But when
      // loading during init from persisted selections, preserving the
      // existing `selectedCategoryId` helps show the saved value inside
      // the dropdown instead of wiping it.
      if (selectedCategoryId == null) {
        foodMenus = [];
        selectedFoodMenuId = null;
      }

      // If there's a health goal label passed from previous page, try to
      // preselect the matching category by name (case-insensitive). If no
      // matching id exists, preserve the label in the controller instead
      // of assigning a synthetic numeric id.
      if (selectedCategoryId == null) {
        final shgl6 = selectedHealthGoalLabel;
        if (shgl6 != null) {
          final label = shgl6.trim();
          if (label.isNotEmpty) {
            final match = foodCategories.firstWhere(
              (e) =>
                  (e['name'] ?? '').toString().toLowerCase() ==
                  label.toLowerCase(),
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              final id = match['id'] is int
                  ? match['id'] as int
                  : int.tryParse(match['id'].toString());
              if (id != null) selectedCategoryId = id;
            } else {
              categoryController.text = label;
              selectedCategoryId = null;
            }
          }
        }
      }
    });
  }

  Future<void> _loadFoodMenus(int categoryId) async {
    // Request only savory foods for this category (explicitly exclude desserts)
    try {
      // Build query with category, exclude desserts, and include food_type when available
      String qs = '?is_dessert=false';
      if (categoryId > 0) {
        qs = '?category_id=$categoryId&is_dessert=false';
      }
      final sft = selectedFoodTypeId;
      if (sft != null && sft > 0) qs += '&food_type_id=$sft';
      // If food type name indicates 'protein', request nutrition tag filter
      try {
        final sft2 = selectedFoodTypeId;
        final ftName = sft2 != null
            ? _nameForId(foodTypes, sft2).toLowerCase()
            : '';
        if (ftName.contains('โปรตีน') || ftName.contains('protein')) {
          qs += '&nutrition_tags=protein';
        }
      } catch (_) {}
      final res = await _safeApiGet(
        '/api/menus$qs',
        userMessage: 'ไม่สามารถโหลดเมนูอาหารได้',
      );
      List<Map<String, dynamic>> newFoods = [];
      // We will not consume desserts from this endpoint to avoid mixing; desserts
      // must be loaded from the dedicated dessert_menus endpoint via _loadDesserts().
      List<Map<String, dynamic>> newDesserts = [];
      List<Map<String, dynamic>> newDrinks = [];
      if (res != null && res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final f = _toListOfMap(j['foods']);
        final dr = _toListOfMap(j['drinks']);
        newFoods = _sortByName(_uniqueByName(f));
        newDrinks = _sortByName(_uniqueByName(dr));
      }

      setState(() {
        // Apply multi-condition filtering when relevant selections exist
        _lastFilterRejectMessage = null;
        List<Map<String, dynamic>> applyFilterIfNeeded(
          List<Map<String, dynamic>> inList,
        ) {
          final shgl7 = selectedHealthGoalLabel;
          if (selectedFoodTypeId == null &&
              (categoryController.text.trim()).isEmpty &&
              (shgl7 == null || shgl7.trim().isEmpty)) {
            return inList;
          }
          return inList.where((it) => _itemMatchesSelection(it)).toList();
        }

        // Enforce strict category inclusion: only include food items that belong
        // to the selected category. Match on numeric `category_id` when present
        // or on the string `category` name as a fallback.
        bool matchesCategory(Map<String, dynamic> it) {
          try {
            final raw = it['category_id'];
            int? cid;
            if (raw is int) {
              cid = raw;
            } else if (raw is String) {
              cid = int.tryParse(raw);
            }
            if (cid != null) return cid == categoryId;
            final catName = (it['category'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final selName = _nameForId(
              foodCategories,
              categoryId,
            ).toLowerCase();
            return catName.isNotEmpty &&
                selName.isNotEmpty &&
                catName == selName;
          } catch (_) {
            return false;
          }
        }

        final filteredFoods = newFoods
            .where((e) => matchesCategory(e))
            .toList();
        foodMenus = applyFilterIfNeeded(filteredFoods);

        // Do not clear desserts/drinks here: keep each section independent so
        // users can search/select across food/dessert/drink without interference.

        try {
          debugPrint(
            '[menus] category=$categoryId rawFoods=${newFoods.length} filteredFoods=${foodMenus.length} rawDesserts=${newDesserts.length} filteredDesserts=${desserts.length} rawDrinks=${newDrinks.length} filteredDrinks=${drinks.length}',
          );
          if ((newFoods.isNotEmpty ||
                  newDesserts.isNotEmpty ||
                  newDrinks.isNotEmpty) &&
              (foodMenus.isEmpty && desserts.isEmpty && drinks.isEmpty)) {
            debugPrint(
              '[menus] all items filtered out for category=$categoryId; lastReject="${_lastFilterRejectMessage ?? '<none>'}"',
            );
          }
        } catch (_) {}

        // If original lists had items but filtering removed them all, provide a default message
        // If original foods (from server) existed but category filtering removed them,
        // show a helpful message.
        if (newFoods.isNotEmpty && foodMenus.isEmpty) {
          _lastFilterRejectMessage ??=
              'ไม่พบรายการอาหารที่ตรงตามหมวดหมู่ที่เลือก';
        }

        // Preserve a previously-restored selectedFoodMenuId if it exists in
        // the newly-loaded list; otherwise clear it.
        if (selectedFoodMenuId != null) {
          final exists = foodMenus.any((e) {
            final id = e['id'] is int
                ? e['id'] as int
                : int.tryParse(e['id'].toString());
            return id == selectedFoodMenuId;
          });
          if (!exists) selectedFoodMenuId = null;
        }

        // clear any existing search suggestions when explicit menus load
        searchedFoodMenus = [];
        searchedDesserts = [];
        searchedDrinks = [];
      });
    } catch (e) {
      debugPrint('[_loadFoodMenus] error: $e');
      setState(() {
        foodMenus = [];
        searchedFoodMenus = [];
        searchedDesserts = [];
        searchedDrinks = [];
      });
    }
  }

  // Wrapper to fetch menus using the currently selectedCategoryId.
  // Skips fetching for null or synthetic placeholder ids (e.g., -999999).
  Future<void> _fetchMenus() async {
    final cid = selectedCategoryId;
    if (cid == null) return;
    try {
      await _loadFoodMenus(cid);
    } catch (e) {
      debugPrint('[_fetchMenus] error: $e');
    }
  }

  Future<void> _loadDrinkTypes() async {
    final res = await _safeApiGet(
      "/api/drink-types",
      userMessage: 'ไม่สามารถโหลดประเภทเครื่องดื่มได้',
    );
    if (res == null) return;
    setState(() {
      drinkTypes = _sortByName(_uniqueByName(_safeList(res, "drink-types")));
    });
  }

  Future<void> _loadDrinkMenus(int drinkTypeId) async {
    try {
      if (drinkTypeId <= 0) return;
      final res = await _safeApiGet(
        '/api/menus?drink_type_id=$drinkTypeId',
        userMessage: 'ไม่สามารถโหลดเมนูเครื่องดื่มได้',
      );
      List<Map<String, dynamic>> newDrinks = [];
      if (res != null) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final dr = _toListOfMap(j['drinks']);
        newDrinks = _sortByName(_uniqueByName(dr));
      }

      setState(() {
        drinkMenus = newDrinks;
        if (selectedDrinkMenuId != null) {
          final exists = drinkMenus.any((e) {
            final id = e['id'] is int
                ? e['id'] as int
                : int.tryParse(e['id'].toString());
            return id == selectedDrinkMenuId;
          });
          if (!exists) selectedDrinkMenuId = null;
        }
      });
    } catch (e) {
      debugPrint('[_loadDrinkMenus] error: $e');
      setState(() {
        drinkMenus = [];
        selectedDrinkMenuId = null;
      });
    }
  }

  Future<void> _loadDesserts() async {
    // Load desserts independently; if a foodType is selected include it as a hint
    String path = '/api/dessert-menus';
    final sft4 = selectedFoodTypeId;
    if (sft4 != null && sft4 > 0) {
      path += '?food_type_id=$sft4';
    }
    final res = await _safeApiGet(
      path,
      userMessage: 'ไม่สามารถโหลดเมนูของหวานได้',
    );
    if (res == null) return;
    setState(() {
      // Filter to actual desserts and dedupe by name
      desserts = _sortByName(_filterDesserts(_safeList(res, "desserts")));
      if (selectedDessertId != null) {
        final exists = desserts.any((e) {
          final id = e['id'] is int
              ? e['id'] as int
              : int.tryParse(e['id'].toString());
          return id == selectedDessertId;
        });
        if (!exists) selectedDessertId = null;
      }
    });
  }

  // ================= UI HELPERS =================

  double _parseNumericValue(dynamic raw) {
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0.0;
  }

  int _getEffectiveQuantity(int? selectedQty, int fallbackQty) {
    return selectedQty ?? fallbackQty;
  }

  double _getTotalSelectedCalories() {
    double total = 0.0;
    try {
      final int foodQty = _getEffectiveQuantity(selectedFoodQty, foodQuantity);
      final int dessertQty =
          _getEffectiveQuantity(selectedDessertQty, dessertQuantity);
      final int drinkQty = _getEffectiveQuantity(selectedDrinkQty, drinkQuantity);

      if (calculatedFoodCalories != null && calculatedFoodCalories! > 0.0) {
        total += calculatedFoodCalories!;
      } else if (selectedFoodMenuCalories != null && selectedFoodMenuCalories! > 0) {
        total += selectedFoodMenuCalories!.toDouble() * foodQty;
      } else if (matchedFood != null) {
        final cal = _parseNumericValue(
          matchedFood?['calories'] ?? matchedFood?['kcal'],
        );
        total += cal * foodQty;
      }

      if (calculatedDessertCalories != null && calculatedDessertCalories! > 0.0) {
        total += calculatedDessertCalories!;
      } else if (selectedDessertMenuCalories != null &&
          selectedDessertMenuCalories! > 0) {
        total += selectedDessertMenuCalories!.toDouble() * dessertQty;
      } else if (matchedDessert != null) {
        final cal = _parseNumericValue(
          matchedDessert?['calories'] ?? matchedDessert?['kcal'],
        );
        total += cal * dessertQty;
      }

      if (calculatedDrinkCalories != null && calculatedDrinkCalories! > 0.0) {
        total += calculatedDrinkCalories!;
      } else if (selectedDrinkMenuCalories != null &&
          selectedDrinkMenuCalories! > 0) {
        total += selectedDrinkMenuCalories!.toDouble() * drinkQty;
      } else if (matchedDrink != null) {
        final cal = _parseNumericValue(
          matchedDrink?['calories'] ?? matchedDrink?['kcal'],
        );
        total += cal * drinkQty;
      }
    } catch (_) {}
    return total;
  }

  // New state for enhanced features
  double? _giRating;
  double? _satietyScore;
  bool _showBehavioralNudge = false;
  List<Map<String, dynamic>> _nudgeAlternatives = [];

  double _getTotalSelectedSugar() {
    double total = 0.0;
    try {
      final int foodQty = _getEffectiveQuantity(selectedFoodQty, foodQuantity);
      final int dessertQty =
          _getEffectiveQuantity(selectedDessertQty, dessertQuantity);
      final int drinkQty = _getEffectiveQuantity(selectedDrinkQty, drinkQuantity);

      if (matchedFood != null) {
        final v = matchedFood?['sugar_g'] ?? matchedFood?['sugar'];
        total += _parseNumericValue(v) * foodQty;
      } else if (selectedFoodMenuId != null) {
        final found = foodMenus.firstWhere(
          (e) =>
              (e['id'] is int
                  ? e['id'] as int
                  : int.tryParse(e['id']?.toString() ?? '')) ==
              selectedFoodMenuId,
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          final v = found['sugar_g'] ?? found['sugar'];
          total += _parseNumericValue(v) * foodQty;
        }
      }

      if (matchedDessert != null) {
        final v = matchedDessert?['sugar_g'] ?? matchedDessert?['sugar'];
        total += _parseNumericValue(v) * dessertQty;
      } else if (selectedDessertId != null) {
        final found = desserts.firstWhere(
          (e) =>
              (e['id'] is int
                  ? e['id'] as int
                  : int.tryParse(e['id']?.toString() ?? '')) ==
              selectedDessertId,
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          final v = found['sugar_g'] ?? found['sugar'];
          total += _parseNumericValue(v) * dessertQty;
        }
      }

      if (matchedDrink != null) {
        final v = matchedDrink?['sugar_g'] ?? matchedDrink?['sugar'];
        total += _parseNumericValue(v) * drinkQty;
      } else if (selectedDrinkMenuId != null) {
        final found = drinkMenus.firstWhere(
          (e) =>
              (e['id'] is int
                  ? e['id'] as int
                  : int.tryParse(e['id']?.toString() ?? '')) ==
              selectedDrinkMenuId,
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          final v = found['sugar_g'] ?? found['sugar'];
          total += _parseNumericValue(v) * drinkQty;
        }
      }
    } catch (_) {}
    return total;
  }

  Widget _buildBulletRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(fontSize: 14, color: Colors.black87)),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  int _getTotalSelectedSodium() {
    int total = 0;
    try {
      final int foodQty = _getEffectiveQuantity(selectedFoodQty, foodQuantity);
      if (matchedFood != null) {
        final v =
            matchedFood?['sodium'] ??
            matchedFood?['sodium_mg'] ??
            matchedFood?['salt_mg'];
        total += (int.tryParse((v?.toString() ?? '0')) ?? 0) * foodQty;
      } else if (selectedFoodMenuId != null) {
        final found = foodMenus.firstWhere(
          (e) =>
              (e['id'] is int
                  ? e['id'] as int
                  : int.tryParse(e['id']?.toString() ?? '')) ==
              selectedFoodMenuId,
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          final v = found['sodium'] ?? found['sodium_mg'] ?? found['salt_mg'];
          total += (int.tryParse((v?.toString() ?? '0')) ?? 0) * foodQty;
        }
      }

      final int dessertQty =
          _getEffectiveQuantity(selectedDessertQty, dessertQuantity);
      if (matchedDessert != null) {
        final v =
            matchedDessert?['sodium'] ??
            matchedDessert?['sodium_mg'] ??
            matchedDessert?['salt_mg'];
        total += (int.tryParse((v?.toString() ?? '0')) ?? 0) * dessertQty;
      } else if (selectedDessertId != null) {
        final found = desserts.firstWhere(
          (e) =>
              (e['id'] is int
                  ? e['id'] as int
                  : int.tryParse(e['id']?.toString() ?? '')) ==
              selectedDessertId,
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          final v = found['sodium'] ?? found['sodium_mg'] ?? found['salt_mg'];
          total += (int.tryParse((v?.toString() ?? '0')) ?? 0) * dessertQty;
        }
      }

      final int drinkQty =
          _getEffectiveQuantity(selectedDrinkQty, drinkQuantity);
      if (matchedDrink != null) {
        final v =
            matchedDrink?['sodium'] ??
            matchedDrink?['sodium_mg'] ??
            matchedDrink?['salt_mg'];
        total += (int.tryParse((v?.toString() ?? '0')) ?? 0) * drinkQty;
      } else if (selectedDrinkMenuId != null) {
        final found = drinkMenus.firstWhere(
          (e) =>
              (e['id'] is int
                  ? e['id'] as int
                  : int.tryParse(e['id']?.toString() ?? '')) ==
              selectedDrinkMenuId,
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          final v = found['sodium'] ?? found['sodium_mg'] ?? found['salt_mg'];
          total += (int.tryParse((v?.toString() ?? '0')) ?? 0) * drinkQty;
        }
      }
    } catch (_) {}
    return total;
  }

  // Compute a lightweight GI and satiety estimate based on selected items
  void _computeGiAndSatiety() {
    try {
      double giSum = 0.0;
      double satSum = 0.0;
      int count = 0;
      void addFrom(
        Map<String, dynamic>? it,
        double defaultGi,
        double defaultSat,
      ) {
        if (it == null) return;
        try {
          final g =
              double.tryParse(
                (it['gi'] ??
                        it['glycemic_index'] ??
                        it['gi_rating'] ??
                        defaultGi)
                    .toString(),
              ) ??
              defaultGi;
          final sat =
              double.tryParse(
                (it['satiety_score'] ?? it['satiety'] ?? defaultSat).toString(),
              ) ??
              defaultSat;
          giSum += g;
          satSum += sat;
          count += 1;
        } catch (_) {}
      }

      addFrom(matchedFood, 50.0, 50.0);
      addFrom(matchedDessert, 60.0, 40.0);
      addFrom(matchedDrink, 65.0, 30.0);
      if (count > 0) {
        _giRating = giSum / count;
        _satietyScore = satSum / count * 1.0;
      } else {
        _giRating = null;
        _satietyScore = null;
      }
    } catch (_) {
      _giRating = null;
      _satietyScore = null;
    }
  }

  // ponytail: combo-safety filtering happens per-item via _validateNutritionAndGoal;
  // this heuristic never had a UI consumer for its result, so it's a no-op call site
  // kept intact rather than touching its ~13 callers. Wire up a consumer to revive it.
  void _applyComboFilters() {}

  // Find lightweight alternative suggestions for a flagged item.
  List<Map<String, dynamic>> _findSmartSwaps(Map<String, dynamic> badItem) {
    final List<Map<String, dynamic>> candidates = [];
    try {
      final name = (badItem['name'] ?? '').toString().toLowerCase();
      // Prefer same-category items with lower calories and marked safe
      final source =
          (name.contains('drink') ||
              (badItem['category'] ?? '').toString().toLowerCase().contains(
                'drink',
              ))
          ? drinks
          : (name.contains('dessert') ||
                (badItem['category'] ?? '').toString().toLowerCase().contains(
                  'dessert',
                ))
          ? desserts
          : foodMenus;
      for (final it in source) {
        try {
          final safe = (it['safe'] is bool)
              ? it['safe'] as bool
              : (it['safe'] is int ? (it['safe'] as int) == 1 : true);
          final cal =
              double.tryParse(
                (it['calories'] ?? it['kcal'] ?? '0').toString(),
              ) ??
              0.0;
          if (safe &&
              cal > 0 &&
              cal <=
                  (double.tryParse((badItem['calories'] ?? '0').toString()) ??
                      9999)) {
            candidates.add(Map<String, dynamic>.from(it));
            if (candidates.length >= 6) break;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return candidates;
  }

  Widget _userProfileSelectionCard() {
    final authService = _auth;
    final user = authService.user ?? {};
    final sels =
        authService.tempSelections ?? authService.guestSelections ?? {};

    final gender = (user['gender'] ?? user['sex'] ?? sels['gender'] ?? '')
        .toString();
    final age = (user['age'] ?? sels['age'] ?? '').toString();
    final dob = (user['date_of_birth'] ?? sels['date_of_birth'] ?? '')
        .toString();
    final weight = (user['weight'] ?? sels['weight'] ?? '').toString();
    final height = (user['height'] ?? sels['height'] ?? '').toString();

    final bmi = (user['bmi'] ?? user['bmi_value'] ?? '').toString();
    final bmiStatus = (user['bmi_status'] ?? user['bmiStatus'] ?? '')
        .toString();
    final recommendedCal =
        (user['recommended_calories'] ?? user['recommendedCalories'] ?? '')
            .toString();

    // Defensive: some upstream paths can leave the literal string "null"
    // (not a real null) in these fields -- treat it the same as empty/'ไม่มี'
    // so it never renders as text (same guard used in choose_a_health_goal.dart).
    var chronic = (user['chronic_diseases'] ?? user['chronicDiseases'] ?? '')
        .toString()
        .trim();
    if (chronic.toLowerCase() == 'null') chronic = '';
    var allergies = (user['food_allergies'] ?? user['allergies'] ?? '')
        .toString()
        .trim();
    if (allergies.toLowerCase() == 'null') allergies = '';

    final meal = (sels['meal'] ?? sels['selected_meal'] ?? user['meal'] ?? '')
        .toString();
    final duration = (sels['duration'] ?? user['duration'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  alignment: WrapAlignment.start,
                  children: [
                    Text(
                      'เพศ: ${gender.isNotEmpty ? gender : '-'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'อายุ: ${age.isNotEmpty ? age : '-'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'วันเกิด: ${dob.isNotEmpty ? dob : '-'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'น้ำหนัก: ${weight.isNotEmpty ? weight : '-'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'ส่วนสูง: ${height.isNotEmpty ? height : '-'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'BMI: ${bmi.isNotEmpty ? bmi : '-'}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bmiStatus.isNotEmpty ? bmiStatus : '-',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: bmiStatus.contains('ผอม')
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: bmiStatus.contains('ผอม')
                          ? Colors.orange
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'แคลอรีอ้างอิง: ${recommendedCal.isNotEmpty ? recommendedCal : '-'} kcal',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'มื้อ: ${meal.isNotEmpty ? meal : '-'}',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  Text(
                    'ระยะเวลา: ${duration.isNotEmpty ? duration : '-'} วัน',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (chronic.isNotEmpty && chronic.toLowerCase() != 'ไม่มี')
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'โรคประจำตัว: $chronic',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (allergies.isNotEmpty && allergies.toLowerCase() != 'ไม่มี')
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'แพ้อาหาร: $allergies',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _healthSummaryCard() {
    final total = _getTotalSelectedCalories();
    // Use AuthService from Provider to read live user profile
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.user ?? {};
    // recommended calories (fallback to 2000)
    final double recommendedCalories = (user['recommended_calories'] != null)
        ? double.tryParse(user['recommended_calories'].toString()) ?? 2000.0
        : 2000.0;
    // recompute GI/satiety before rendering
    _computeGiAndSatiety();
    // เป้าหมายต่อวัน = recommended_calories ตรงๆ (ปรับตามเป้าหมายน้ำหนักแล้วจากฝั่งเซิร์ฟเวอร์
    // — ตัวเลขเดียวกับที่หน้าเลือกมื้ออาหาร/สรุปผลอ่านมาแสดง ไม่ใช่โควตาต่อมื้อแยกคำนวณเอง)
    final int quota = recommendedCalories.round();
    final progress = quota > 0 ? (total / quota).clamp(0.0, 1.0) : 0.0;
    final tags = <Widget>[];
    if ((selectedHealthGoalLabel ?? user['health_goal']) != null) {
      final label =
          (selectedHealthGoalLabel ?? user['health_goal'])?.toString() ?? '';
      if (label.isNotEmpty) tags.add(Chip(label: Text('🎯 $label')));
    }
    try {
      // Show health_goal_group as the second chip (purple) or an orange warning if absent
      final String goalGroup = (user['health_goal_group'] ?? '').toString();
      if (goalGroup.isNotEmpty) {
        tags.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.purple),
            ),
            child: Text(
              goalGroup,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        );
      } else {
        tags.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange),
            ),
            child: Text(
              '⚠️ ไม่มี',
              style: TextStyle(color: Colors.orange[800]),
            ),
          ),
        );
      }
    } catch (_) {}

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'สรุปเป้าหมายด้านสุขภาพ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'แคลอรีที่เลือกไปแล้ว / เป้าหมายต่อวัน',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${total.toStringAsFixed(0)} / $quota kcal วันนี้',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(children: [Icon(Icons.favorite, color: primaryGreen)]),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: AppColors.card,
                valueColor: AlwaysStoppedAnimation(primaryGreen),
              ),
            ),
            const SizedBox(height: 10),
            if (tags.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 6, children: tags),
            const SizedBox(height: 10),
            // Nutrition quick summary: sugar (g) and sodium (mg)
            Builder(
              builder: (_) {
                final totalSugar = _getTotalSelectedSugar();
                final totalSodium = _getTotalSelectedSodium();
                // compute user-specific limits
                double maxSugar = 65.0;
                int maxSodium = 2000;
                try {
                  final cds = (user['chronic_diseases'] ?? '')
                      .toString()
                      .toLowerCase();
                  if (cds.contains('ความดัน') || cds.contains('ไต')) {
                    maxSodium = 1500;
                  }
                  if (cds.contains('เบาหวาน')) maxSugar = 24.0;
                } catch (_) {}

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'น้ำตาล: ${totalSugar.toStringAsFixed(1)} g / ${maxSugar.toStringAsFixed(1)} g',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'โซเดียม: $totalSodium mg / $maxSodium mg',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            // Chronic disease micro-targeting: CKD (phosphorus/potassium) and Hypertension tips
            Builder(
              builder: (_) {
                try {
                  final cds = (user['chronic_diseases'] ?? '')
                      .toString()
                      .toLowerCase();
                  if (cds.contains('ไต') || cds.contains('ckd')) {
                    // sum potassium/phosphorus from selected items when available
                    double pot = 0.0;
                    double phos = 0.0;
                    void addIfExists(Map<String, dynamic>? it) {
                      if (it == null) return;
                      try {
                        pot +=
                            double.tryParse(
                              (it['potassium_mg'] ??
                                      it['potassium'] ??
                                      it['k'] ??
                                      '0')
                                  .toString(),
                            ) ??
                            0.0;
                        phos +=
                            double.tryParse(
                              (it['phosphorus_mg'] ??
                                      it['phosphorus'] ??
                                      it['p'] ??
                                      '0')
                                  .toString(),
                            ) ??
                            0.0;
                      } catch (_) {}
                    }

                    addIfExists(matchedFood);
                    addIfExists(matchedDessert);
                    addIfExists(matchedDrink);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CKD Alert — Potassium: ${pot.toStringAsFixed(0)} mg, Phosphorus: ${phos.toStringAsFixed(0)} mg',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    );
                  }
                } catch (_) {}
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 8),
            // Display drink-specific goal and types inside the same summary card
            const SizedBox(height: 6),
            // compute display strings here (use `user` from authService scope)
            Builder(
              builder: (_) {
                final String? displayDrinkGoal =
                    (healthGoalDrink != null &&
                        healthGoalDrink!.trim().isNotEmpty)
                    ? healthGoalDrink
                    : (user['health_goal_drink']?.toString());
                String drinkTypesStr = '';
                if (healthGoalDrinkTypes.isNotEmpty) {
                  drinkTypesStr = healthGoalDrinkTypes.join(', ');
                } else {
                  final dyn = user['health_goal_drink_types'];
                  try {
                    if (dyn is List) {
                      drinkTypesStr = dyn.map((e) => e.toString()).join(', ');
                    } else if (dyn is String) {
                      final parsed = jsonDecode(dyn);
                      if (parsed is List) {
                        drinkTypesStr = parsed
                            .map((e) => e.toString())
                            .join(', ');
                      } else {
                        drinkTypesStr = dyn;
                      }
                    }
                  } catch (_) {
                    if (dyn is String) drinkTypesStr = dyn;
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBulletRow(
                      'เป้าหมายเครื่องดื่ม: ${displayDrinkGoal ?? 'ไม่ได้ระบุ'}',
                    ),
                    const SizedBox(height: 6),
                    _buildBulletRow(
                      'ประเภทเครื่องดื่ม: ${drinkTypesStr.isEmpty ? 'ไม่มี' : drinkTypesStr}',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            // Server-provided remaining / consumed calories (if available)
            if (remainingCaloriesToday != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'โควตาที่เหลือวันนี้: ${remainingCaloriesToday!.toStringAsFixed(0)} kcal',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'ทานแล้ว: ${consumedCaloriesToday != null ? consumedCaloriesToday!.toStringAsFixed(0) : '-'} kcal',
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // If backend flagged the selected item as unsafe, show warning + swap/upgrade
            if (itemSafe != null && itemSafe == false) ...[
              Card(
                color: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'คำเตือน: ${safetyMessage ?? 'รายการนี้อาจไม่เหมาะสมสำหรับคุณ'}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Portion slider to let user reduce portion and re-check safety
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ปรับสัดส่วนการทาน:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                '${(_currentPortion * 100).round()}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Slider(
                                  value: _currentPortion,
                                  min: 0.5,
                                  max: 1.0,
                                  divisions: 5,
                                  label: '${(_currentPortion * 100).round()}%',
                                  onChanged: (v) {
                                    setState(() {
                                      _currentPortion = v;
                                    });
                                  },
                                  onChangeEnd: (v) async {
                                    setState(() {
                                      _currentPortion = v;
                                    });
                                    // re-query safety with new portion ratio
                                    try {
                                      final int menuId = matchedFood != null
                                          ? (matchedFood!['id'] is int
                                                ? matchedFood!['id'] as int
                                                : int.tryParse(
                                                        matchedFood!['id']
                                                                ?.toString() ??
                                                            '',
                                                      ) ??
                                                      0)
                                          : (selectedFoodMenuId ?? 0);
                                      if (menuId != 0) {
                                        await _fetchSafetyForMenu(menuId);
                                      }
                                    } catch (e) {
                                      if (kDebugMode) {
                                        print('portion change fetch error: $e');
                                      }
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (upgradeTips != null && upgradeTips!.isNotEmpty)
                        Text(
                          'คำแนะนำในการปรับเมนู: $upgradeTips',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      const SizedBox(height: 8),
                      if (swapSuggestion != null)
                        ListTile(
                          title: Text(swapSuggestion?['name'] ?? ''),
                          subtitle: Text(
                            '${(swapSuggestion?['calories'] ?? '-')} kcal — ประหยัด ${(swapSuggestion?['saving_calories'] ?? '-')} kcal',
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              // Apply smart swap locally
                              try {
                                final alt = swapSuggestion!;
                                setState(() {
                                  matchedFood = alt;
                                  foodController.text = alt['name'] ?? '';
                                  selectedFoodQty = 1;
                                  selectedFoodMenuId = alt['id'] is int
                                      ? alt['id'] as int
                                      : int.tryParse(
                                          alt['id']?.toString() ?? '',
                                        );
                                  _computeGiAndSatiety();
                                  _applyComboFilters();
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'สลับเมนูเป็นตัวเลือกที่แนะนำแล้ว',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (kDebugMode) print('apply swap error: $e');
                              }
                            },
                            child: const Text('สลับเมนู'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // GI and Satiety
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Satiety: ${_satietyScore != null ? _satietyScore!.toStringAsFixed(0) : '-'} / 100',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'GI Rating: ${_giRating != null ? _giRating!.toStringAsFixed(0) : '-'}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_giRating != null && _giRating! >= 70) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'GI สูง: พิจารณาจับคู่กับโปรตีนเพื่อลดการดูดซึม',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Behavioral nudge (Smart Swap & Upgrade)
            if (_showBehavioralNudge) ...[
              Card(
                color: Colors.yellow.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'คำแนะนำ: พบเมนูที่อาจไม่ปลอดภัย — ลองเมนูทางเลือกเหล่านี้',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (final alt in _nudgeAlternatives)
                        ListTile(
                          dense: true,
                          title: Text(alt['name'] ?? ''),
                          subtitle: Text('${(alt['calories'] ?? '-')} kcal'),
                          trailing: ElevatedButton(
                            onPressed: () {
                              // apply swap: set controllers & matched items
                              try {
                                if ((alt['category'] ?? '')
                                    .toString()
                                    .toLowerCase()
                                    .contains('drink')) {
                                  setState(() {
                                    matchedDrink = alt;
                                    drinkController.text = alt['name'] ?? '';
                                    selectedDrinkQty = 1;
                                    selectedDrinkMenuId = alt['id'] is int
                                        ? alt['id'] as int
                                        : int.tryParse(
                                            alt['id']?.toString() ?? '',
                                          );
                                  });
                                } else if ((alt['category'] ?? '')
                                    .toString()
                                    .toLowerCase()
                                    .contains('dessert')) {
                                  setState(() {
                                    matchedDessert = alt;
                                    dessertController.text = alt['name'] ?? '';
                                    selectedDessertQty = 1;
                                    selectedDessertId = alt['id'] is int
                                        ? alt['id'] as int
                                        : int.tryParse(
                                            alt['id']?.toString() ?? '',
                                          );
                                  });
                                } else {
                                  setState(() {
                                    matchedFood = alt;
                                    foodController.text = alt['name'] ?? '';
                                    selectedFoodQty = 1;
                                    selectedFoodMenuId = alt['id'] is int
                                        ? alt['id'] as int
                                        : int.tryParse(
                                            alt['id']?.toString() ?? '',
                                          );
                                  });
                                }
                                _computeGiAndSatiety();
                                _applyComboFilters();
                              } catch (_) {}
                            },
                            child: const Text('เลือก'),
                          ),
                        ),
                      const SizedBox(height: 6),
                      const Text(
                        'Upgrade Tips: ลดน้ำจิ้ม, เพิ่มผัก หรือเลือกน้ำเปล่าแทนเครื่องดื่มหวาน',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onNextPressed() async {
    if (_fieldsLocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🛑 ขณะนี้ยังไม่ถึงช่วงเปิดกรอกมื้อปัจจุบัน กรุณารอช่วงเวลาถัดไป',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!_canAttemptNext) return;
    await _saveSelection();
  }

  String _nameForId(List<Map<String, dynamic>> list, int? id) {
    if (id == null) return '';
    try {
      final found = list.firstWhere(
        (e) =>
            (e['id'] is int
                ? e['id'] as int
                : int.tryParse(e['id'].toString())) ==
            id,
        orElse: () => {},
      );
      return (found['name'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  Widget _buildInputBlock(
    String title,
    String hint,
    TextEditingController ctrl,
    String cat,
    String? err, {
    ValueChanged<String>? onChanged,
  }) {
    final bool editable = !_fieldsLocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          enabled: editable,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            errorText: err,
            filled: true,
            fillColor: AppColors.card,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search, color: Colors.green),
              onPressed: editable ? () => _analyzeMenu(ctrl.text, cat) : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSafeImage({
    required String? imageUrl,
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: Icon(Icons.image_not_supported)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }

  Widget _buildResultCard(
    Map<String, dynamic> item,
    String cat,
    String? img,
    int? qty,
    String? adv,
    String currentUnit,
    List<String> unitList,
    ValueChanged<int?> onQtyChanged,
    ValueChanged<String> onUnitChanged,
  ) {
    final displayQty = qty ?? 1;
    final totalCalories = _calculateMatchedItemCalories(
      item,
      currentUnit,
      displayQty,
    );
    final imageHeight = MediaQuery.of(context).size.height * 0.32;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (img != null && img.trim().isNotEmpty)
              Container(
                height: imageHeight,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.network(
                  img,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: imageHeight,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.card,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              item['name'],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (adv != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: adv.contains('⚠️')
                    ? Colors.orange.shade50
                    : Colors.green.shade50,
                child: Text(
                  adv,
                  style: TextStyle(
                    color: adv.contains('⚠️')
                        ? Colors.red.shade900
                        : Colors.green.shade900,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text("ปริมาณที่ต้องการรับประทาน: "),
                IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.black54,
                  ),
                  onPressed: () {
                    final newQty = (displayQty - 1) < 1 ? 1 : (displayQty - 1);
                    onQtyChanged(newQty);
                  },
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '$displayQty',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.black54,
                  ),
                  onPressed: () {
                    final newQty = displayQty + 1;
                    onQtyChanged(newQty);
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: currentUnit.isNotEmpty ? currentUnit : null,
                    hint: const Text('หน่วย'),
                    items: unitList
                        .map(
                          (u) => DropdownMenuItem<String>(
                            value: u,
                            child: Text(u),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onUnitChanged(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.green.shade100,
              child: Text(
                "🔥 ผลคำนวณพลังงานสุทธิ: ${totalCalories.toStringAsFixed(0)} Kcal",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _fetchImageUrl(String name) async {
    try {
      final resp = await api.get(
        '/api/food-image?name=${Uri.encodeComponent(name)}&debug=1',
      );
      if (resp.statusCode == 200) {
        final j = json.decode(resp.body);
        if (j is Map) {
          final url = (j['image_url'] ?? '').toString();
          if (url.trim().isNotEmpty) return url.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  // (previously used for Tab UI) tab state removed — UI now shows separate boxes

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    if (!_authLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Enforce strict selection rules: main food must be a confirmed menu id
    final bool canProceed =
        (matchedFood != null && selectedFoodQty != null) ||
        (matchedDessert != null && selectedDessertQty != null) ||
        (matchedDrink != null && selectedDrinkQty != null);

    // Next button uses class-level `nextEnabled` getter (requires both food+drink filled and safety-checked)

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.leaf),
        title: const Text(
          "เลือกเมนูอาหารและเครื่องดื่ม",
          style: TextStyle(
            color: AppColors.leaf,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back, color: primaryGreen),
        ),
        // keep existing action widgets (user display)
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Builder(
                builder: (ctx) {
                  final auth = _auth;
                  final displayName = auth.isGuest
                      ? 'Guest'
                      : (auth.user?['username'] ??
                            auth.user?['name'] ??
                            (auth.user?['email'] != null
                                ? auth.user!['email']
                                      .toString()
                                      .split('@')
                                      .first
                                : '') ??
                            '');
                  return Text(
                    displayName,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              // Static header for menu section (moved above health summary)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'เลือกเมนูอาหารและเครื่องดื่ม',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.leaf,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
              // Top: Health & Goal Summary Card
              _healthSummaryCard(),
              // New user/profile selection card inserted between summary and search
              _userProfileSelectionCard(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.leaf,
                  side: BorderSide(color: AppColors.leaf),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
                icon: const Icon(Icons.shuffle, size: 18),
                label: const Text(
                  'สุ่มทุกหมวดหมู่ (อาหาร, เครื่องดื่ม, ของหวาน)',
                  style: TextStyle(fontSize: 14),
                ),
                onPressed: (_mealWindowLocked || _fieldsLocked)
                    ? null
                    : _randomizeAllCategories,
              ),
              const SizedBox(height: 12),

              // Dessert and Drink dropdowns removed per UI requirement.
              // (State and loader functions remain intact.)

              // Three independent input blocks (idea #2) — wrapped as cards
              Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.restaurant_menu,
                            color: AppColors.leaf,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'อาหารคาว',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            icon: _isFetchingRandomFood
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.shuffle, size: 18),
                            label: const Text('สุ่ม'),
                            onPressed: (_mealWindowLocked || _fieldsLocked || _isFetchingRandomFood)
                                ? null
                                : () => _randomizeCategory('food'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildInputBlock(
                        "ระบุรายการเมนูอาหาร",
                        "ระบุรายการเมนูอาหาร",
                        foodController,
                        "food",
                        foodError,
                        onChanged: (v) {
                          setState(() {
                            matchedFood = null;
                            foodError = null;
                            selectedFoodMenuId = null;
                            selectedFoodMenuCalories = 0;
                            calculatedFoodCalories = 0.0;
                            foodImageUrl = null;
                            // reset safety when user edits
                            isSafetyChecked = false;
                            isFoodSafe = false;
                            _foodSafetyOk = false;
                          });
                          _realtimeDebounceFood?.cancel();
                          _realtimeDebounceFood = Timer(
                            const Duration(milliseconds: 450),
                            () {
                              if (v.trim().isEmpty) {
                                setState(() {
                                  matchedFood = null;
                                  foodError = null;
                                });
                                return;
                              }
                              _validateAndProcessInput(v, 'food');
                            },
                          );
                        },
                      ),
                      if (matchedFood != null)
                        _buildResultCard(
                          matchedFood!,
                          "food",
                          foodImageUrl,
                          selectedFoodQty,
                          foodAdvice,
                          selectedFoodUnit,
                          foodUnits,
                          (v) => setState(() {
                            selectedFoodQty = v;
                            calculatedFoodCalories = _calculateMatchedItemCalories(
                              matchedFood!,
                              selectedFoodUnit,
                              selectedFoodQty ?? 1,
                            );
                            foodError = _validateNutritionAndGoal(
                              text: foodController.text,
                              category: 'อาหารคาว',
                              quantity: selectedFoodQty ?? 1,
                              unit: selectedFoodUnit,
                              computedCalories: calculatedFoodCalories ??
                                  _calculateMatchedItemCalories(
                                    matchedFood!,
                                    selectedFoodUnit,
                                    selectedFoodQty ?? 1,
                                  ),
                            );
                            _computeGiAndSatiety();
                            _applyComboFilters();
                          }),
                          (u) => setState(() {
                            selectedFoodUnit = u;
                            calculatedFoodCalories = _calculateMatchedItemCalories(
                              matchedFood!,
                              selectedFoodUnit,
                              selectedFoodQty ?? 1,
                            );
                            foodError = _validateNutritionAndGoal(
                              text: foodController.text,
                              category: 'อาหารคาว',
                              quantity: selectedFoodQty ?? 1,
                              unit: selectedFoodUnit,
                              computedCalories: calculatedFoodCalories ??
                                  _calculateMatchedItemCalories(
                                    matchedFood!,
                                    selectedFoodUnit,
                                    selectedFoodQty ?? 1,
                                  ),
                            );
                            _computeGiAndSatiety();
                            _applyComboFilters();
                          }),
                        ),
                      if (foodMenuError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            foodMenuError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.icecream, color: Colors.deepOrange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ของหวาน',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            icon: _isFetchingRandomDessert
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.shuffle, size: 18),
                            label: const Text('สุ่ม'),
                            onPressed: (_mealWindowLocked || _fieldsLocked || _isFetchingRandomDessert)
                                ? null
                                : () => _randomizeCategory('dessert'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildInputBlock(
                        "ระบุรายการเมนูของหวาน",
                        "ระบุรายการเมนูของหวาน",
                        dessertController,
                        "dessert",
                        dessertError,
                        onChanged: (v) {
                          setState(() {
                            matchedDessert = null;
                            dessertError = null;
                            selectedDessertId = null;
                            selectedDessertMenuCalories = 0;
                            calculatedDessertCalories = 0.0;
                            dessertImageUrl = null;
                            // reset safety when user edits
                            isSafetyChecked = false;
                            isFoodSafe = false;
                          });
                          _realtimeDebounceDessert?.cancel();
                          _realtimeDebounceDessert = Timer(
                            const Duration(milliseconds: 450),
                            () {
                              if (v.trim().isEmpty) {
                                setState(() {
                                  matchedDessert = null;
                                  dessertError = null;
                                });
                                return;
                              }
                              _validateAndProcessInput(v, 'dessert');
                            },
                          );
                        },
                      ),
                      if (matchedDessert != null)
                        _buildResultCard(
                          matchedDessert!,
                          "dessert",
                          dessertImageUrl,
                          selectedDessertQty,
                          dessertAdvice,
                          selectedDessertUnit,
                          dessertUnits,
                          (v) => setState(() {
                            selectedDessertQty = v;
                            calculatedDessertCalories = _calculateMatchedItemCalories(
                              matchedDessert!,
                              selectedDessertUnit,
                              selectedDessertQty ?? 1,
                            );
                            dessertError = _validateNutritionAndGoal(
                              text: dessertController.text,
                              category: 'ของหวาน',
                              quantity: selectedDessertQty ?? 1,
                              unit: selectedDessertUnit,
                              computedCalories: calculatedDessertCalories ??
                                  _calculateMatchedItemCalories(
                                    matchedDessert!,
                                    selectedDessertUnit,
                                    selectedDessertQty ?? 1,
                                  ),
                            );
                            _computeGiAndSatiety();
                            _applyComboFilters();
                          }),
                          (u) => setState(() {
                            selectedDessertUnit = u;
                            calculatedDessertCalories = _calculateMatchedItemCalories(
                              matchedDessert!,
                              selectedDessertUnit,
                              selectedDessertQty ?? 1,
                            );
                            dessertError = _validateNutritionAndGoal(
                              text: dessertController.text,
                              category: 'ของหวาน',
                              quantity: selectedDessertQty ?? 1,
                              unit: selectedDessertUnit,
                              computedCalories: calculatedDessertCalories ??
                                  _calculateMatchedItemCalories(
                                    matchedDessert!,
                                    selectedDessertUnit,
                                    selectedDessertQty ?? 1,
                                  ),
                            );
                            _computeGiAndSatiety();
                            _applyComboFilters();
                          }),
                        ),
                    ],
                  ),
                ),
              ),

              Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_cafe, color: Colors.indigo),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'เครื่องดื่ม',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            icon: _isFetchingRandomDrink
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.shuffle, size: 18),
                            label: const Text('สุ่ม'),
                            onPressed: (_mealWindowLocked || _fieldsLocked || _isFetchingRandomDrink)
                                ? null
                                : () => _randomizeCategory('drink'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildInputBlock(
                        "ระบุรายการเมนูเครื่องดื่ม",
                        "ระบุรายการเมนูเครื่องดื่ม",
                        drinkController,
                        "drink",
                        drinkError,
                        onChanged: (v) {
                          setState(() {
                            matchedDrink = null;
                            drinkError = null;
                            selectedDrinkMenuId = null;
                            selectedDrinkMenuCalories = 0;
                            calculatedDrinkCalories = 0.0;
                            drinkImageUrl = null;
                            // reset safety when user edits
                            isSafetyChecked = false;
                            isFoodSafe = false;
                            _drinkSafetyOk = false;
                          });
                          _realtimeDebounceDrink?.cancel();
                          _realtimeDebounceDrink = Timer(
                            const Duration(milliseconds: 450),
                            () {
                              if (v.trim().isEmpty) {
                                setState(() {
                                  matchedDrink = null;
                                  drinkError = null;
                                });
                                return;
                              }
                              _validateAndProcessInput(v, 'drink');
                            },
                          );
                        },
                      ),
                      if (matchedDrink != null)
                        _buildConditionalNutrientField(
                          imageUrl: drinkImageUrl,
                          quantity: drinkQuantity,
                          selectedUnit: selectedDrinkUnit,
                          unitList: drinkUnits,
                          calculatedCalories: calculatedDrinkCalories,
                          category: 'เครื่องดื่ม',
                          onQuantityChanged: (newQty) {
                            setState(() {
                              drinkQuantity = newQty;
                              double currentCal =
                                  _getBaseCaloriesByUnit(selectedDrinkUnit) *
                                  drinkQuantity;
                              calculatedDrinkCalories = currentCal;
                              drinkError = _validateNutritionAndGoal(
                                text: drinkController.text,
                                category: 'เครื่องดื่ม',
                                quantity: drinkQuantity,
                                unit: selectedDrinkUnit,
                                computedCalories: currentCal,
                              );
                              _computeGiAndSatiety();
                              _applyComboFilters();
                            });
                          },
                          onUnitChanged: (newUnit) {
                            setState(() {
                              selectedDrinkUnit = newUnit;
                              double currentCal =
                                  _getBaseCaloriesByUnit(selectedDrinkUnit) *
                                  drinkQuantity;
                              calculatedDrinkCalories = currentCal;
                              drinkError = _validateNutritionAndGoal(
                                text: drinkController.text,
                                category: 'เครื่องดื่ม',
                                quantity: drinkQuantity,
                                unit: selectedDrinkUnit,
                                computedCalories: currentCal,
                              );
                              _computeGiAndSatiety();
                              _applyComboFilters();
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),

              // Safety status alert (red = blocked, green = safe)
              // Calorie warning / health goal suggestion
              if (_overQuota) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade700),
                  ),
                  child: const Text(
                    '⚠️ คุณเลือกแคลอรีเกินสำหรับมื้ออาหารนี้แล้ว ควรปรับการกินให้พอดีนะ',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              if (_healthGoalWarning != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade700),
                  ),
                  child: Text(
                    _healthGoalWarning!,
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              Builder(
                builder: (ctx) {
                  String? safetyMsg;
                  bool safe = true;
                  if (foodError != null &&
                      (foodError!.contains('ไม่ผ่าน') ||
                          foodError!.contains('🚨') ||
                          foodError!.contains('กินไม่ได้'))) {
                    safetyMsg = foodError;
                    safe = false;
                  } else if (dessertError != null &&
                      (dessertError!.contains('ไม่ผ่าน') ||
                          dessertError!.contains('🚨') ||
                          dessertError!.contains('กินไม่ได้'))) {
                    safetyMsg = dessertError;
                    safe = false;
                  } else if (drinkError != null &&
                      (drinkError!.contains('ไม่ผ่าน') ||
                          drinkError!.contains('🚨') ||
                          drinkError!.contains('กินไม่ได้'))) {
                    safetyMsg = drinkError;
                    safe = false;
                  } else if (canProceed) {
                    // show positive confirmation using advice text when available
                    safetyMsg = matchedFood != null
                        ? (foodAdvice ??
                              'สามารถรับประทานได้ไม่มีส่วนผสมที่อันตรายต่อชีวิตหรือไม่แพ้อาหารหรือโรคประจำตัวใดๆ')
                        : (matchedDessert != null
                              ? (dessertAdvice ?? 'สามารถรับประทานได้')
                              : (matchedDrink != null
                                    ? (drinkAdvice ?? 'สามารถรับประทานได้')
                                    : null));
                    safe = true;
                  }
                  if (safetyMsg == null) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: safe ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: safe
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                    child: Text(
                      safetyMsg,
                      style: TextStyle(
                        color: safe
                            ? Colors.green.shade900
                            : Colors.red.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 56,
                child: Builder(
                  builder: (context) {
                    final canPress =
                        !_mealWindowLocked &&
                        !_fieldsLocked &&
                        _canAttemptNext;
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        // ต้องตั้ง disabledBackgroundColor เองตรงๆ — ไม่งั้น
                        // ElevatedButton.styleFrom ใช้สีเทาจางเริ่มต้นของ
                        // Material 3 ทับ AppColors.inkSoft ที่ตั้งใจไว้เสมอ
                        // ตอนปุ่ม disabled ทำให้ตัวอักษรขาว (hardcode ด้านล่าง)
                        // จางจนอ่านไม่ออกบนพื้นเทาอ่อนนั้น (บั๊กที่เจอจริง)
                        disabledBackgroundColor: AppColors.inkSoft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: canPress ? () => _onNextPressed() : null,
                      child: Text(
                        'หน้าถัดไป (เลือกระบุมื้ออาหาร)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
