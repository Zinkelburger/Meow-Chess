import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../domain/model.dart';

/// Device preferences live outside tournament files and their undo history.
class PrinterPreference {
  PrinterPreference({this.directory});
  final Directory? directory;

  Future<File> get file async {
    final configured = Platform.environment['MEOW_DATA_DIR'];
    final dir =
        directory ??
        (configured == null
            ? await getApplicationSupportDirectory()
            : Directory(configured));
    return File(path.join(dir.path, 'printer.json'));
  }

  Future<Printer?> read() async {
    final f = await file;
    if (!await f.exists()) return null;
    try {
      return Printer.fromMap(jsonDecode(await f.readAsString()) as Map);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> write(Printer printer) async {
    final f = await file;
    await f.parent.create(recursive: true);
    final temporary = File('${f.path}.tmp');
    await temporary.writeAsString(jsonEncode(printer.toMap()), flush: true);
    await temporary.rename(f.path);
  }
}

/// Sends exactly one job; cancellation and failures never trigger a retry.
class RememberedPrinting {
  RememberedPrinting({
    PrinterPreference? preference,
    Future<PrintingInfo> Function()? info,
    Future<List<Printer>> Function()? printers,
    Future<bool> Function(Printer?, Uint8List, String)? send,
  }) : preference = preference ?? PrinterPreference(),
       info = info ?? Printing.info,
       printers = printers ?? Printing.listPrinters,
       send = send ?? _send;

  static final shared = RememberedPrinting();
  final PrinterPreference preference;
  final Future<PrintingInfo> Function() info;
  final Future<List<Printer>> Function() printers;
  final Future<bool> Function(Printer?, Uint8List, String) send;
  bool busy = false;

  static Future<bool> _send(
    Printer? printer,
    Uint8List bytes,
    String name,
  ) async => printer == null
      ? Printing.layoutPdf(
          onLayout: (_) => bytes,
          name: name,
          format: PdfPageFormat.letter,
          dynamicLayout: false,
        )
      : Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) => bytes,
          name: name,
          format: PdfPageFormat.letter,
          dynamicLayout: false,
        );

  Future<bool> print(
    Uint8List bytes,
    String name, {
    required Future<Printer?> Function(List<Printer>) choose,
    bool changePrinter = false,
    void Function(Object)? onPreferenceError,
  }) async {
    if (busy) return false;
    busy = true;
    try {
      final capabilities = await info();
      if (!capabilities.canPrint) {
        throw const TournamentException(
          'Printing is not available on this computer.',
        );
      }
      if (!capabilities.directPrint || !capabilities.canListPrinters) {
        return await send(null, bytes, name);
      }
      final available = (await printers()).where((p) => p.isAvailable).toList();
      if (available.isEmpty) {
        throw const TournamentException(
          'No printers are available. Connect a printer and try again.',
        );
      }
      Printer? saved;
      try {
        saved = await preference.read();
      } catch (e) {
        onPreferenceError?.call(e);
      }
      var printer = changePrinter
          ? null
          : available.where((p) => p.url == saved?.url).firstOrNull;
      printer ??= await choose(available);
      if (printer == null) return false;
      final success = await send(printer, bytes, name);
      if (success) {
        try {
          await preference.write(printer);
        } catch (e) {
          onPreferenceError?.call(e);
        }
      }
      return success;
    } finally {
      busy = false;
    }
  }
}
