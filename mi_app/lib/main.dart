import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';


import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';


Future<Uint8List> _processBrandedPhotoInIsolate(
  Uint8List originalBytes,
  Uint8List? frameBytes,
  Uint8List? watermarkBytes,
  int orientationIndex,
  int overlayIndex,
  String eventName,
) async {
  final original = img.decodeImage(originalBytes);
  if (original == null) {
    throw Exception('No se pudo procesar la fotografía.');
  }

  final landscape = orientationIndex == PrintOrientation.landscape.index;
  final targetWidth = landscape ? 1600 : 1067;
  final targetHeight = landscape ? 1067 : 1600;
  final targetRatio = targetWidth / targetHeight;

  final originalRatio = original.width / original.height;
  int cropWidth = original.width;
  int cropHeight = original.height;

  if (originalRatio > targetRatio) {
    cropWidth = (original.height * targetRatio).round();
  } else {
    cropHeight = (original.width / targetRatio).round();
  }

  final cropX = ((original.width - cropWidth) / 2).round();
  final cropY = ((original.height - cropHeight) / 2).round();

  final cropped = img.copyCrop(
    original,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );

  final resized = img.copyResize(
    cropped,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.linear,
  );

  final brandingHeight = landscape ? 105 : 120;

  img.fillRect(
    resized,
    x1: 0,
    y1: targetHeight - brandingHeight,
    x2: targetWidth - 1,
    y2: targetHeight - 1,
    color: img.ColorRgb8(9, 7, 13),
  );

  img.fillRect(
    resized,
    x1: 0,
    y1: targetHeight - brandingHeight,
    x2: targetWidth - 1,
    y2: targetHeight - brandingHeight + 6,
    color: img.ColorRgb8(123, 44, 191),
  );

  img.drawString(
    resized,
    'PALOMITOPTY',
    font: img.arial24,
    x: 30,
    y: targetHeight - brandingHeight + 18,
    color: img.ColorRgb8(255, 255, 255),
  );

  img.drawString(
    resized,
    eventName,
    font: img.arial14,
    x: 30,
    y: targetHeight - 38,
    color: img.ColorRgb8(210, 210, 210),
  );

  if (overlayIndex == OverlayType.frame.index && frameBytes != null) {
    final frame = img.decodeImage(frameBytes);
    if (frame != null) {
      final resizedFrame = img.copyResize(
        frame,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );
      img.compositeImage(resized, resizedFrame);
    }
  }

  if (overlayIndex == OverlayType.watermark.index &&
      watermarkBytes != null) {
    final logo = img.decodeImage(watermarkBytes);
    if (logo != null) {
      final maxWidth = (targetWidth * 0.28).round();
      final resizedLogo = img.copyResize(
        logo,
        width: maxWidth,
        interpolation: img.Interpolation.linear,
      );

      final x = targetWidth - resizedLogo.width - 30;
      final y = targetHeight -
          brandingHeight -
          resizedLogo.height -
          20;

      img.compositeImage(
        resized,
        resizedLogo,
        dstX: x,
        dstY: y,
      );
    }
  }

  return Uint8List.fromList(
    img.encodeJpg(resized, quality: 90),
  );
}

Future<Uint8List> _buildPdfInIsolate(
  Uint8List photoBytes,
  double width,
  double height,
) async {
  final document = pw.Document();
  final format = PdfPageFormat(
    width,
    height,
    marginAll: 0,
  );

  final image = pw.MemoryImage(photoBytes);

  document.addPage(
    pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) {
        return pw.SizedBox(
          width: format.width,
          height: format.height,
          child: pw.Image(
            image,
            fit: pw.BoxFit.fill,
          ),
        );
      },
    ),
  );

  return document.save();
}

const Color kPurple = Color(0xFF7B2CBF);
const Color kDark = Color(0xFF09070D);
const Color kCard = Color(0xFF17131D);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = [];

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error obteniendo cámaras: $e');
  }

  runApp(
    PalomitoptyBoothApp(
      cameras: cameras,
    ),
  );
}

// ============================================================
// APP
// ============================================================

class PalomitoptyBoothApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const PalomitoptyBoothApp({
    super.key,
    required this.cameras,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PALOMITOPTY BOOTH',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kDark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(
        cameras: cameras,
      ),
    );
  }
}


// ============================================================
// HOME
// ============================================================

class HomePage extends StatelessWidget {
  final List<CameraDescription> cameras;

  const HomePage({
    super.key,
    required this.cameras,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kDark,
              Color(0xFF160B20),
              kDark,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 600,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 25),

                        Image.asset(
                          'assets/palomitopty_logo.png',
                          width: 430,
                          height: 430,
                          fit: BoxFit.contain,
                          cacheWidth: 860,
                          filterQuality: FilterQuality.medium,
                        ),

                        const SizedBox(height: 25),

                        _homeButton(
                          context,
                          icon: Icons.camera_alt,
                          text: 'INICIAR BOOTH',
                          onPressed: cameras.isEmpty
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CameraPage(
                                        cameras: cameras,
                                      ),
                                    ),
                                  );
                                },
                        ),

                        const SizedBox(height: 16),

                        _homeButton(
                          context,
                          icon: Icons.event,
                          text: 'CONFIGURAR EVENTO',
                          outlined: true,
                          onPressed: cameras.isEmpty
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EventsPage(
                                        cameras: cameras,
                                      ),
                                    ),
                                  );
                                },
                        ),

                        const SizedBox(height: 55),

                        Text(
                          cameras.isEmpty
                              ? 'No se detectó ninguna cámara'
                              : '${cameras.length} cámara(s) disponible(s)',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _homeButton(
    BuildContext context, {
    required IconData icon,
    required String text,
    required VoidCallback? onPressed,
    bool outlined = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 68,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(
                text,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(
                  color: kPurple,
                  width: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(35),
                ),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(
                text,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPurple,
                foregroundColor: Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(35),
                ),
              ),
            ),
    );
  }
}

// ============================================================
// EVENTOS LOCALES
// ============================================================

class BoothEvent {
  final String id;
  String name;
  String date;
  String client;
  String folderPath;
  String? framePath;
  String? logoPath;
  String printFormat;
  bool qrEnabled;
  String status;
  int photoCount;

