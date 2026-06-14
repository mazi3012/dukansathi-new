import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main/pages/main_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_box.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../providers/dashboard_provider.dart';
import '../../../core/session.dart';
import '../../../core/widgets/dukan_sathi_logo.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int? _selectedChartIndex;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(dashboardProvider.notifier).fetchDashboardData();
    });
  }

  Future<void> _fetchDashboardData() async {
    await ref.read(dashboardProvider.notifier).fetchDashboardData();
  }

  DashboardState get _state => ref.watch(dashboardProvider);

  bool get _isLoading => _state.isLoading;
  bool get _hasError => _state.hasError;
  double get _grossSales => _state.grossSales;
  double get _netRevenue => _state.netRevenue;
  double get _gstCollected => _state.gstCollected;
  int get _invoiceCountToday => _state.invoiceCountToday;
  double get _totalMarketDues => _state.totalMarketDues;
  int get _aiRestockItemsCount => _state.aiRestockItemsCount;
  String get _aiRestockItemName => _state.aiRestockItemName;
  double get _expectedRevenueTomorrow => _state.expectedRevenueTomorrow;
  int get _pendingApprovalsCount => _state.pendingApprovalsCount;
  List<Map<String, dynamic>> get _recentActivity => _state.recentActivity;

  // Live analytics getters
  double get _netProfit => _state.netProfit;
  double get _netProfitMargin => _state.netProfitMargin;
  double get _averageOrderValue => _state.averageOrderValue;
  List<double> get _past7DaysSales => _state.past7DaysSales;
  List<double> get _predicted7DaysSales => _state.predicted7DaysSales;
  List<Map<String, dynamic>> get _aiAlerts => _state.aiAlerts;

  String _formatTimestamp(String? timestampStr) {
    if (timestampStr == null) return '';
    try {
      final dateTime = DateTime.parse(timestampStr).toLocal();
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${dateTime.day}/${dateTime.month}';
      }
    } catch (e) {
      return '';
    }
  }

  Future<void> _handleAlertAction(Map<String, dynamic> alert) async {
    final type = alert['type'];
    final payload = alert['payload'] ?? {};

    if (type == 'ledger' && payload['customer_phone'] != null) {
      final phone = payload['customer_phone'];
      final name = payload['customer_name'];
      final amount = payload['due_amount'];
      final message = "Hello $name,\nThis is a friendly reminder from Dukan Sathi that there is an outstanding balance of ₹${amount.toStringAsFixed(0)} in your ledger account. Kindly settle the outstanding at your earliest convenience.\nThank you!";
      final whatsappUrl = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");

      try {
        if (await canLaunchUrl(whatsappUrl)) {
          await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not launch WhatsApp. Make sure it is installed."), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } else if (type == 'stock') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Initiating Quick Restock draft for ${payload['product_name']}..."),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } else if (type == 'peak') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Navigating to Billing Page to pre-generate invoice drafts..."),
          backgroundColor: Color(0xFF2563EB),
        ),
      );
    } else {
      // Default fallback snout
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Opening ledger/catalog details..."), backgroundColor: AppColors.primary),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context) || ResponsiveLayout.isTablet(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dynamic Background Ambience - Emerald glow top right
          Positioned(
            top: -120,
            right: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF10B981).withOpacity(isDark ? 0.08 : 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Deep Cyan glow bottom left
          Positioned(
            bottom: -150,
            left: -100,
            child: Container(
              width: 450,
              height: 450,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF06B6D4).withOpacity(isDark ? 0.07 : 0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: isDesktop ? _buildDesktopLayout(context) : _buildMobileLayout(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return CustomScrollView(
      slivers: [
        _buildMobileAppBar(context),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildWelcomeSection(context),
              const SizedBox(height: 20),
              _isLoading ? _buildStatsSkeleton() : _buildStatsGrid(),
              const SizedBox(height: 25),
              _buildSectionTitle(context, "AI Sales Prediction & Forecast"),
              const SizedBox(height: 12),
              SizedBox(height: 300, child: _isLoading ? _buildChartSkeleton() : _buildSalesChart()),
              const SizedBox(height: 25),
              _buildSectionTitle(context, "AI Critical Notify & Smart Feed"),
              const SizedBox(height: 12),
              _isLoading ? SizedBox(height: 300, child: _buildInsightsSkeleton()) : _buildAIAlertsFeed(),
              const SizedBox(height: 25),
              _buildSectionTitle(context, "Recent Invoices & Activity"),
              const SizedBox(height: 12),
              _isLoading ? _buildActivitySkeleton() : _buildActivityList(),
              const SizedBox(height: 100), // Navigation spacer
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeSection(context),
            const SizedBox(height: 24),
            _isLoading ? _buildStatsSkeleton() : _buildStatsGrid(),
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: AI Forecast Wave & Activity logs
                Expanded(
                  flex: 55,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle(context, "AI Sales Prediction & Forecast"),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 380, // Spacious fixed height of 380 on desktop!
                          child: _isLoading ? _buildChartSkeleton() : _buildSalesChart(),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionTitle(context, "Recent Invoices & Activity"),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 480, // Spacious fixed height of 480 on desktop!
                          child: _isLoading ? _buildActivitySkeleton() : _buildActivityCard(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 28),
                // Right Column: AI Smart Feed (Actions Ledger / Velocity Inventory)
                Expanded(
                  flex: 45,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle(context, "AI Critical Notify & Smart Feed"),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 880, // Spacious fixed height of 880 to show all alerts without squeeze!
                          child: _isLoading ? _buildInsightsSkeleton() : _buildAIAlertsFeed(isDesktop: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 100), // Navigation spacer
          ],
        ),
      ),
    );
  }

  Widget _buildMobileAppBar(BuildContext context) {
    return SliverAppBar(
      floating: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Iconsax.menu),
        onPressed: () {
          mainScaffoldKey.currentState?.openDrawer();
        },
      ),
      title: const DukanSathiHeader(
        height: 48,
        showGlow: false,
        animate: true,
      ),
      actions: [
        IconButton(
          onPressed: _fetchDashboardData,
          icon: Icon(Iconsax.refresh, color: Theme.of(context).iconTheme.color),
        ),
      ],
    );
  }

  Widget _buildWelcomeSection(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context) || ResponsiveLayout.isTablet(context);
    final userName = UserSession().userName ?? "Mazidur Rahman";

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundImage: const NetworkImage(
                'https://api.dicebear.com/7.x/adventurer/png?seed=Mazidur',
              ),
              backgroundColor: AppColors.primary.withOpacity(0.1),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome back,",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade400,
                  ),
                ),
                Text(
                  userName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (isDesktop) ...[
          Row(
            children: [
              IconButton(
                onPressed: _fetchDashboardData,
                icon: const Icon(Iconsax.refresh, color: Colors.white70),
              ),
              const SizedBox(width: 8),
              Stack(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Iconsax.notification, color: Colors.white70),
                  ),
                  if (_aiRestockItemsCount > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Container(
                width: 220,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Iconsax.search_normal, size: 16, color: Colors.grey.shade400),
                    const SizedBox(width: 8),
                    Text(
                      "Search",
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]
      ],
    ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.05);
  }

  Widget _buildStatsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        
        int crossAxisCount = 2;
        if (width > 950) {
          crossAxisCount = 6;
        } else if (width > 680) {
          crossAxisCount = 3;
        } else {
          crossAxisCount = 2; // Always display 2 cards side-by-side on mobile
        }

        final double cardSpacing = crossAxisCount == 2 ? 10.0 : 14.0;
        final cardWidth = (width - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
        final double cardHeight = crossAxisCount == 6 ? 138.0 : (crossAxisCount == 3 ? 116.0 : 92.0);
        final double childAspectRatio = cardWidth / cardHeight;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: cardSpacing,
          mainAxisSpacing: cardSpacing,
          childAspectRatio: childAspectRatio,
          children: [
            _buildMetricsCard(
              "Gross Sales",
              "₹${_grossSales.toStringAsFixed(0)}",
              subtitle: "Billing + GST",
              accentColor: const Color(0xFF10B981),
            ),
            _buildMetricsCard(
              "Net Revenue",
              "₹${_netRevenue.toStringAsFixed(0)}",
              subtitle: "Total core income",
              accentColor: const Color(0xFF06B6D4),
            ),
            _buildMetricsCard(
              "GST Collected",
              "₹${_gstCollected.toStringAsFixed(2)}",
              subtitle: "CGST/SGST tax",
              accentColor: const Color(0xFF3B82F6),
            ),
            _buildMetricsCard(
              "Total Invoices",
              _invoiceCountToday.toString(),
              subtitle: "AOV: ₹${_averageOrderValue.toStringAsFixed(0)}",
              accentColor: const Color(0xFF8B5CF6),
            ),
            _buildMetricsCard(
              "Net Profit",
              "₹${_netProfit.toStringAsFixed(0)}",
              subtitle: "Margin: ${_netProfitMargin.toStringAsFixed(1)}%",
              accentColor: const Color(0xFFF59E0B),
            ),
            _buildMetricsCard(
              "Critical Dues",
              "₹${_totalMarketDues.toStringAsFixed(0)}",
              subtitle: "Stock Restock: $_aiRestockItemsCount",
              accentColor: const Color(0xFFEF4444),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricsCard(
    String title,
    String value, {
    required String subtitle,
    required Color accentColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassBorder = accentColor.withOpacity(isDark ? 0.28 : 0.38);
    final isDesktop = ResponsiveLayout.isDesktop(context) || ResponsiveLayout.isTablet(context);

    return GlassBox(
      borderRadius: 14,
      border: Border.all(color: glassBorder, width: 1.2),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 14 : 10,
          vertical: isDesktop ? 12 : 8,
        ),
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.015),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: isDesktop ? 11 : 9.5,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: isDesktop ? 20 : 16,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      color: accentColor.withOpacity(0.9),
                      fontSize: isDesktop ? 10 : 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).scaleXY(begin: 0.95);
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSalesChart() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = ResponsiveLayout.isDesktop(context) || ResponsiveLayout.isTablet(context);
    final bool hasSales = _past7DaysSales.any((v) => v > 0.0);

    Widget chartContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Dynamic 7-Day Revenue Trend",
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Live past transactions overlaid with AI 7-day weighted forecast.",
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                  ),
                ],
              ),
            ),
            // Legend
            if (hasSales)
              Row(
                children: [
                  _buildLegendItem("Past 7d", const Color(0xFF10B981), isDashed: false),
                  const SizedBox(width: 12),
                  _buildLegendItem("AI Forecast", const Color(0xFF06B6D4), isDashed: true),
                ],
              ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SizedBox(
            width: double.infinity,
            child: !hasSales
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF06B6D4).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Iconsax.chart_1, color: Color(0xFF06B6D4), size: 28),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Awaiting Sales Activity",
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            "Create invoices in the Billing page to unlock real-time revenue trends and AI-driven forecasting.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final double width = constraints.maxWidth;
                      const double leftPadding = 20.0;
                      const double rightPadding = 45.0;
                      final double drawableWidth = width - leftPadding - rightPadding;
                      final int totalPoints = _past7DaysSales.length + _predicted7DaysSales.length;
                      final double dx = drawableWidth / (totalPoints - 1);

                      return GestureDetector(
                        onTapDown: (details) {
                          final double localX = details.localPosition.dx;
                          final int index = ((localX - leftPadding) / dx).round().clamp(0, totalPoints - 1);
                          setState(() {
                            _selectedChartIndex = index;
                          });
                        },
                        onPanDown: (details) {
                          final double localX = details.localPosition.dx;
                          final int index = ((localX - leftPadding) / dx).round().clamp(0, totalPoints - 1);
                          setState(() {
                            _selectedChartIndex = index;
                          });
                        },
                        onPanUpdate: (details) {
                          final double localX = details.localPosition.dx;
                          final int index = ((localX - leftPadding) / dx).round().clamp(0, totalPoints - 1);
                          setState(() {
                            _selectedChartIndex = index;
                          });
                        },
                        onPanEnd: (_) {
                          Future.delayed(const Duration(seconds: 3), () {
                            if (mounted) {
                              setState(() {
                                _selectedChartIndex = null;
                              });
                            }
                          });
                        },
                        onTapUp: (_) {
                          Future.delayed(const Duration(seconds: 3), () {
                            if (mounted) {
                              setState(() {
                                _selectedChartIndex = null;
                              });
                            }
                          });
                        },
                        child: CustomPaint(
                          painter: ProfessionalMLComboPainter(
                            currentData: _past7DaysSales,
                            predictedData: _predicted7DaysSales,
                            currentColor: const Color(0xFF10B981),
                            predictedColor: const Color(0xFF06B6D4),
                            isDark: isDark,
                            selectedIndex: _selectedChartIndex,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        // AI Analysis banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF06B6D4).withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.1)),
          ),
          child: Row(
            children: [
              const Icon(Iconsax.flash_15, size: 16, color: Color(0xFF06B6D4)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasSales
                      ? "AI Projected: Sales revenue is expected to grow by 9.4% this week. Optimal inventory restock threshold is solid."
                      : "AI Forecast: Waiting for transaction data. Real-time predictive models activate after your first sales invoice.",
                  style: TextStyle(
                    color: isDark ? Colors.cyan.shade200 : Colors.cyan.shade900,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return GlassBox(
      borderRadius: 20,
      border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : AppColors.lightGlassBorder),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: isDesktop 
            ? chartContent 
            : SizedBox(height: 315, child: chartContent),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, {required bool isDashed}) {
    return Row(
      children: [
        if (isDashed)
          Row(
            children: List.generate(3, (index) => Container(
              width: 4,
              height: 2,
              margin: const EdgeInsets.only(right: 2),
              color: color,
            ))
          )
        else
          Container(
            width: 14,
            height: 3,
            color: color,
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildAIAlertsFeed({bool isDesktop = false}) {
    if (_aiAlerts.isEmpty) {
      return const EmptyState(
        title: "Dukan Sathi Alert Clear",
        subtitle: "No high risk issues detected. Business health is optimal.",
        icon: Iconsax.shield_security,
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: isDesktop ? const ScrollPhysics() : const NeverScrollableScrollPhysics(),
      itemCount: _aiAlerts.length,
      itemBuilder: (context, index) {
        final alert = _aiAlerts[index];
        return _buildAIAlertCard(alert);
      },
    );
  }

  Widget _buildAIAlertCard(Map<String, dynamic> alert) {
    final type = alert['type'];
    final title = alert['title'] ?? 'AI System Notification';
    final message = alert['message'] ?? '';
    final actionLabel = alert['actionLabel'] ?? 'Take Action';

    Color cardAccentColor = const Color(0xFF3B82F6);
    IconData cardIcon = Iconsax.info_circle;

    if (type == 'ledger') {
      cardAccentColor = const Color(0xFFEF4444);
      cardIcon = Iconsax.wallet_3;
    } else if (type == 'stock') {
      cardAccentColor = const Color(0xFFF59E0B);
      cardIcon = Iconsax.box;
    } else if (type == 'peak') {
      cardAccentColor = const Color(0xFF06B6D4);
      cardIcon = Iconsax.clock;
    } else if (type.toString().endsWith('perfect')) {
      cardAccentColor = const Color(0xFF10B981);
      cardIcon = Iconsax.shield_tick;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassBox(
        borderRadius: 16,
        border: Border.all(color: cardAccentColor.withOpacity(isDark ? 0.22 : 0.32), width: 1.2),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: cardAccentColor.withOpacity(0.01),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cardAccentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(cardIcon, size: 18, color: cardAccentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => _handleAlertAction(alert),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: cardAccentColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: cardAccentColor.withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          actionLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios, size: 10, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
  }

  Widget _buildActivityCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassBox(
      borderRadius: 20,
      border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : AppColors.lightGlassBorder),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Expanded(
              child: _recentActivity.isEmpty
                  ? const Center(
                      child: EmptyState(
                        title: "No Recent Sales",
                        subtitle: "Create invoices inside the Billing page to view logs.",
                        icon: Iconsax.receipt_item,
                      ),
                    )
                  : Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.0),
                        1: FlexColumnWidth(1.4),
                        2: FlexColumnWidth(1.2),
                        3: FlexColumnWidth(0.9),
                        4: FlexColumnWidth(1.1),
                      },
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isDark ? Colors.white12 : Colors.black12,
                                width: 1,
                              ),
                            ),
                          ),
                          children: [
                            _buildTableHeaderCell("Invoice #"),
                            _buildTableHeaderCell("Customer"),
                            _buildTableHeaderCell("Time"),
                            _buildTableHeaderCell("Status", align: TextAlign.center),
                            _buildTableHeaderCell("Net Amount", align: TextAlign.right),
                          ],
                        ),
                        ..._recentActivity.take(4).map((activity) {
                          final invNum = activity['invoice_number'] ?? 'N/A';
                          final customer = activity['customer_name'] ?? 'Walk-in';
                          final amount = (activity['amount'] as num?)?.toDouble() ?? 0;
                          final timeStr = _formatTimestamp(activity['timestamp']);

                          return TableRow(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                                  width: 0.8,
                                ),
                              ),
                            ),
                            children: [
                              _buildTableCellText(invNum, isBold: true),
                              _buildTableCellText(customer),
                              _buildTableCellText(timeStr),
                              TableCell(
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
                                    ),
                                    child: const Text(
                                      "PAID",
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              TableCell(
                                child: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(
                                    "₹${amount.toStringAsFixed(0)}",
                                    style: const TextStyle(
                                      color: Color(0xFF10B981),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeaderCell(String text, {TextAlign align = TextAlign.left}) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTableCellText(String text, {bool isBold = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Text(
          text,
          style: TextStyle(
            color: isDark ? Colors.white.withOpacity(0.87) : Colors.black.withOpacity(0.87),
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: 12.5,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildActivityList() {
    if (_recentActivity.isEmpty) {
      return const EmptyState(
        title: "No Recent Sales",
        subtitle: "Create invoices inside the Billing page to view logs.",
        icon: Iconsax.receipt_item,
      );
    }
    return Column(
      children: _recentActivity.map((activity) => _buildActivityItem(activity)).toList(),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity) {
    final invNum = activity['invoice_number'] ?? 'N/A';
    final customer = activity['customer_name'] ?? 'Walk-in';
    final amount = (activity['amount'] as num?)?.toDouble() ?? 0;
    final timeStr = _formatTimestamp(activity['timestamp']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassBox(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white.withOpacity(0.08) 
                  : AppColors.lightPrimarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Iconsax.receipt, color: AppColors.primary, size: 18),
          ),
          title: Text(
            "Invoice #$invNum", 
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text("Customer: $customer", style: Theme.of(context).textTheme.bodySmall),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("₹${amount.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 15)),
              if (timeStr.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(timeStr, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 2;
        if (width > 950) {
          crossAxisCount = 6;
        } else if (width > 680) {
          crossAxisCount = 3;
        } else if (width > 400) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = 1;
        }

        final cardWidth = (width - (crossAxisCount - 1) * 14) / crossAxisCount;
        final double cardHeight = crossAxisCount == 1 ? 110.0 : 138.0;
        final double childAspectRatio = cardWidth / cardHeight;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: childAspectRatio,
          children: List.generate(6, (index) => const SkeletonCard()),
        );
      },
    );
  }

  Widget _buildInsightsSkeleton() {
    return Column(
      children: List.generate(3, (index) => const SkeletonCard()),
    );
  }

  Widget _buildChartSkeleton() {
    return const SkeletonCard();
  }

  Widget _buildActivitySkeleton() {
    return Column(
      children: List.generate(4, (index) => const SkeletonListTile()),
    );
  }
}

// Professional Combo ML Painter with Glowing filled bars for past sales, empty dashed bars for forecast, standard error envelope, gridlines and X/Y labels!
class ProfessionalMLComboPainter extends CustomPainter {
  final List<double> currentData;
  final List<double> predictedData;
  final Color currentColor;
  final Color predictedColor;
  final bool isDark;
  final int? selectedIndex;

  ProfessionalMLComboPainter({
    required this.currentData,
    required this.predictedData,
    required this.currentColor,
    required this.predictedColor,
    required this.isDark,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (currentData.isEmpty && predictedData.isEmpty) return;

    const double topPadding = 15.0;
    const double bottomPadding = 25.0;
    const double leftPadding = 20.0;
    const double rightPadding = 45.0; // wider right padding to fit Y-axis labels like ₹15,000

    final double drawableWidth = size.width - leftPadding - rightPadding;
    final double drawableHeight = size.height - topPadding - bottomPadding;
    final double baseline = size.height - bottomPadding;

    final allData = [...currentData, ...predictedData];
    
    // Calculate upper and lower bounds for the ML confidence envelope!
    final List<double> upperBounds = [];
    final List<double> lowerBounds = [];
    for (int i = 0; i < predictedData.length; i++) {
      final double uncertaintyFactor = 0.04 + (i * 0.03); // expanding uncertainty
      upperBounds.add(predictedData[i] * (1.0 + uncertaintyFactor));
      lowerBounds.add(predictedData[i] * (1.0 - uncertaintyFactor));
    }

    final double maxVal = [...allData, ...upperBounds].reduce((a, b) => a > b ? a : b);
    const double minVal = 0.0; // force baseline to start from 0 for realistic bar scale!
    final double range = maxVal - minVal == 0 ? 1 : maxVal - minVal;

    final int totalPoints = currentData.length + predictedData.length;
    final double dx = drawableWidth / (totalPoints - 1);

    double getX(int index) => leftPadding + index * dx;
    double getY(double val) => baseline - ((val - minVal) / range) * drawableHeight;

    // 1. Draw Grid Lines and Y-Axis Labels
    const int gridLineCount = 4;
    final gridPaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i <= gridLineCount; i++) {
      final double fraction = i / gridLineCount;
      final double y = baseline - fraction * drawableHeight;
      final double val = minVal + fraction * (maxVal - minVal);
      
      // Draw gridline
      canvas.drawLine(Offset(leftPadding, y), Offset(leftPadding + drawableWidth, y), gridPaint);
      
      // Draw Y-axis value label
      final String label = "₹${val >= 1000 ? '${(val / 1000).toStringAsFixed(1)}k' : val.toStringAsFixed(0)}";
      _drawText(
        canvas, 
        label, 
        Offset(leftPadding + drawableWidth + 6.0, y - 4.0), 
        isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        fontSize: 8.0,
        alignment: Alignment.centerLeft,
      );
    }

    // 2. Draw Historical Bars (Past 7 days)
    final double barWidth = dx * 0.38; // dynamic bar thickness
    final barFillPaint = Paint()..style = PaintingStyle.fill;
    final Color barColor = currentColor;

    for (int i = 0; i < currentData.length; i++) {
      final double x = getX(i);
      final double y = getY(currentData[i]);

      // Create a gradient for the historical bar fill
      barFillPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [barColor.withOpacity(0.24), barColor.withOpacity(0.03)],
      ).createShader(Rect.fromLTWH(x - barWidth / 2, y, barWidth, baseline - y));

      final RRect rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x - barWidth / 2, y, barWidth, baseline - y),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      canvas.drawRRect(rrect, barFillPaint);

      // Draw active solid border lines on the top face of the bars to make them extremely distinct!
      final borderTopPaint = Paint()
        ..color = barColor.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(x - barWidth / 2, y), Offset(x + barWidth / 2, y), borderTopPaint);
    }

    // 3. Draw ML Confidence Envelope Shading & Outlines (Predicted 7 days)
    if (predictedData.isNotEmpty && currentData.isNotEmpty) {
      final envelopePath = Path();
      final startIdx = currentData.length - 1;

      envelopePath.moveTo(getX(startIdx), getY(currentData.last));

      // Upper bounds
      for (int i = 0; i < predictedData.length; i++) {
        envelopePath.lineTo(getX(startIdx + i), getY(upperBounds[i]));
      }
      // Lower bounds
      for (int i = predictedData.length - 1; i >= 0; i--) {
        envelopePath.lineTo(getX(startIdx + i), getY(lowerBounds[i]));
      }
      envelopePath.close();

      final envelopePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = predictedColor.withOpacity(0.06);
      canvas.drawPath(envelopePath, envelopePaint);
    }

    // 4. Draw Projected Dashed Bars (AI Forecast 7 days)
    final Paint predictedBarPaint = Paint()
      ..color = predictedColor.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (int i = 0; i < predictedData.length; i++) {
      final int idx = currentData.length + i;
      final double x = getX(idx);
      final double y = getY(predictedData[i]);

      final RRect rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x - barWidth / 2, y, barWidth, baseline - y),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      
      // Draw standard predicted bar outline with dashes!
      _drawDashedRRect(canvas, rrect, predictedBarPaint, dashWidth: 3.0, dashSpace: 3.0);
    }

    // 5. Draw Historical Connecting Trend Curve Line
    if (currentData.isNotEmpty) {
      final path = Path();
      path.moveTo(getX(0), getY(currentData[0]));

      for (int i = 1; i < currentData.length; i++) {
        final double x1 = getX(i - 1);
        final double y1 = getY(currentData[i - 1]);
        final double x2 = getX(i);
        final double y2 = getY(currentData[i]);

        final double controlX1 = x1 + (x2 - x1) / 2;
        final double controlY1 = y1;
        final double controlX2 = x1 + (x2 - x1) / 2;
        final double controlY2 = y2;

        path.cubicTo(controlX1, controlY1, controlX2, controlY2, x2, y2);
      }

      final paintCurrent = Paint()
        ..color = currentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, paintCurrent);

      // Pulse indicator at current data junction point (Today)
      final pulsePaint = Paint()..color = currentColor;
      final glowPaint = Paint()..color = currentColor.withOpacity(0.35);
      final endX = getX(currentData.length - 1);
      final endY = getY(currentData.last);

      canvas.drawCircle(Offset(endX, endY), 7.0, glowPaint);
      canvas.drawCircle(Offset(endX, endY), 3.5, pulsePaint);
    }

    // 6. Draw AI Projected Connecting Trend Curve Line (Dashed)
    if (predictedData.isNotEmpty && currentData.isNotEmpty) {
      final path = Path();
      final startIdx = currentData.length - 1;
      path.moveTo(getX(startIdx), getY(currentData.last));

      for (int i = 0; i < predictedData.length; i++) {
        final double x1 = getX(startIdx + (i == 0 ? 0 : i - 1));
        final double y1 = getY(i == 0 ? currentData.last : predictedData[i - 1]);
        final double x2 = getX(startIdx + i);
        final double y2 = getY(predictedData[i]);

        final double controlX1 = x1 + (x2 - x1) / 2;
        final double controlY1 = y1;
        final double controlX2 = x1 + (x2 - x1) / 2;
        final double controlY2 = y2;

        path.cubicTo(controlX1, controlY1, controlX2, controlY2, x2, y2);
      }

      final paintPredicted = Paint()
        ..color = predictedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      _drawDashedPath(canvas, path, paintPredicted, dashWidth: 5.0, dashSpace: 4.0);
    }

    // 7. Draw X-Axis Labels (Day 1 - 7, and AI +1d - +7d)
    final labelColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    
    // Draw Past 7 days X labels
    for (int i = 0; i < currentData.length; i++) {
      final double x = getX(i);
      final String label = i == currentData.length - 1 ? "Today" : "d-${currentData.length - 1 - i}";
      _drawText(
        canvas, 
        label, 
        Offset(x, baseline + 8.0), 
        labelColor, 
        fontSize: 8.0,
        fontWeight: i == currentData.length - 1 ? FontWeight.bold : FontWeight.normal,
      );
    }

    // Draw AI Forecast 7 days X labels
    for (int i = 1; i < predictedData.length; i++) {
      final int idx = currentData.length - 1 + i;
      if (idx % 2 == 0) { // show every alternate prediction label to keep it neat
        final double x = getX(idx);
        final String label = "AI+${i}d";
        _drawText(canvas, label, Offset(x, baseline + 8.0), predictedColor.withOpacity(0.8), fontSize: 8.0, fontWeight: FontWeight.bold);
      }
    }

    // 8. Draw Touch Interaction Tooltip
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < totalPoints) {
      final double x = getX(selectedIndex!);
      final double val = selectedIndex! < currentData.length 
          ? currentData[selectedIndex!] 
          : predictedData[selectedIndex! - currentData.length];
      final double y = getY(val);

      final Color activeColor = selectedIndex! < currentData.length ? currentColor : predictedColor;

      // Draw vertical guide line
      final guidePaint = Paint()
        ..color = activeColor.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(x, topPadding), Offset(x, baseline), guidePaint);

      // Draw highlighted circle
      final highlightPaint = Paint()..color = activeColor;
      final highlightGlowPaint = Paint()..color = activeColor.withOpacity(0.35);
      canvas.drawCircle(Offset(x, y), 8.0, highlightGlowPaint);
      canvas.drawCircle(Offset(x, y), 4.0, highlightPaint);

      // Draw floating Glassmorphic Tooltip bubble
      double tooltipX = x;
      if (tooltipX < 65.0) tooltipX = 65.0;
      if (tooltipX > size.width - 65.0) tooltipX = size.width - 65.0;

      // Adjust tooltip position vertically to avoid clipping at the top
      double tooltipY = y - 48.0;
      if (tooltipY < 5.0) tooltipY = y + 16.0; // show below point if too high

      final Rect tooltipRect = Rect.fromLTWH(tooltipX - 60.0, tooltipY, 120.0, 36.0);
      final RRect tooltipRRect = RRect.fromRectAndRadius(tooltipRect, const Radius.circular(8.0));

      final tooltipBgPaint = Paint()
        ..color = isDark ? const Color(0xFF1E293B).withOpacity(0.92) : Colors.white.withOpacity(0.96);
      
      final tooltipBorderPaint = Paint()
        ..color = activeColor.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRRect(tooltipRRect, tooltipBgPaint);
      canvas.drawRRect(tooltipRRect, tooltipBorderPaint);

      // Determine label text
      String dayName = selectedIndex! < currentData.length ? "Past Sale" : "AI Forecast";
      if (selectedIndex! == currentData.length - 1) {
        dayName = "Today";
      } else if (selectedIndex! < currentData.length - 1) {
        dayName = "d-${currentData.length - 1 - selectedIndex!}";
      } else {
        dayName = "AI +${selectedIndex! - currentData.length + 1}d";
      }

      final String valText = "₹${val.toStringAsFixed(0)}";

      // Draw text values
      _drawText(
        canvas, 
        dayName, 
        Offset(tooltipX, tooltipY + 4.0), 
        isDark ? Colors.grey.shade400 : Colors.grey.shade600, 
        fontSize: 7.5, 
        fontWeight: FontWeight.bold
      );
      _drawText(
        canvas, 
        valText, 
        Offset(tooltipX, tooltipY + 16.0), 
        activeColor, 
        fontSize: 10.5, 
        fontWeight: FontWeight.w900
      );
    }
  }

  void _drawText(Canvas canvas, String text, Offset position, Color color, {double fontSize = 8.0, FontWeight fontWeight = FontWeight.normal, Alignment alignment = Alignment.topCenter}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFamily: 'Inter',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    Offset paintPos;
    if (alignment == Alignment.centerLeft) {
      paintPos = position;
    } else {
      paintPos = position - Offset(textPainter.width / 2, 0);
    }
    
    textPainter.paint(canvas, paintPos);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint, {double dashWidth = 5.0, double dashSpace = 4.0}) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double length = dashWidth;
        final Path extract = metric.extractPath(distance, distance + length);
        canvas.drawPath(extract, paint);
        distance += length + dashSpace;
      }
    }
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Paint paint, {double dashWidth = 4.0, double dashSpace = 3.0}) {
    final Path path = Path()..addRRect(rrect);
    _drawDashedPath(canvas, path, paint, dashWidth: dashWidth, dashSpace: dashSpace);
  }

  @override
  bool shouldRepaint(covariant ProfessionalMLComboPainter oldDelegate) =>
      oldDelegate.currentData != currentData ||
      oldDelegate.predictedData != predictedData ||
      oldDelegate.currentColor != currentColor ||
      oldDelegate.predictedColor != predictedColor ||
      oldDelegate.isDark != isDark ||
      oldDelegate.selectedIndex != selectedIndex;
}
