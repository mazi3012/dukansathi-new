import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../main/pages/main_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_box.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../widgets/invoice_draft_card.dart';
import '../widgets/inventory_draft_card.dart';
import '../widgets/ai_thinking_indicator.dart';
import '../widgets/analytics_summary_card.dart';
import '../widgets/customer_dues_card.dart';
import '../widgets/customer_due_detail_card.dart';
import '../widgets/expense_report_card.dart';
import '../widgets/invoice_lookup_card.dart';
import '../widgets/product_catalog_card.dart';
import '../widgets/payment_confirmation_card.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/config.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';


import '../../../core/widgets/dukan_sathi_logo.dart';

class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isVoiceEnabled = false;
  final TtsService _ttsService = TtsService();
  late StreamSubscription<bool> _connectivitySubscription;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _ttsService.init();
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySubscription = ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) {
        setState(() {
          _isOnline = online;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatControllerProvider.notifier).loadHistory();
    });
  }


  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _audioRecorder.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        const config = RecordConfig();
        await _audioRecorder.start(config, path: ''); 
        setState(() => _isRecording = true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        _transcribeAudio(path);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  Future<void> _transcribeAudio(String path) async {
    setState(() => _isTranscribing = true);
    try {
      final response = await http.get(Uri.parse(path));
      final bytes = response.bodyBytes;

      final transResponse = await http.post(
        _getApiUri('/api/transcribe'),
        body: bytes,
      );

      if (transResponse.statusCode == 200) {
        final data = jsonDecode(transResponse.body);
        final text = data['text'] as String;
        if (text.trim().isNotEmpty) {
          _textController.text = text;
          _sendMessage(); // Auto-send transcribed text
        }
      }
    } catch (e) {
      debugPrint('Transcription error: $e');
    } finally {
      setState(() => _isTranscribing = false);
    }
  }

  void _sendMessage() {
    final text = _textController.text;
    if (text.trim().isNotEmpty) {
      ref.read(chatControllerProvider.notifier).sendMessage(text);
      _textController.clear();
      _scrollToBottom();
    }
  }

  void _showChatUploadOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border.all(
            color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder,
          ),
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Upload File to Assistant",
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.lightOnSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Import and scan products using your device files, document sheets, or bills directly in this conversation.",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            _buildChatUploadOption(
              context: context,
              icon: Iconsax.camera,
              title: "Camera OCR / Upload Photo",
              subtitle: "Snap or upload a wholesale invoice bill photo.",
              color: AppColors.success,
              onTap: () {
                Navigator.pop(context);
                _showChatImportPresetSelection(context, "Invoice OCR Photo");
              },
            ),
            const SizedBox(height: 14),
            _buildChatUploadOption(
              context: context,
              icon: Iconsax.document,
              title: "Upload PDF Invoice",
              subtitle: "Directly ingest products from a PDF receipt.",
              color: AppColors.primary,
              onTap: () {
                Navigator.pop(context);
                _showChatImportPresetSelection(context, "PDF Invoice");
              },
            ),
            const SizedBox(height: 14),
            _buildChatUploadOption(
              context: context,
              icon: Iconsax.document_text,
              title: "Upload Spreadsheet / CSV Catalog",
              subtitle: "Excel sheets or CSV inventories.",
              color: AppColors.warning,
              onTap: () {
                Navigator.pop(context);
                _showChatImportPresetSelection(context, "Excel / CSV Sheet");
              },
            ),
            const SizedBox(height: 14),
            _buildChatUploadOption(
              context: context,
              icon: Iconsax.folder_open,
              title: "Browse Device Files...",
              subtitle: "Select documents directly from your device storage.",
              color: Colors.grey,
              onTap: () {
                Navigator.pop(context);
                _showChatImportPresetSelection(context, "Custom Device File");
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatUploadOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: GlassBox(
        blur: 10,
        opacity: 0.05,
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.lightOnSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Iconsax.arrow_right_1, color: isDark ? Colors.white30 : Colors.black38, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _showChatImportPresetSelection(BuildContext context, String sourceType) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border.all(
            color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder,
          ),
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Choose Template File",
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.lightOnSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Select a preset sample to simulate uploading a file/photo to the chat assistant.",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            _buildChatPresetOption(
              context: context,
              title: "Distributor_Stock_Sheet.csv",
              subtitle: "Hygiene products CSV (matches 'Dettol Liquid Handwash' restock).",
              items: [
                {"name": "Dettol Liquid Handwash", "price": 99.0, "cost_price": 75.0, "stock_quantity": 50, "category": "Hygiene"},
                {"name": "Paracetamol 650mg", "price": 30.0, "cost_price": 18.0, "stock_quantity": 120, "category": "Pharmacy"},
                {"name": "Tata Salt 1kg", "price": 28.0, "cost_price": 22.0, "stock_quantity": 40, "category": "Grocery"},
                {"name": "Maggi Noodles 2-Min", "price": 14.0, "cost_price": 11.0, "stock_quantity": 100, "category": "Grocery"},
              ],
            ),
            const SizedBox(height: 12),
            _buildChatPresetOption(
              context: context,
              title: "Grocery_Vendor_Invoice_042.pdf",
              subtitle: "Standard wholesale bill PDF (matches multiple restocks).",
              items: [
                {"name": "Fortune Soyabean Oil 1L", "price": 165.0, "cost_price": 140.0, "stock_quantity": 30, "category": "Grocery"},
                {"name": "Aashirvaad Atta 5kg", "price": 260.0, "cost_price": 215.0, "stock_quantity": 25, "category": "Grocery"},
                {"name": "Dettol Liquid Handwash", "price": 99.0, "cost_price": 75.0, "stock_quantity": 20, "category": "Hygiene"},
                {"name": "Colgate MaxFresh 150g", "price": 112.0, "cost_price": 90.0, "stock_quantity": 50, "category": "Hygiene"},
              ],
            ),
            const SizedBox(height: 12),
            _buildChatPresetOption(
              context: context,
              title: "Wholesale_Bill_Photo.jpg",
              subtitle: "Simulated camera invoice photograph (scans electronics catalog).",
              items: [
                {"name": "Syska LED Bulb 9W", "price": 140.0, "cost_price": 100.0, "stock_quantity": 60, "category": "Electronics"},
                {"name": "Syska LED Bulb 12W", "price": 180.0, "cost_price": 130.0, "stock_quantity": 40, "category": "Electronics"},
                {"name": "SanDisk 64GB Flash Drive", "price": 450.0, "cost_price": 320.0, "stock_quantity": 15, "category": "Electronics"},
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatPresetOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        Navigator.pop(context); // Close preset selection sheet
        _showIntentPromptSheet(context, title, items);
      },
      borderRadius: BorderRadius.circular(14),
      child: GlassBox(
        blur: 5,
        opacity: 0.04,
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.lightOnSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "${items.length} Items",
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showIntentPromptSheet(BuildContext context, String title, List<Map<String, dynamic>> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textController = TextEditingController(text: "Add proposed products directly to my inventory");
    final stateSetter = ValueNotifier<String>("Add proposed products directly to my inventory");

    final quickIntents = [
      "Add proposed products directly to my inventory",
      "Scan and verify the GST, CGST, and SGST taxes in this bill",
      "Check catalog prices and mark matching products for restock",
      "Import all items and auto-categorize them",
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: AnimatedBuilder(
          animation: stateSetter,
          builder: (context, _) {
            final isButtonEnabled = stateSetter.value.trim().isNotEmpty;

            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border.all(
                  color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder,
                ),
              ),
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "Describe File Intention",
                          style: TextStyle(
                            color: isDark ? Colors.white : AppColors.lightOnSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "You must provide an instruction or question alongside '$title' to help the AI understand your goal (e.g. adding items, tax lookup, audit).",
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Text Area
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder,
                      ),
                    ),
                    child: TextField(
                      controller: textController,
                      maxLines: 3,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14),
                      onChanged: (val) {
                        stateSetter.value = val;
                      },
                      decoration: InputDecoration(
                        hintText: "E.g., Please import these items to my grocery list...",
                        hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Quick Action Tags
                  Text(
                    "QUICK INTENT TEMPLATES",
                    style: TextStyle(
                      color: isDark ? Colors.white30 : Colors.black45,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickIntents.map((intent) {
                      final isSelected = stateSetter.value == intent;
                      return InkWell(
                        onTap: () {
                          textController.text = intent;
                          stateSetter.value = intent;
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected 
                              ? AppColors.primary.withOpacity(0.15) 
                              : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03)),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected 
                                ? AppColors.primary.withOpacity(0.5) 
                                : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            intent.length > 35 ? "${intent.substring(0, 35)}..." : intent,
                            style: TextStyle(
                              color: isSelected 
                                ? AppColors.primary 
                                : (isDark ? Colors.white70 : Colors.black87),
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                          ),
                          child: Text(
                            "Cancel",
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isButtonEnabled
                              ? () {
                                  Navigator.pop(context); // Close instruction prompt
                                  ref.read(chatControllerProvider.notifier).proposeBatchUpload(
                                        title,
                                        items,
                                        stateSetter.value.trim(),
                                      );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text(
                            "Confirm & Send",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _confirmClearChat(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Iconsax.trash, color: AppColors.error),
            const SizedBox(width: 8),
            Text(
              "Clear Conversation?",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to delete all messages? This will also reset the AI assistant's short-term memory.",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(chatControllerProvider.notifier).clearChat();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Chat cleared and AI memory reset!"),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Clear"),
          ),
        ],
      ),
    );
  }

  void _showApiUrlConfigDialog(BuildContext context) {
    final controller = TextEditingController(text: AppConfig.apiUrl);
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Iconsax.setting_2, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              "Assistant Server Config",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Configure the server URL that the Dukan Sathi AI assistant connects to.",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.darkGlassBorder),
                ),
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: "API Server URL",
                    labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Quick Presets:",
                style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    backgroundColor: Colors.white10,
                    label: const Text("Localhost (USB)", style: TextStyle(color: Colors.white, fontSize: 11)),
                    onPressed: () {
                      controller.text = "http://localhost:3100";
                    },
                  ),
                  ActionChip(
                    backgroundColor: Colors.white10,
                    label: const Text("Production (Render)", style: TextStyle(color: Colors.white, fontSize: 11)),
                    onPressed: () {
                      controller.text = "https://dukan-sathi-pro.onrender.com";
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 8),
              const Text(
                "💡 Physical Vivo Phone Testing Tip:",
                style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                "1. Connect your Vivo phone via USB cable.\n"
                "2. Ensure USB Debugging is turned ON in developer options.\n"
                "3. Select 'Localhost (USB)' preset.\n"
                "4. Run this command on your computer terminal:\n"
                "   adb reverse tcp:3100 tcp:3100\n"
                "This links your physical phone directly to your computer's local Genkit server!",
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await AppConfig.setApiUrl(newUrl);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("API URL updated to: $newUrl"),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatControllerProvider);

    // Auto-scroll when new messages arrive
    ref.listen<List<ChatMessage>>(chatControllerProvider, (previous, next) {
      if (previous?.length != next.length) {
        _scrollToBottom();
        
        // If voice is enabled, find the new messages and speak the AI text
        if (_isVoiceEnabled && previous != null && next.length > previous.length) {
          final newMessages = next.sublist(previous.length);
          for (var msg in newMessages) {
            if (msg.type == MessageType.aiText && !msg.isTyping) {
              _ttsService.speak(msg.text);
              break; // Speak the first new AI text found in this update
            }
          }
        }
      }
    });


    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(Iconsax.arrow_left_2, color: Theme.of(context).iconTheme.color),
                onPressed: () => Navigator.pop(context),
              )
            : IconButton(
                icon: Icon(Iconsax.menu, color: Theme.of(context).iconTheme.color),
                onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
              ),
        title: const DukanSathiHeader(
          height: 28,
          showGlow: false,
          animate: true,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Iconsax.setting_2, color: Theme.of(context).iconTheme.color),
            onPressed: () => _showApiUrlConfigDialog(context),
          ),
          IconButton(
            icon: Icon(Iconsax.trash, color: Theme.of(context).iconTheme.color),
            onPressed: () => _confirmClearChat(context),
          ),
          IconButton(
            icon: Icon(
              _isVoiceEnabled ? Iconsax.volume_high : Iconsax.volume_cross,
              color: _isVoiceEnabled ? Theme.of(context).primaryColor : Theme.of(context).iconTheme.color,
            ),
            onPressed: () {
              setState(() {
                _isVoiceEnabled = !_isVoiceEnabled;
              });
              if (!_isVoiceEnabled) {
                _ttsService.stop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Voice Output Enabled"),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_isOnline
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: GlassBox(
                    blur: 20,
                    opacity: 0.1,
                    border: Border.all(color: AppColors.darkGlassBorder),
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.error.withOpacity(0.3)),
                            ),
                            child: const Icon(
                              Iconsax.wifi_square,
                              size: 48,
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            "AI Assistant is Offline",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Dukan Sathi AI utilizes strictly online neural processing engines to run voice recognition and billing generation. Please check your internet connection.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isOnline = ConnectivityService.instance.isOnline;
                              });
                              if (_isOnline) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Connected! AI Voice Chat initialized."),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Iconsax.refresh, size: 18),
                            label: const Text("Retry Connection"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          : Stack(
              children: [
                // Background handled by Scaffold
                const SizedBox.expand(),
                
                // Chat List
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(20).copyWith(
                          bottom: 100,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildMessageRow(context, msg),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                
                // Input Area
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: _buildInputArea(context),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMessageRow(BuildContext context, ChatMessage msg) {
    switch (msg.type) {
      case MessageType.user:
        return _buildUserMessage(context, msg.text);
      case MessageType.aiText:
        return _buildAiMessage(context, msg.text, msg.isTyping);
      case MessageType.aiDraftInvoice:
        return InvoiceDraftCard(payload: msg.payload as Map<String, dynamic>?);
      case MessageType.aiDraftInventory:
        return InventoryDraftCard(
          payload: msg.payload,
          onApproved: () {
            ref.read(inventoryProvider.notifier).fetchProducts(forceRefresh: true);
            ref.read(dashboardProvider.notifier).fetchDashboardData();
          },
        );
      case MessageType.aiAnalyticsSummary:
        return AnalyticsSummaryCard(payload: Map<String, dynamic>.from(msg.payload as Map));
      case MessageType.aiCustomerDuesList:
        return CustomerDuesCard(payload: Map<String, dynamic>.from(msg.payload as Map));
      case MessageType.aiCustomerDueDetail:
        return CustomerDueDetailCard(payload: Map<String, dynamic>.from(msg.payload as Map));
      case MessageType.aiExpenseReport:
        return ExpenseReportCard(payload: Map<String, dynamic>.from(msg.payload as Map));
      case MessageType.aiInvoiceLookup:
        return InvoiceLookupCard(payload: Map<String, dynamic>.from(msg.payload as Map));
      case MessageType.aiProductCatalog:
        return ProductCatalogCard(payload: Map<String, dynamic>.from(msg.payload as Map));
      case MessageType.aiPaymentConfirmation:
        return PaymentConfirmationCard(payload: Map<String, dynamic>.from(msg.payload as Map));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildUserMessage(BuildContext context, String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 40),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
      ),
    );
  }

  Widget _buildAiMessage(BuildContext context, String text, bool isTyping) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 40),
        child: GlassBox(
          opacity: 0.1,
          blur: 10,
          borderRadius: 12,
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark 
                ? AppColors.darkGlassBorder 
                : AppColors.lightGlassBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: isTyping
                ? const AiThinkingIndicator()
                : Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 15,
            bottom: MediaQuery.of(context).viewInsets.bottom > 0
                ? 15
                : MediaQuery.of(context).padding.bottom + 15,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.8),
            border: Border(
              top: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? AppColors.darkGlassBorder 
                    : AppColors.lightGlassBorder,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? AppColors.darkGlassBorder 
                          : AppColors.lightGlassBorder,
                    ),
                  ),
                  child: TextField(
                    controller: _textController,
                    style: Theme.of(context).textTheme.bodyLarge,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: _isTranscribing ? "Transcribing..." : "Ask Dukan Sathi...",
                      hintStyle: Theme.of(context).textTheme.bodySmall,
                      border: InputBorder.none,
                      icon: IconButton(
                        icon: const Icon(Iconsax.paperclip, color: AppColors.primary),
                        onPressed: () => _showChatUploadOptions(context),
                      ),
                      suffixIcon: _isTranscribing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_isRecording) {
                    _stopRecording();
                  } else {
                    _startRecording();
                  }
                },
                onLongPress: _startRecording,
                onLongPressUp: _stopRecording,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording 
                        ? Colors.red.withOpacity(0.2) 
                        : Theme.of(context).cardColor,
                    border: Border.all(
                      color: _isRecording 
                          ? Colors.red 
                          : (Theme.of(context).brightness == Brightness.dark 
                              ? AppColors.darkGlassBorder 
                              : AppColors.lightGlassBorder),
                    ),
                    boxShadow: _isRecording
                        ? [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.3),
                              blurRadius: 10,
                              spreadRadius: 2,
                            )
                          ]
                        : [],
                  ),
                  child: Icon(
                    _isRecording ? Iconsax.stop : Iconsax.microphone_2,
                    color: _isRecording ? Colors.red : Theme.of(context).iconTheme.color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Iconsax.send_1, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Uri _getApiUri(String path) {
  return AppConfig.getApiUri(path);
}