  BoothEvent({
    required this.id,
    required this.name,
    required this.date,
    this.client = '',
    required this.folderPath,
    this.framePath,
    this.logoPath,
    this.printFormat = '4x6',
    this.qrEnabled = true,
    this.status = 'Activo',
    this.photoCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'date': date,
        'client': client,
        'folderPath': folderPath,
        'framePath': framePath,
        'logoPath': logoPath,
        'printFormat': printFormat,
        'qrEnabled': qrEnabled,
        'status': status,
        'photoCount': photoCount,
      };

  factory BoothEvent.fromJson(Map<String, dynamic> json) {
    return BoothEvent(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Evento PALOMITOPTY',
      date: json['date'] as String? ?? '',
      client: json['client'] as String? ?? '',
      folderPath: json['folderPath'] as String? ?? '',
      framePath: json['framePath'] as String?,
      logoPath: json['logoPath'] as String?,
      printFormat: json['printFormat'] as String? ?? '4x6',
      qrEnabled: json['qrEnabled'] as bool? ?? true,
      status: json['status'] as String? ?? 'Activo',
      photoCount: (json['photoCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class EventStorage {
  static Future<Directory> root() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/PALOMITOPTY/EVENTOS');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> indexFile() async {
    final dir = await root();
    return File('${dir.path}/eventos.json');
  }

  static Future<List<BoothEvent>> loadEvents() async {
    try {
      final file = await indexFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(BoothEvent.fromJson)
          .toList();
    } catch (e) {
      debugPrint('Error cargando eventos: $e');
      return [];
    }
  }

  static Future<void> saveEvents(List<BoothEvent> events) async {
    final file = await indexFile();
    await file.writeAsString(
      jsonEncode(events.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  static String safeName(String value) {
    final clean = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑ _-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return clean.isEmpty ? 'Evento_PALOMITOPTY' : clean;
  }

  static Future<Directory> createEventFolder(String name, String id) async {
    final base = await root();
    final folder = Directory('${base.path}/${safeName(name)}_$id');
    await Directory('${folder.path}/fotos').create(recursive: true);
    await Directory('${folder.path}/configuracion').create(recursive: true);
    return folder;
  }

  static Future<String> copyAsset(
    Uint8List bytes,
    String folderPath,
    String filename,
  ) async {
    final file = File('$folderPath/configuracion/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

// ============================================================
// MIS EVENTOS
// ============================================================

class EventsPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const EventsPage({super.key, required this.cameras});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  List<BoothEvent> events = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await EventStorage.loadEvents();
    if (!mounted) return;
    setState(() {
      events = loaded;
      loading = false;
    });
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EventSetupPage(cameras: widget.cameras),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _openEvent(BoothEvent event) async {
    if (event.status == 'Finalizado') {
      final resume = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('EVENTO FINALIZADO'),
          content: Text(
            '¿Quieres volver a trabajar en "${event.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ABRIR'),
            ),
          ],
        ),
      );
      if (resume != true) return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraPage(
          cameras: widget.cameras,
          eventName: event.name,
          eventFrameBytes: event.framePath == null
              ? null
              : File(event.framePath!).readAsBytesSync(),
          eventDirectory: event.folderPath,
          eventId: event.id,
          qrEnabled: event.qrEnabled,
        ),
      ),
    ).then((_) => _load());
  }

  Future<void> _delete(BoothEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ELIMINAR EVENTO'),
        content: Text(
          'Se eliminará el evento y sus fotografías del iPad. Esta acción no se puede deshacer.\n\n${event.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final dir = Directory(event.folderPath);
      if (await dir.exists()) await dir.delete(recursive: true);
      events.removeWhere((e) => e.id == event.id);
      await EventStorage.saveEvents(events);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      appBar: AppBar(
        title: const Text('MIS EVENTOS'),
        backgroundColor: Colors.transparent,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                children: [
                  SizedBox(
                    height: 58,
                    child: ElevatedButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'NUEVO EVENTO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (events.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(35),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.event_note, size: 60, color: Colors.white30),
                          SizedBox(height: 15),
                          Text('Aún no tienes eventos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text('Crea tu primer evento para comenzar.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    )
                  else
                    ...events.map(
                      (event) => Card(
                        color: kCard,
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          leading: CircleAvatar(
                            backgroundColor: kPurple.withValues(alpha: 0.18),
                            child: Icon(
                              event.status == 'Finalizado' ? Icons.check : Icons.event,
                              color: kPurple,
                            ),
                          ),
                          title: Text(event.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${event.date.isEmpty ? 'Sin fecha' : event.date}  •  ${event.photoCount} fotos\n${event.status}'),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'open') _openEvent(event);
                              if (value == 'delete') _delete(event);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'open', child: Text('Abrir evento')),
                              PopupMenuItem(value: 'delete', child: Text('Eliminar evento')),
                            ],
                          ),
                          onTap: () => _openEvent(event),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// EVENT SETUP
// ============================================================

class EventSetupPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final BoothEvent? existingEvent;

  const EventSetupPage({
    super.key,
    required this.cameras,
    this.existingEvent,
  });

  @override
  State<EventSetupPage> createState() => _EventSetupPageState();
}

class _EventSetupPageState extends State<EventSetupPage> {
  final TextEditingController eventController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController clientController = TextEditingController();

  Uint8List? frameBytes;
  Uint8List? logoBytes;
  String frameName = 'Sin marco';
  String logoName = 'Sin logo';
  String printFormat = '4x6';
  bool qrEnabled = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existingEvent;
    if (e != null) {
      eventController.text = e.name;
      dateController.text = e.date;
      clientController.text = e.client;
      printFormat = e.printFormat;
      qrEnabled = e.qrEnabled;
      if (e.framePath != null && File(e.framePath!).existsSync()) {
        frameBytes = File(e.framePath!).readAsBytesSync();
        frameName = 'Marco seleccionado';
      }
      if (e.logoPath != null && File(e.logoPath!).existsSync()) {
        logoBytes = File(e.logoPath!).readAsBytesSync();
        logoName = 'Logo seleccionado';
      }
    }
  }

  Future<void> selectFrame() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 3200,
        imageQuality: 92,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        frameBytes = bytes;
        frameName = 'Marco seleccionado';
      });
    } catch (e) {
      debugPrint('Error seleccionando marco: $e');
    }
  }

  Future<void> selectLogo() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 92,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        logoBytes = bytes;
        logoName = 'Logo seleccionado';
      });
    } catch (e) {
      debugPrint('Error seleccionando logo: $e');
    }
  }

  Future<void> startEvent() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final name = eventController.text.trim().isEmpty
          ? 'Evento PALOMITOPTY'
          : eventController.text.trim();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final folder = await EventStorage.createEventFolder(name, id);
      String? framePath;
      String? logoPath;
      if (frameBytes != null) {
        framePath = await EventStorage.copyAsset(frameBytes!, folder.path, 'marco.jpg');
      }
      if (logoBytes != null) {
        logoPath = await EventStorage.copyAsset(logoBytes!, folder.path, 'logo.jpg');
      }

      final event = BoothEvent(
        id: id,
        name: name,
        date: dateController.text.trim(),
        client: clientController.text.trim(),
        folderPath: folder.path,
        framePath: framePath,
        logoPath: logoPath,
        printFormat: printFormat,
        qrEnabled: qrEnabled,
      );
      final events = await EventStorage.loadEvents();
      events.insert(0, event);
      await EventStorage.saveEvents(events);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CameraPage(
            cameras: widget.cameras,
            eventName: event.name,
            eventFrameBytes: frameBytes,
            eventDirectory: event.folderPath,
            eventId: event.id,
            qrEnabled: event.qrEnabled,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear el evento: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      appBar: AppBar(
        title: const Text('NUEVO EVENTO'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Crear nuevo evento', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: eventController,
                decoration: InputDecoration(
                  labelText: 'Nombre del evento',
                  hintText: 'Ej. Boda Juan & María',
                  prefixIcon: const Icon(Icons.event),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: dateController,
                decoration: InputDecoration(
                  labelText: 'Fecha del evento',
                  hintText: 'Ej. 28/09/2026',
                  prefixIcon: const Icon(Icons.calendar_today),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: clientController,
                decoration: InputDecoration(
                  labelText: 'Cliente (opcional)',
                  hintText: 'Ej. Juan Pérez',
                  prefixIcon: const Icon(Icons.person_outline),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 24),
              const Text('PLANTILLA / MARCO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 10),
              Container(
                height: 190,
                decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
                child: frameBytes == null
                    ? const Center(child: Text('Sin marco seleccionado', style: TextStyle(color: Colors.white54)))
                    : Image.memory(frameBytes!, fit: BoxFit.contain),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(onPressed: selectFrame, icon: const Icon(Icons.image), label: const Text('ELEGIR MARCO')),
              Center(child: Text(frameName, style: const TextStyle(color: Colors.white54))),
              const SizedBox(height: 22),
              const Text('LOGO DEL EVENTO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 10),
              Container(
                height: 130,
                decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
                child: logoBytes == null
                    ? const Center(child: Text('Sin logo seleccionado', style: TextStyle(color: Colors.white54)))
                    : Image.memory(logoBytes!, fit: BoxFit.contain),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: selectLogo, icon: const Icon(Icons.branding_watermark), label: const Text('ELEGIR LOGO')),
              Center(child: Text(logoName, style: const TextStyle(color: Colors.white54))),
              const SizedBox(height: 22),
              const Text('FORMATO DE IMPRESIÓN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '4x6', label: Text('4 × 6')),
                  ButtonSegment(value: '6x4', label: Text('6 × 4')),
                ],
                selected: {printFormat},
                onSelectionChanged: (value) => setState(() => printFormat = value.first),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('QR de las fotos'),
                subtitle: const Text('Permite generar el QR durante el evento'),
                value: qrEnabled,
                onChanged: (value) => setState(() => qrEnabled = value),
              ),
              const SizedBox(height: 25),
              SizedBox(
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: saving ? null : startEvent,
                  icon: saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
                  label: Text(saving ? 'CREANDO EVENTO...' : 'INICIAR EVENTO', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  style: ElevatedButton.styleFrom(backgroundColor: kPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    eventController.dispose();
    dateController.dispose();
    clientController.dispose();
    super.dispose();
  }
}

// ============================================================
// CAMERA PAGE
// ============================================================

class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String eventName;
  final Uint8List? eventFrameBytes;
  final String? eventDirectory;
  final String? eventId;
  final bool qrEnabled;

  const CameraPage({
    super.key,
    required this.cameras,
    this.eventName = 'Evento PALOMITOPTY',
    this.eventFrameBytes,
    this.eventDirectory,
    this.eventId,
    this.qrEnabled = true,
  });

  @override
  State<CameraPage> createState() =>
      _CameraPageState();
}

class _CameraPageState extends State<CameraPage>
    with WidgetsBindingObserver {
  CameraController? controller;

  Timer? countdownTimer;

  int countdown = 0;
  int countdownSeconds = 3;

  XFile? photo;

  Uint8List? selectedFrameBytes;
  Uint8List? watermarkBytes;

  // Cache de procesamiento: evita reconstruir la foto al pulsar QR/IMPRIMIR.
  Uint8List? brandedPhotoCache;
  Uint8List? pdfCache;
  Future<Uint8List>? _brandingFuture;
  Future<Uint8List>? _pdfFuture;
  int _brandingGeneration = 0;

  bool isSaving = false;
  bool isPrinting = false;
  bool isInitializing = true;
  bool flashEnabled = false;

  int cameraIndex = 0;

  PrintOrientation orientation =
      PrintOrientation.portrait;

  OverlayType overlayType =
      OverlayType.none;

  String overlayName = 'Sin marco';

  // ==========================================================
  // SERVIDOR QR TEMPORAL
  // ==========================================================

  HttpServer? qrServer;

  String? qrUrl;

  bool qrServerRunning = false;

  Timer? qrExpirationTimer;

  String get eventName => widget.eventName;

  Future<void> _saveEventPhoto(Uint8List bytes) async {
    final directory = widget.eventDirectory;
    final id = widget.eventId;
    if (directory == null || id == null) return;

    try {
      final photos = Directory('$directory/fotos');
      if (!await photos.exists()) await photos.create(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${photos.path}/PALOMITOPTY_$stamp.jpg');
      await file.writeAsBytes(bytes, flush: true);

      final events = await EventStorage.loadEvents();
      final index = events.indexWhere((e) => e.id == id);
      if (index >= 0) {
        events[index].photoCount++;
        await EventStorage.saveEvents(events);
      }
    } catch (e) {
      debugPrint('No se pudo guardar copia del evento: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    selectedFrameBytes = widget.eventFrameBytes;

    if (selectedFrameBytes != null) {
      overlayType = OverlayType.frame;
      overlayName = 'Plantilla del evento';
    }

    initializeCamera();
  }

  // ==========================================================
  // CAMERA INITIALIZATION
  // ==========================================================

  Future<void> initializeCamera() async {
    if (widget.cameras.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        isInitializing = true;
      });
    }

    final camera = widget.cameras[cameraIndex];

    final newController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await newController.initialize();

      await newController.lockCaptureOrientation(
        DeviceOrientation.portraitUp,
      );

      controller = newController;

      if (flashEnabled &&
          camera.lensDirection ==
              CameraLensDirection.back) {
        try {
          await controller!.setFlashMode(
            FlashMode.torch,
          );
        } catch (_) {}
      }

      if (!mounted) {
        await newController.dispose();
        return;
      }

      setState(() {
        isInitializing = false;
      });
    } catch (e) {
      debugPrint(
        'Error inicializando cámara: $e',
      );

      await newController.dispose();

      if (!mounted) return;

      setState(() {
        isInitializing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo iniciar la cámara: $e',
          ),
        ),
      );
    }
  }

  // ==========================================================
  // SWITCH CAMERA
  // ==========================================================

  Future<void> switchCamera() async {
    if (widget.cameras.length < 2) return;

    if (countdown > 0 ||
        isSaving ||
        isPrinting) {
      return;
    }

    cameraIndex =
        (cameraIndex + 1) % widget.cameras.length;

    final oldController = controller;

    controller = null;

    if (mounted) {
      setState(() {
        isInitializing = true;
      });
    }

    await oldController?.dispose();

    await initializeCamera();
  }

  // ==========================================================
  // FLASH
  // ==========================================================

  Future<void> toggleFlash() async {
    final c = controller;

    if (c == null ||
        !c.value.isInitialized) {
      return;
    }

    if (c.description.lensDirection ==
        CameraLensDirection.front) {
      return;
    }

    try {
      flashEnabled = !flashEnabled;

      await c.setFlashMode(
        flashEnabled
            ? FlashMode.torch
            : FlashMode.off,
      );

      setStateSafe(() {});
    } catch (e) {
      debugPrint(
        'Flash no disponible: $e',
      );
    }
  }

  // ==========================================================
  // COUNTDOWN
  // ==========================================================

  Future<void> startCountdown() async {
    final c = controller;

    if (c == null ||
        !c.value.isInitialized ||
        countdown > 0 ||
        isSaving ||
        isPrinting) {
      return;
    }

    setStateSafe(() {
      countdown = countdownSeconds;
    });

    countdownTimer?.cancel();

    countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (countdown > 1) {
          setStateSafe(() {
            countdown--;
          });
        } else {
          timer.cancel();

          setStateSafe(() {
            countdown = 0;
          });

          await capturePhoto();
        }
      },
    );
  }

  // ==========================================================
  // CAPTURE
  // ==========================================================

  Future<void> capturePhoto() async {
    final c = controller;

    if (c == null ||
        !c.value.isInitialized ||
        c.value.isTakingPicture) {
      return;
    }

    try {
      final captured = await c.takePicture();

      if (!mounted) return;

      setState(() {
        photo = captured;
        // La cámara está bloqueada en portraitUp.
        orientation = PrintOrientation.portrait;
      });

      // Empieza a procesar mientras el usuario revisa la foto.
      unawaited(() async {
        try {
          final finalBytes = await createBrandedPhoto();
          await _saveEventPhoto(finalBytes);
        } catch (e) {
          debugPrint('Error guardando copia del evento: $e');
        }
      }());
    } catch (e) {
      debugPrint('Error capturando: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo tomar la fotografía: $e',
          ),
        ),
      );
    }
  }

  // ==========================================================
  // SELECT FRAME
  // ==========================================================

  Future<void> selectFrame() async {
    if (isSaving || isPrinting) return;

    try {
      final picker = ImagePicker();

      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 3200,
        imageQuality: 92,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();

      if (!mounted) return;

      setState(() {
        selectedFrameBytes = bytes;
        watermarkBytes = null;
        overlayType = OverlayType.frame;
        overlayName = 'Marco personalizado';
      });
      _invalidateBrandedPhotoCache();
      unawaited(createBrandedPhoto());
    } catch (e) {
      debugPrint(
        'Error seleccionando marco: $e',
      );
    }
  }

  // ==========================================================
  // SELECT WATERMARK
  // ==========================================================

  Future<void> selectWatermark() async {
    if (isSaving || isPrinting) return;

    try {
      final picker = ImagePicker();

      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 92,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();

      if (!mounted) return;

      setState(() {
        watermarkBytes = bytes;
        selectedFrameBytes = null;
        overlayType = OverlayType.watermark;
        overlayName = 'Logo / Marca de agua';
      });
      _invalidateBrandedPhotoCache();
      unawaited(createBrandedPhoto());
    } catch (e) {
      debugPrint(
        'Error seleccionando logo: $e',
      );
    }
  }

  // ==========================================================
  // REMOVE OVERLAY
  // ==========================================================

  void removeOverlay() {
    setState(() {
      selectedFrameBytes = null;
      watermarkBytes = null;
      overlayType = OverlayType.none;
      overlayName = 'Sin marco';
    });
    _invalidateBrandedPhotoCache();
    if (photo != null) {
      unawaited(createBrandedPhoto());
    }
  }

  // ==========================================================
  // CREATE FINAL PHOTO
  // ==========================================================

  void _invalidateBrandedPhotoCache() {
    _brandingGeneration++;
    brandedPhotoCache = null;
    pdfCache = null;

    // No reutilizar un procesamiento que corresponde a una foto/overlay/orientación
    // anterior. El Future viejo puede terminar por su cuenta, pero su resultado
    // ya no se guardará en la caché gracias a _brandingGeneration.
    _brandingFuture = null;
    _pdfFuture = null;
  }

  Future<Uint8List> createBrandedPhoto() async {
    final currentPhoto = photo;

    if (currentPhoto == null) {
      throw Exception('No existe fotografía.');
    }

    final cached = brandedPhotoCache;
    if (cached != null) {
      return cached;
    }

    final running = _brandingFuture;
    if (running != null) {
      return running;
    }

    final generation = _brandingGeneration;
    final orientationIndex = orientation.index;
    final overlayIndex = overlayType.index;
    final frameBytes = selectedFrameBytes;
    final watermark = watermarkBytes;
    final currentEventName = eventName;

    // IMPORTANTE:
    // No envolver Isolate.run() dentro de una closure de _CameraPageState.
    // Esa closure captura "this" y Dart no puede enviarlo al isolate.
    // Primero leemos los bytes y después enviamos únicamente datos simples
    // y Uint8List al isolate.
    final originalBytes = await currentPhoto.readAsBytes();

    // Puede haber cambiado la foto mientras esperábamos la lectura.
    if (!mounted ||
        !identical(photo, currentPhoto) ||
        generation != _brandingGeneration) {
      if (photo == null) {
        throw Exception('La fotografía ya no está disponible.');
      }
      return createBrandedPhoto();
    }

    final future = Isolate.run(
      () => _processBrandedPhotoInIsolate(
        originalBytes,
        frameBytes,
        watermark,
        orientationIndex,
        overlayIndex,
        currentEventName,
      ),
    );

    _brandingFuture = future;

    try {
      final result = await future;

      if (generation == _brandingGeneration &&
          identical(photo, currentPhoto)) {
        brandedPhotoCache = result;
      }

      return result;
    } finally {
      if (identical(_brandingFuture, future)) {
        _brandingFuture = null;
      }
    }
  }

  Future<Uint8List> _createPdfBytes(
    Uint8List photoBytes,
  ) async {
    final cached = pdfCache;
    if (cached != null) return cached;

    final running = _pdfFuture;
    if (running != null) return running;

    final formatWidth = orientation == PrintOrientation.landscape
        ? 6 * PdfPageFormat.inch
        : 4 * PdfPageFormat.inch;
    final formatHeight = orientation == PrintOrientation.landscape
        ? 4 * PdfPageFormat.inch
        : 6 * PdfPageFormat.inch;

    // Igual que con el procesamiento de imagen, esta closure solo captura
    // variables locales enviables al isolate. Nunca captura State/BuildContext.
    final future = Isolate.run(
      () => _buildPdfInIsolate(
        photoBytes,
        formatWidth,
        formatHeight,
      ),
    );

    _pdfFuture = future;

    try {
      final result = await future;

      // pdfCache se invalida cada vez que cambia la foto, orientación
      // o plantilla, por lo que aquí corresponde al PDF actual.
      if (identical(photoBytes, brandedPhotoCache)) {
        pdfCache = result;
      }

      return result;
    } finally {
      if (identical(_pdfFuture, future)) {
        _pdfFuture = null;
      }
    }
  }

  // ==========================================================
  // TEMP FILE
  // ==========================================================

  Future<String> createTempFile(
    Uint8List bytes,
    String prefix,
  ) async {
    final directory =
        await getTemporaryDirectory();

    final file = File(
      '${directory.path}/'
      '${prefix}_'
      '${DateTime.now().millisecondsSinceEpoch}'
      '.jpg',
    );

    await file.writeAsBytes(bytes, flush: true);

    return file.path;
  }

  // ==========================================================
  // SAVE
  // ==========================================================

  Future<void> savePhoto() async {
    if (photo == null ||
        isSaving ||
        isPrinting) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final bytes =
          await createBrandedPhoto();

      bool access = await Gal.hasAccess();

      if (!access) {
        access = await Gal.requestAccess();
      }

      if (!access) {
        throw Exception(
          'Permiso de Fotos no concedido. Activa el acceso a Fotos para PALOMITOPTY BOOTH.',
        );
      }

      // Guardar directamente desde memoria evita crear/leer un archivo
      // temporal adicional y es más rápido y estable en iPadOS.
      await Gal.putImageBytes(
        bytes,
        name: 'PALOMITOPTY_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      await showMessage(
        'FOTO GUARDADA',
        'La fotografía fue guardada correctamente en la galería.',
      );
    } catch (e) {
      setStateSafe(() {
        isSaving = false;
      });

      showError(
        'No se pudo guardar: $e',
      );
    }
  }

  // ==========================================================
  // SHARE
  // ==========================================================

  Future<void> sharePhoto() async {
    if (photo == null ||
        isSaving ||
        isPrinting) {
      return;
    }

    try {
      setStateSafe(() {
        isSaving = true;
      });

      // IMPORTANTE: capturamos la posición usando context ANTES de cualquier
      // await. Esto evita el aviso use_build_context_synchronously y mantiene
      // el anclaje correcto del menú de compartir en iPad.
      final renderObject = context.findRenderObject();
      final box = renderObject is RenderBox ? renderObject : null;
      final sharePositionOrigin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;

      final bytes =
          await createBrandedPhoto();

      final path =
          await createTempFile(
        bytes,
        'palomitopty_share',
      );

      setStateSafe(() {
        isSaving = false;
      });

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(path),
          ],
          text:
              'Foto de $eventName - PALOMITOPTY BOOTH',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } catch (e) {
      setStateSafe(() {
        isSaving = false;
      });

      showError(
        'No se pudo compartir: $e',
      );
    }
  }

  // ==========================================================
  // QR - OBTENER IP LOCAL
  // ==========================================================

  Future<String?> getLocalIpAddress() async {
    try {
      final interfaces =
          await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        for (final address
            in interface.addresses) {
          final ip = address.address;

          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.16.') ||
              ip.startsWith('172.17.') ||
              ip.startsWith('172.18.') ||
              ip.startsWith('172.19.') ||
              ip.startsWith('172.20.') ||
              ip.startsWith('172.21.') ||
              ip.startsWith('172.22.') ||
              ip.startsWith('172.23.') ||
              ip.startsWith('172.24.') ||
              ip.startsWith('172.25.') ||
              ip.startsWith('172.26.') ||
              ip.startsWith('172.27.') ||
              ip.startsWith('172.28.') ||
              ip.startsWith('172.29.') ||
              ip.startsWith('172.30.') ||
              ip.startsWith('172.31.')) {
            return ip;
          }
        }
      }

      if (interfaces.isNotEmpty &&
          interfaces.first.addresses.isNotEmpty) {
        return interfaces
            .first
            .addresses
            .first
            .address;
      }
    } catch (e) {
      debugPrint(
        'Error obteniendo IP local: $e',
      );
    }

    return null;
  }

  // ==========================================================
  // QR - INICIAR SERVIDOR TEMPORAL
  // ==========================================================

  Future<String> startQrServer(
    Uint8List photoBytes,
  ) async {
    if (!widget.qrEnabled) {
      throw Exception('El QR está desactivado para este evento.');
    }
    await stopQrServer();

    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: true,
    );

    qrServer = server;
    qrServerRunning = true;

    final ip = await getLocalIpAddress();

    if (ip == null) {
      await server.close(force: true);
      qrServer = null;
      qrServerRunning = false;

      throw Exception(
        'No se pudo obtener la dirección IP local. '
        'Conecta el Booth a una red Wi-Fi.',
      );
    }

    final port = server.port;

    final url =
        'http://$ip:$port/';

    qrUrl = url;

    server.listen(
      (HttpRequest request) async {
        try {
          final path =
              request.uri.path;

          // ==================================================
          // FOTO
          // ==================================================

          if (path == '/foto.jpg') {
            request.response.headers.contentType =
                ContentType(
              'image',
              'jpeg',
            );

            request.response.headers.set(
              'Cache-Control',
              'no-store, no-cache, must-revalidate',
            );

            request.response.headers.set(
              'Pragma',
              'no-cache',
            );

            request.response.headers.contentLength =
                photoBytes.length;

            request.response.add(
              photoBytes,
            );

            await request.response.close();

            return;
          }

          // ==================================================
          // PAGINA
          // ==================================================

          if (path == '/' ||
              path == '/index.html') {
            final html =
                buildQrHtml(
              url,
              eventName,
            );

            final htmlBytes =
                utf8.encode(html);

            request.response.headers.contentType =
                ContentType(
              'text',
              'html',
              charset: 'utf-8',
            );

            request.response.headers.set(
              'Cache-Control',
              'no-store, no-cache, must-revalidate',
            );

            request.response.contentLength =
                htmlBytes.length;

            request.response.add(
              htmlBytes,
            );

            await request.response.close();

            return;
          }

          // ==================================================
          // 404
          // ==================================================

          request.response.statusCode =
              HttpStatus.notFound;

          await request.response.close();
        } catch (e) {
          debugPrint(
            'Error servidor QR: $e',
          );

          try {
            await request.response.close();
          } catch (_) {}
        }
      },
    );

    // ========================================================
    // SEGURIDAD:
    // EL QR EXPIRA AUTOMÁTICAMENTE DESPUÉS DE 10 MINUTOS.
    // ========================================================

    qrExpirationTimer?.cancel();

    qrExpirationTimer =
        Timer(
      const Duration(minutes: 10),
      () async {
        await stopQrServer();

        if (mounted) {
          setStateSafe(() {});
        }
      },
    );

    return url;
  }

  // ==========================================================
  // QR - HTML PARA EL TELÉFONO
  // ==========================================================

  String buildQrHtml(
    String baseUrl,
    String eventName,
  ) {
    final safeEventName =
        const HtmlEscape().convert(
      eventName,
    );

    final imageUrl =
        '${baseUrl}foto.jpg';

    return '''
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport"
      content="width=device-width,
               initial-scale=1.0">

<title>PALOMITOPTY BOOTH</title>

<style>

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  padding: 20px;
  min-height: 100vh;

  display: flex;
  justify-content: center;
  align-items: center;

  background:
    linear-gradient(
      135deg,
      #09070D,
      #160B20,
      #09070D
    );

  color: white;

  font-family:
    Arial,
    Helvetica,
    sans-serif;
}

.container {
  width: 100%;
  max-width: 600px;

  text-align: center;
}

.logo {
  font-size: 30px;
  font-weight: bold;
  letter-spacing: 5px;

  margin-bottom: 5px;
}

.booth {
  font-size: 14px;
  letter-spacing: 8px;

  color: #dddddd;

  margin-bottom: 20px;
}

.event {
  color: #bbbbbb;
  font-size: 15px;

  margin-bottom: 20px;
}

.photo-container {
  background: #17131D;

  padding: 10px;

  border-radius: 20px;

  box-shadow:
    0 10px 40px
    rgba(0,0,0,.5);
}

.photo {
  display: block;

  width: 100%;
  height: auto;

  border-radius: 12px;
}

.button {
  display: block;

  margin-top: 20px;

  padding: 17px;

  width: 100%;

  border-radius: 35px;

  background: #7B2CBF;

  color: white;

  text-decoration: none;

  font-size: 18px;

  font-weight: bold;
}

.info {
  margin-top: 20px;

  color: #999999;

  font-size: 12px;
}

</style>

</head>

<body>

<div class="container">

<div class="logo">
PALOMITOPTY
</div>

<div class="booth">
BOOTH
</div>

<div class="event">
$safeEventName
</div>

<div class="photo-container">

<img
  class="photo"
  src="$imageUrl"
  alt="Foto PALOMITOPTY"
/>

</div>

<a
  class="button"
  href="$imageUrl"
  download="PALOMITOPTY.jpg"
>
  ⬇ DESCARGAR FOTO
</a>

<div class="info">
Foto compartida directamente desde PALOMITOPTY BOOTH.
<br>
No se almacena en la nube.
</div>

</div>

</body>
</html>
''';
  }

  // ==========================================================
  // QR - DETENER SERVIDOR
  // ==========================================================

  Future<void> stopQrServer() async {
    qrExpirationTimer?.cancel();
    qrExpirationTimer = null;

    final server = qrServer;

    qrServer = null;
    qrUrl = null;
    qrServerRunning = false;

    if (server != null) {
      try {
        await server.close(
          force: true,
        );
      } catch (e) {
        debugPrint(
          'Error cerrando servidor QR: $e',
        );
      }
    }
  }

  // ==========================================================
  // QR - MOSTRAR
  // ==========================================================

  Future<void> showQr() async {
    if (photo == null ||
        isSaving ||
        isPrinting) {
      return;
    }

    try {
      setStateSafe(() {
        isSaving = true;
      });

      final bytes =
          await createBrandedPhoto();

      final url =
          await startQrServer(bytes);

      if (!mounted) {
        await stopQrServer();
        return;
      }

      setStateSafe(() {
        isSaving = false;
      });

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return Dialog(
            backgroundColor: kCard,
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(25),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.qr_code_2,
                      size: 45,
                      color: kPurple,
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'COMPARTIR FOTO',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Escanea este QR con tu teléfono',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                      ),
                    ),

                    const SizedBox(height: 5),

                    const Text(
                      'Debes estar conectado a la misma Wi-Fi del Booth.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      padding:
                          const EdgeInsets.all(15),
                      decoration:
                          BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                      child: QrImageView(
                        data: url,
                        size: 230,
                        backgroundColor:
                            Colors.white,
                        eyeStyle:
                            const QrEyeStyle(
                          eyeShape:
                              QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle:
                            const QrDataModuleStyle(
                          dataModuleShape:
                              QrDataModuleShape
                                  .square,
                          color: Colors.black,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Container(
                      padding:
                          const EdgeInsets.all(10),
                      decoration:
                          BoxDecoration(
                        color: Colors.black26,
                        borderRadius:
                            BorderRadius.circular(
                          10,
                        ),
                      ),
                      child: Text(
                        url,
                        textAlign:
                            TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    const Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off,
                          size: 17,
                          color: Colors.white54,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'SIN NUBE • COMPARTICIÓN LOCAL',
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                Colors.white54,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width:
                          double.infinity,
                      child:
                          ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(
                            context,
                          );
                        },
                        style:
                            ElevatedButton
                                .styleFrom(
                          backgroundColor:
                              kPurple,
                          foregroundColor:
                              Colors.white,
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 14,
                          ),
                        ),
                        child:
                            const Text(
                          'CERRAR QR',
                          style:
                              TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      await stopQrServer();

      if (mounted) {
        setStateSafe(() {});
      }
    } catch (e) {
      await stopQrServer();

      setStateSafe(() {
        isSaving = false;
      });

      showError(
        'No se pudo generar el QR: $e',
      );
    }
  }

  // ==========================================================
  // PRINT
  // ==========================================================

  Future<void> printPhoto() async {
    if (photo == null ||
        isPrinting ||
        isSaving) {
      return;
    }

    setStateSafe(() {
      isPrinting = true;
    });

    try {
      final bytes = await createBrandedPhoto();

      final format = orientation == PrintOrientation.landscape
          ? PdfPageFormat(
              6 * PdfPageFormat.inch,
              4 * PdfPageFormat.inch,
              marginAll: 0,
            )
          : PdfPageFormat(
              4 * PdfPageFormat.inch,
              6 * PdfPageFormat.inch,
              marginAll: 0,
            );

      final pdfBytes = await _createPdfBytes(bytes);

      await Printing.layoutPdf(
        name: 'PALOMITOPTY_$eventName',
        format: format,
        onLayout: (_) async => pdfBytes,
      );
    } catch (e) {
      showError('No se pudo imprimir: $e');
    } finally {
      setStateSafe(() {
        isPrinting = false;
      });
    }
  }

  // ==========================================================
  // FINALIZAR EVENTO
  // ==========================================================

  Future<void> finalizeEvent() async {
    final id = widget.eventId;
    if (id == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FINALIZAR EVENTO'),
        content: Text('¿Quieres finalizar "$eventName"?\n\nLas fotos permanecerán guardadas en el iPad.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('FINALIZAR')),
        ],
      ),
    );
    if (confirmed != true) return;

    final events = await EventStorage.loadEvents();
    final index = events.indexWhere((e) => e.id == id);
    if (index >= 0) {
      events[index].status = 'Finalizado';
      await EventStorage.saveEvents(events);
    }
    await stopQrServer();
    if (mounted) Navigator.pop(context);
  }

  // ==========================================================
  // RETAKE
  // ==========================================================

  void retakePhoto() {
    unawaited(stopQrServer());
    _invalidateBrandedPhotoCache();
    setState(() {
      photo = null;
      countdown = 0;
    });
  }

  // ==========================================================
  // SETTINGS
  // ==========================================================

  void _openProtectedSettings() {
    showSettings();
  }

  void showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      showDragHandle: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (
            context,
            sheetSetState,
          ) {
            return Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                20,
                10,
                20,
                30,
              ),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.admin_panel_settings, color: kPurple),
                      SizedBox(width: 8),
                      Text(
                        'CONFIGURACIÓN',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Temporizador',
                        ),
                      ),
                      DropdownButton<int>(
                        value:
                            countdownSeconds,
                        items: const [
                          DropdownMenuItem(
                            value: 3,
                            child: Text(
                              '3 segundos',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 5,
                            child: Text(
                              '5 segundos',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 10,
                            child: Text(
                              '10 segundos',
                            ),
                          ),
                        ],
                        onChanged:
                            (value) {
                          if (value ==
                              null) {
                            return;
                          }

                          sheetSetState(() {
                            countdownSeconds =
                                value;
                          });

                          setState(() {});
                        },
                      ),
                    ],
                  ),

                  const Divider(),

                  ListTile(
                    leading:
                        const Icon(
                      Icons.photo,
                    ),
                    title: const Text(
                      'Elegir marco',
                    ),
                    onTap: () {
                      Navigator.pop(
                        context,
                      );
                      selectFrame();
                    },
                  ),

                  ListTile(
                    leading:
                        const Icon(
                      Icons
                          .branding_watermark,
                    ),
                    title: const Text(
                      'Elegir logo',
                    ),
                    onTap: () {
                      Navigator.pop(
                        context,
                      );
                      selectWatermark();
                    },
                  ),

                  ListTile(
                    leading:
                        const Icon(
                      Icons.delete_outline,
                    ),
                    title: const Text(
                      'Quitar plantilla',
                    ),
                    onTap: () {
                      Navigator.pop(
                        context,
                      );
                      removeOverlay();
                    },
                  ),

                  if (widget.eventId != null)
                    ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: const Text('Finalizar evento'),
                      onTap: () {
                        Navigator.pop(context);
                        finalizeEvent();
                      },
                    ),

                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // CAMERA SCREEN
  // ==========================================================

  Widget buildCameraScreen() {
    final c = controller;

    if (c == null ||
        !c.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: kPurple,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
          fit: StackFit.expand,
          children: [
            // PREVIEW A PANTALLA COMPLETA
            // La cámara ocupa todo el display del iPad.
            // BoxFit.cover elimina las franjas negras y mantiene la
            // proporción de la cámara recortando únicamente los bordes
            // que sobren para llenar toda la pantalla.
            Positioned.fill(
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: c.value.previewSize?.height ?? 1080,
                    height: c.value.previewSize?.width ?? 1920,
                    child: CameraPreview(c),
                  ),
                ),
              ),
            ),

            // OSCURECIMIENTO
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration:
                      BoxDecoration(
                    gradient:
                        LinearGradient(
                      begin:
                          Alignment.topCenter,
                      end:
                          Alignment.bottomCenter,
                      colors: [
                        Colors.black
                            .withValues(
                          alpha: .35,
                        ),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black
                            .withValues(
                          alpha: .45,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // EVENTO
            Positioned(
              top: 18,
              left: 15,
              right: 15,
              child: Column(
                children: [
                  const Text(
                    'PALOMITOPTY',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight:
                          FontWeight.bold,
                      letterSpacing: 4,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'BOOTH',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    eventName,
                    textAlign:
                        TextAlign.center,
                    style:
                        const TextStyle(
                      fontSize: 12,
                      color:
                          Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            // HD
            Positioned(
              top: 20,
              right: 15,
              child: _smallButton(
                icon: Icons.hd,
                onPressed: () {},
                active: true,
              ),
            ),

            // FLASH
            Positioned(
              top: 70,
              right: 15,
              child: _smallButton(
                icon: flashEnabled
                    ? Icons.flash_on
                    : Icons.flash_off,
                onPressed:
                    toggleFlash,
                active:
                    flashEnabled,
              ),
            ),

            // CAMBIO DE CÁMARA
            Positioned(
              top: 120,
              right: 15,
              child: _smallButton(
                icon:
                    Icons.flip_camera_ios,
                onPressed:
                    switchCamera,
              ),
            ),

            // CONFIGURACIÓN
            Positioned(
              top: 170,
              right: 15,
              child: _smallButton(
                icon:
                    Icons.settings,
                onPressed:
                    _openProtectedSettings,
              ),
            ),

            // CUENTA REGRESIVA
            if (countdown > 0)
              Positioned.fill(
                child: Center(
                  child:
                      AnimatedScale(
                    scale: 1,
                    duration:
                        const Duration(
                      milliseconds:
                          200,
                    ),
                    child:
                        Container(
                      width: 160,
                      height: 160,
                      decoration:
                          BoxDecoration(
                        shape:
                            BoxShape
                                .circle,
                        color: Colors
                            .black
                            .withValues(
                          alpha: .75,
                        ),
                        border:
                            Border.all(
                          color:
                              kPurple,
                          width: 7,
                        ),
                      ),
                      alignment:
                          Alignment
                              .center,
                      child:
                          Text(
                        '$countdown',
                        style:
                            const TextStyle(
                          fontSize:
                              92,
                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // CAPTURE
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Center(
                child:
                    GestureDetector(
                  onTap:
                      countdown > 0 ||
                              isSaving ||
                              isPrinting
                          ? null
                          : startCountdown,
                  child:
                      Container(
                    width: 100,
                    height: 100,
                    decoration:
                        BoxDecoration(
                      shape:
                          BoxShape
                              .circle,
                      color:
                          Colors.white,
                      border:
                          Border.all(
                        color:
                            kPurple,
                        width: 8,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color:
                              Colors
                                  .black54,
                          blurRadius:
                              20,
                        ),
                      ],
                    ),
                    child:
                        const Icon(
                      Icons
                          .camera_alt,
                      color:
                          Colors.black,
                      size: 45,
                    ),
                  ),
                ),
              ),
            ),

            // TEMPORIZADOR
            Positioned(
              bottom: 42,
              right: 20,
              child: Text(
                '${countdownSeconds}s',
                style:
                    const TextStyle(
                  color:
                      Colors.white70,
                  fontWeight:
                      FontWeight
                          .bold,
                ),
              ),
            ),
          ],
        ),
    );
  }

  // ==========================================================
  // REVIEW
  // ==========================================================

  Widget buildReviewScreen() {
    return Scaffold(
      backgroundColor: kDark,
      appBar: AppBar(
        title: const Text(
          'RESULTADO',
        ),
        backgroundColor:
            Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 18,
                ),
                child:
                    Container(
                  decoration:
                      BoxDecoration(
                    color:
                        Colors.black,
                    border:
                        Border.all(
                      color:
                          Colors.white12,
                    ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      18,
                    ),
                  ),
                  clipBehavior:
                      Clip.antiAlias,
                  child:
                      Image.file(
                    File(
                      photo!.path,
                    ),
                    fit:
                        BoxFit.contain,
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            const Text(
              'ORIENTACIÓN',
              style:
                  TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color:
                    Colors.white54,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .center,
              children: [
                orientationButton(
                  '6 × 4',
                  orientation ==
                      PrintOrientation
                          .landscape,
                  () {
                    if (orientation ==
                        PrintOrientation.landscape) {
                      return;
                    }

                    _invalidateBrandedPhotoCache();

                    setState(() {
                      orientation =
                          PrintOrientation
                              .landscape;
                    });

                    if (photo != null) {
                      unawaited(createBrandedPhoto());
                    }
                  },
                ),
                const SizedBox(
                  width: 10,
                ),
                orientationButton(
                  '4 × 6',
                  orientation ==
                      PrintOrientation
                          .portrait,
                  () {
                    if (orientation ==
                        PrintOrientation.portrait) {
                      return;
                    }

                    _invalidateBrandedPhotoCache();

                    setState(() {
                      orientation =
                          PrintOrientation
                              .portrait;
                    });

                    if (photo != null) {
                      unawaited(createBrandedPhoto());
                    }
                  },
                ),
              ],
            ),

            const SizedBox(
              height: 10,
            ),

            // OVERLAYS
            SingleChildScrollView(
              scrollDirection:
                  Axis.horizontal,
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 12,
              ),
              child: Row(
                children: [
                  _reviewButton(
                    Icons.photo,
                    'MARCO',
                    selectFrame,
                  ),
                  _reviewButton(
                    Icons
                        .branding_watermark,
                    'LOGO',
                    selectWatermark,
                  ),
                  _reviewButton(
                    Icons.qr_code_2,
                    'QR',
                    showQr,
                  ),
                  _reviewButton(
                    Icons.share,
                    'COMPARTIR',
                    sharePhoto,
                  ),
                  _reviewButton(
                    Icons.print,
                    'IMPRIMIR',
                    printPhoto,
                  ),
                  _reviewButton(
                    Icons.delete_outline,
                    'QUITAR',
                    removeOverlay,
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              overlayName,
              style:
                  const TextStyle(
                fontSize: 10,
                color:
                    Colors.white54,
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            // MAIN BUTTONS
            Padding(
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child:
                        ElevatedButton
                            .icon(
                      onPressed:
                          isSaving ||
                                  isPrinting
                              ? null
                              : savePhoto,
                      icon:
                          const Icon(
                        Icons.save,
                      ),
                      label:
                          const Text(
                        'GUARDAR',
                      ),
                      style:
                          ElevatedButton
                              .styleFrom(
                        backgroundColor:
                            kPurple,
                        foregroundColor:
                            Colors.white,
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 13,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    width: 8,
                  ),

                  Expanded(
                    child:
                        OutlinedButton
                            .icon(
                      onPressed:
                          isSaving ||
                                  isPrinting
                              ? null
                              : retakePhoto,
                      icon:
                          const Icon(
                        Icons.refresh,
                      ),
                      label:
                          const Text(
                        'OTRA FOTO',
                      ),
                      style:
                          OutlinedButton
                              .styleFrom(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 12,
            ),
          ],
        ),
      ),
    );
  }

  Widget orientationButton(
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child:
          AnimatedContainer(
        duration:
            const Duration(
          milliseconds: 180,
        ),
        width: 105,
        height: 40,
        decoration:
            BoxDecoration(
          color: selected
              ? kPurple
              : Colors.transparent,
          borderRadius:
              BorderRadius.circular(
            25,
          ),
          border:
              Border.all(
            color: selected
                ? kPurple
                : Colors.white30,
            width: 2,
          ),
        ),
        alignment:
            Alignment.center,
        child: Text(
          label,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _reviewButton(
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Padding(
      padding:
          const EdgeInsets
              .symmetric(
        horizontal: 4,
      ),
      child:
          OutlinedButton(
        onPressed:
            isSaving ||
                    isPrinting
                ? null
                : onTap,
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 19,
            ),
            const SizedBox(
              height: 3,
            ),
            Text(
              label,
              style:
                  const TextStyle(
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child:
          Container(
        width: 43,
        height: 43,
        decoration:
            BoxDecoration(
          color: active
              ? kPurple.withValues(
                  alpha: .85,
                )
              : Colors.black
                  .withValues(
                  alpha: .55,
                ),
          shape:
              BoxShape.circle,
          border:
              Border.all(
            color:
                Colors.white24,
          ),
        ),
        child:
            Icon(
          icon,
          color:
              Colors.white,
          size: 21,
        ),
      ),
    );
  }

  // ==========================================================
  // HELPERS
  // ==========================================================

  void setStateSafe(
    VoidCallback fn,
  ) {
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> showMessage(
    String title,
    String message,
  ) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: kCard,
          title: Text(
            title,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          content: Text(
            message,
            style:
                const TextStyle(
              color:
                  Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
              ),
              child:
                  const Text(
                'CONTINUAR',
              ),
            ),
          ],
        );
      },
    );
  }

  void showError(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }

  // ==========================================================
  // LIFECYCLE
  // ==========================================================

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    final c = controller;

    if (state ==
        AppLifecycleState.inactive) {
      if (c != null) {
        controller = null;

        c.dispose();
      }
    } else if (state ==
        AppLifecycleState.resumed) {
      if (controller == null &&
          mounted) {
        initializeCamera();
      }
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (isInitializing) {
      return const Scaffold(
        backgroundColor:
            Colors.black,
        body: Center(
          child:
              CircularProgressIndicator(
            color: kPurple,
          ),
        ),
      );
    }

    if (photo != null) {
      return buildReviewScreen();
    }

    return buildCameraScreen();
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    WidgetsBinding.instance
        .removeObserver(this);

    countdownTimer?.cancel();

    qrExpirationTimer?.cancel();

    final server = qrServer;

    qrServer = null;

    if (server != null) {
      server.close(
        force: true,
      );
    }

    controller?.dispose();

    super.dispose();
  }
}

// ============================================================
// ENUMS
// ============================================================

enum PrintOrientation {
  landscape,
  portrait,
}

enum OverlayType {
  none,
  frame,
  watermark,
}